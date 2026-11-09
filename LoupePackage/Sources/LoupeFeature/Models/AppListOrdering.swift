import Foundation

/// How the app picker orders and searches the open apps
enum AppListOrdering {

    /// The selected app first, then the apps used most recently, then the rest alphabetically
    static func ordered(_ apps: [TargetApp], selectedID: pid_t?, recentIDs: [pid_t]) -> [TargetApp] {
        func rank(_ app: TargetApp) -> Int {
            if app.id == selectedID { return -1 }
            return recentIDs.firstIndex(of: app.id) ?? Int.max
        }
        return apps.sorted { a, b in
            let rankA = rank(a), rankB = rank(b)
            if rankA != rankB { return rankA < rankB }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    /// Apps whose name matches the search. Names that start with it (or have a word that does)
    /// come first; otherwise the existing order is kept.
    static func filtered(_ apps: [TargetApp], query: String) -> [TargetApp] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return apps }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

        func startsWithNeedle(_ app: TargetApp) -> Bool {
            app.name.range(of: needle, options: options.union(.anchored)) != nil
                || app.name.split(separator: " ").contains {
                    $0.range(of: needle, options: options.union(.anchored)) != nil
                }
        }

        let matches = apps.filter { $0.name.range(of: needle, options: options) != nil }
        return matches.filter(startsWithNeedle) + matches.filter { !startsWithNeedle($0) }
    }

    /// Record that an app was just used: it moves to the front of the recent list
    static func noting(_ id: pid_t, in recentIDs: [pid_t], limit: Int = 30) -> [pid_t] {
        Array(([id] + recentIDs.filter { $0 != id }).prefix(limit))
    }
}
