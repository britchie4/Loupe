import Foundation
import Darwin

/// The private local connection between the Loupe app and its agent relay.
///
/// It is a Unix domain socket in the user's own temporary folder, readable and writable
/// only by this Mac user, and the server rejects connections from any other user.
/// Messages are newline-delimited JSON, matching MCP's stdio transport.
public enum AgentLinkSocket {

    /// Where the socket lives for a given app bundle (Debug and Release builds get separate sockets)
    public static func path(bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> String {
        let folder = userTemporaryDirectory()
        return (folder as NSString).appendingPathComponent("\(bundleIdentifier ?? "Loupe").agent-link.sock")
    }

    /// The per-user temporary folder, read from the system rather than $TMPDIR,
    /// so the app and an agent-launched relay always agree on it
    private static func userTemporaryDirectory() -> String {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, buffer.count)
        if length > 0, let path = String(validatingCString: buffer) {
            return path
        }
        return NSTemporaryDirectory()
    }

    /// Fill a sockaddr_un for a path; nil if the path is too long for a socket
    static func address(for path: String) -> sockaddr_un? {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let maxLength = MemoryLayout.size(ofValue: address.sun_path)
        guard path.utf8.count < maxLength else { return nil }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: maxLength) { chars in
                _ = path.withCString { strncpy(chars, $0, maxLength - 1) }
            }
        }
        return address
    }

    /// Connect to a listening socket. Returns the file descriptor, or nil if nothing is listening.
    public static func connect(path: String) -> Int32? {
        guard var address = address(for: path) else { return nil }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard result == 0 else {
            close(fd)
            return nil
        }
        return fd
    }

    /// Write all bytes to a descriptor, retrying on partial writes
    @discardableResult
    static func writeAll(_ data: Data, to fd: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            guard var pointer = buffer.baseAddress else { return true }
            var remaining = buffer.count
            while remaining > 0 {
                let written = Darwin.write(fd, pointer, remaining)
                if written < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                remaining -= written
                pointer = pointer.advanced(by: written)
            }
            return true
        }
    }
}

// MARK: - Line Splitting

/// Collects bytes and hands back complete newline-terminated lines
struct LineBuffer {
    private var pending = Data()

    mutating func append(_ data: Data) -> [Data] {
        pending.append(data)
        var lines: [Data] = []
        while let newline = pending.firstIndex(of: 0x0A) {
            let line = pending[pending.startIndex..<newline]
            pending.removeSubrange(pending.startIndex...newline)
            if !line.allSatisfy({ $0 == 0x20 || $0 == 0x0D || $0 == 0x09 }) {
                lines.append(Data(line))
            }
        }
        return lines
    }
}

// MARK: - Server

/// Listens on the Agent Link socket and passes each received line to a handler.
/// All socket work happens on one private serial queue.
final class AgentLinkSocketServer: @unchecked Sendable {

    enum StartError: Error, Equatable {
        case pathTooLong
        case alreadyInUse
        case system(String)
    }

    typealias ConnectionID = Int

    /// Called on the server's queue for each complete line
    var onLine: (@Sendable (ConnectionID, Data) -> Void)?
    /// Called on the server's queue when a connection opens or closes
    var onConnectionChange: (@Sendable (ConnectionID, Bool) -> Void)?

    let path: String
    private let queue = DispatchQueue(label: "com.loupe.agent-link.socket")
    private var listenFD: Int32 = -1
    private var acceptSource: DispatchSourceRead?
    private var connections: [ConnectionID: Connection] = [:]
    private var nextID = 1

    private final class Connection {
        let fd: Int32
        let source: DispatchSourceRead
        var buffer = LineBuffer()
        init(fd: Int32, source: DispatchSourceRead) {
            self.fd = fd
            self.source = source
        }
    }

    init(path: String) {
        self.path = path
    }

    deinit {
        stopOnQueue()
    }

    /// Start listening. Fails if another copy of Loupe is already serving this socket.
    func start() throws(StartError) {
        var failure: StartError?
        queue.sync {
            do throws(StartError) { try startOnQueue() } catch { failure = error }
        }
        if let failure { throw failure }
    }

    func stop() {
        queue.sync { stopOnQueue() }
    }

    /// Send a line to one connection
    func send(_ data: Data, to id: ConnectionID) {
        queue.async { [weak self] in
            guard let self, let connection = self.connections[id] else { return }
            if !AgentLinkSocket.writeAll(data, to: connection.fd) {
                self.closeConnection(id)
            }
        }
    }

    var connectionCount: Int {
        queue.sync { connections.count }
    }

    // MARK: - Queue-confined work

    private func startOnQueue() throws(StartError) {
        guard listenFD < 0 else { return }
        guard var address = AgentLinkSocket.address(for: path) else { throw .pathTooLong }

        // A live server means another copy of Loupe owns the socket; a dead file is just stale
        if let existing = AgentLinkSocket.connect(path: path) {
            close(existing)
            throw .alreadyInUse
        }
        unlink(path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .system(String(cString: strerror(errno))) }

        // Create the socket file with owner-only permissions
        let previousMask = umask(0o077)
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        umask(previousMask)
        guard bound == 0, listen(fd, 8) == 0 else {
            let message = String(cString: strerror(errno))
            close(fd)
            throw .system(message)
        }
        chmod(path, 0o600)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        listenFD = fd
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.acceptPending() }
        source.resume()
        acceptSource = source
    }

    private func stopOnQueue() {
        for id in Array(connections.keys) {
            closeConnection(id)
        }
        acceptSource?.cancel()
        acceptSource = nil
        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
            unlink(path)
        }
    }

    private func acceptPending() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }

            // Only this Mac user may connect
            var uid: uid_t = 0
            var gid: gid_t = 0
            guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
                close(fd)
                continue
            }

            var noSigPipe: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            // Reads only happen when data is waiting, so blocking mode keeps writes simple
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK)

            let id = nextID
            nextID += 1
            let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            source.setEventHandler { [weak self] in self?.readAvailable(id) }
            connections[id] = Connection(fd: fd, source: source)
            source.resume()
            onConnectionChange?(id, true)
        }
    }

    private func readAvailable(_ id: ConnectionID) {
        guard let connection = connections[id] else { return }
        var bytes = [UInt8](repeating: 0, count: 64 * 1024)
        let count = read(connection.fd, &bytes, bytes.count)
        guard count > 0 else {
            if count < 0, errno == EAGAIN || errno == EINTR { return }
            closeConnection(id)
            return
        }
        for line in connection.buffer.append(Data(bytes[0..<count])) {
            onLine?(id, line)
        }
    }

    private func closeConnection(_ id: ConnectionID) {
        guard let connection = connections.removeValue(forKey: id) else { return }
        connection.source.cancel()
        close(connection.fd)
        onConnectionChange?(id, false)
    }
}
