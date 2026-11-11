import AppKit
import SwiftUI
import WebKit

// The practice app's page, shown in a web view.
//
// The page is the one place in Loupe where an agent's own writing is displayed, so the web
// view is locked down: the page's own JavaScript never runs, nothing is loaded from outside
// (the document's policy allows inline styles and inline images only), and it can't navigate
// anywhere. The only script is Loupe's (`PracticePage.bridgeScript`), which runs in its own
// world, apart from the page.

/// What the page last reported about itself
@Observable @MainActor
final class PracticePageState {
    /// The element under the pointer, and where it is in the page
    var hover: (element: PracticeElement, frame: CGRect)?
    /// Where each noted element is in the page, by key. An element that has gone from the
    /// page keeps its last place, so its badge and note stay where the person left them.
    var frames: [String: CGRect] = [:]
}

struct PracticePageWebView: NSViewRepresentable {
    let session: PracticeSession
    let page: PracticePageState

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, page: page)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.websiteDataStore = .nonPersistent()
        let world = WKContentWorld.defaultClient
        configuration.userContentController.add(context.coordinator, contentWorld: world, name: "loupe")
        configuration.userContentController.addUserScript(
            WKUserScript(source: PracticePage.bridgeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: world)
        )

        let webView = InertWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsMagnification = false
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        // Let the practice app's own background show through
        webView.setValue(false, forKey: "drawsBackground")
        webView.setAccessibilityLabel("Practice app")
        context.coordinator.webView = webView
        webView.loadHTMLString(PracticePage.document, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        let model = session.model
        var tracked = model.finishedNotes.keys.map(\.id)
        if let selected = model.selected { tracked.append(selected.id) }
        context.coordinator.push(PageUpdate(
            html: model.pageHTML,
            pickable: model.canPickElement,
            tracked: tracked.sorted()
        ))
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "loupe", contentWorld: .defaultClient)
    }

    /// Everything the page needs to show the practice app as it is now
    struct PageUpdate {
        let html: String
        let pickable: Bool
        let tracked: [String]

        var json: String? {
            let object: [String: Any] = ["html": html, "pickable": pickable, "tracked": tracked]
            guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
            return String(data: data, encoding: .utf8)
        }
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        private let session: PracticeSession
        private let page: PracticePageState
        weak var webView: WKWebView?

        private var isReady = false
        private var didStartLoading = false
        private var pending: String?
        private var lastSent: String?

        init(session: PracticeSession, page: PracticePageState) {
            self.session = session
            self.page = page
        }

        func push(_ update: PageUpdate) {
            guard let json = update.json, json != lastSent else { return }
            guard isReady else { pending = json; return }
            lastSent = json
            webView?.evaluateJavaScript("window.loupe.update(\(json));", in: nil, in: .defaultClient)
        }

        // MARK: From the page

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "ready":
                isReady = true
                if let pending {
                    self.pending = nil
                    lastSent = pending
                    webView?.evaluateJavaScript("window.loupe.update(\(pending));", in: nil, in: .defaultClient)
                }
            case "hover":
                if let found = Self.element(from: body["element"]) {
                    // Not picked yet, so it may have no key of its own: any stand-in will do
                    let element = found.element.id.isEmpty
                        ? PracticeElement(id: "~pointer", role: found.element.role, title: found.element.title)
                        : found.element
                    page.hover = (element, found.frame)
                    session.hover(element)
                } else if let previous = page.hover?.element {
                    page.hover = nil
                    session.unhover(previous)
                }
            case "select":
                guard let found = Self.element(from: body["element"]), !found.element.id.isEmpty else { return }
                page.frames[found.element.id] = found.frame
                page.hover = nil
                session.select(found.element)
            case "frames":
                if let frames = body["frames"] as? [String: Any] {
                    for (key, value) in frames {
                        if let frame = Self.rect(from: value) { page.frames[key] = frame }
                    }
                }
                if let frame = Self.rect(from: body["hover"]), let hover = page.hover {
                    page.hover = (hover.element, frame)
                }
            case "snapshot":
                if let html = body["html"] as? String { session.pageWasRendered(html) }
            default:
                break
            }
        }

        private static func element(from value: Any?) -> (element: PracticeElement, frame: CGRect)? {
            guard let info = value as? [String: Any],
                  let role = info["role"] as? String,
                  let frame = rect(from: info["rect"]) else { return nil }
            let element = PracticeElement(
                id: info["key"] as? String ?? "",
                role: role,
                title: info["title"] as? String ?? ""
            )
            return (element, frame)
        }

        private static func rect(from value: Any?) -> CGRect? {
            guard let numbers = value as? [NSNumber], numbers.count == 4 else { return nil }
            return CGRect(x: numbers[0].doubleValue, y: numbers[1].doubleValue, width: numbers[2].doubleValue, height: numbers[3].doubleValue)
        }

        // MARK: Staying put

        /// The page is loaded once and never goes anywhere else
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
            if !didStartLoading, navigationAction.navigationType == .other {
                didStartLoading = true
                return .allow
            }
            return .cancel
        }
    }
}

/// A web view with nothing of a browser about it: no menu on right-click
private final class InertWebView: WKWebView {
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()
    }
}
