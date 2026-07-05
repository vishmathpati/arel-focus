import Foundation

// Rich per-row aggregates for the Apps / Websites / Chrome Tabs pages.
// Computed on demand from `todaySessions`; cheap because today is bounded.

struct AppRowDetail: Identifiable {
    var id: String { appName }
    let appName: String
    let bundleID: String?
    let activeDuration: TimeInterval
    let openDuration: TimeInterval
    let firstSeen: Date?
    let lastSeen: Date?
    let windowCount: Int
    let displayNames: [String]

    var totalDuration: TimeInterval { activeDuration + openDuration }
}

struct DomainRowDetail: Identifiable {
    var id: String { domain }
    let domain: String
    let activeDuration: TimeInterval
    let openDuration: TimeInterval
    let firstSeen: Date?
    let lastSeen: Date?
    let distinctTabs: Int
    let topURL: String?
    let topTitle: String?
    let favIconURL: String?
    let favIconDataURL: String?

    var totalDuration: TimeInterval { activeDuration + openDuration }
}

struct ChromeTabRowDetail: Identifiable {
    let id: String
    let title: String
    let domain: String
    let url: String?
    let activeDuration: TimeInterval
    let openDuration: TimeInterval
    let firstSeen: Date?
    let lastSeen: Date?
    let favIconURL: String?
    let favIconDataURL: String?
    let profileLabel: String?

    var totalDuration: TimeInterval { activeDuration + openDuration }
}

struct AttentionAppInsight: Identifiable {
    var id: String { bundleID ?? name }
    let name: String
    let bundleID: String?
    let focused: TimeInterval
    let open: TimeInterval
    let firstSeen: Date?
    let lastSeen: Date?
    let windowCount: Int
    let displayNames: [String]

    var totalContext: TimeInterval { focused + open }
}

struct AttentionWebsiteInsight: Identifiable {
    var id: String { domain }
    let domain: String
    let title: String?
    let displayURL: String?
    let focused: TimeInterval
    let open: TimeInterval
    let firstSeen: Date?
    let lastSeen: Date?
    let tabCount: Int
    let favIconURL: String?
    let favIconDataURL: String?
    let focusHourTouches: Int

    var totalContext: TimeInterval { focused + open }
    var focusRatio: Double {
        guard totalContext > 0 else { return 0 }
        return focused / totalContext
    }
}

struct AttentionTabInsight: Identifiable {
    let id: String
    let title: String
    let domain: String
    let displayURL: String?
    let focused: TimeInterval
    let open: TimeInterval
    let firstSeen: Date?
    let lastSeen: Date?
    let favIconURL: String?
    let favIconDataURL: String?
    let profileLabel: String?
    let isOpenNow: Bool
    let isActiveNow: Bool

    var totalContext: TimeInterval { focused + open }
}

struct FocusHourInsight: Identifiable {
    let id: String
    let state: FocusHourRuntimeState
    let projectName: String
    let taskName: String?
    let profileName: String
    let startedAt: Date
    let endedAt: Date?
    let plannedMinutes: Int
    let actualMinutes: Int
    let apps: [String]
    let websites: [String]
    let blockedAttempts: [String]
    let rescued: Bool
}

@MainActor
extension FocusStore {

    // MARK: - Top-line metrics

    var todayActiveAppDuration: TimeInterval {
        unionDuration(todaySessions.filter { $0.kind == .activeApp })
    }

    var todayOpenAppDuration: TimeInterval {
        todaySessions
            .filter { $0.kind == .backgroundApp }
            .reduce(0) { $0 + $1.duration }
    }

    var todayActiveChromeDuration: TimeInterval {
        unionDuration(todaySessions.filter { $0.kind == .chromeTab })
    }

    var todayOpenChromeDuration: TimeInterval {
        todaySessions
            .filter { $0.kind == .openChromeTab }
            .reduce(0) { $0 + $1.duration }
    }

    var todayDistinctAppCount: Int {
        Set(todaySessions
            .filter { $0.kind == .activeApp || $0.kind == .backgroundApp }
            .map { $0.bundleID ?? $0.sourceName }
        ).count
    }

    var todayDistinctDomainCount: Int {
        Set(todaySessions
            .filter { $0.kind == .chromeTab || $0.kind == .openChromeTab }
            .compactMap { $0.domain }
        ).count
    }

    var todayScreenOnDuration: TimeInterval {
        todayActiveDuration + todayIdleDuration
    }

    var todayReviewCandidateCount: Int {
        reviewCandidates(in: .today).count
    }

    var todayFocusHourInsights: [FocusHourInsight] {
        focusHourInsights.filter { Calendar.current.isDateInToday($0.startedAt) }
    }

    var focusHourInsights: [FocusHourInsight] {
        var rows = focusHourBridge.loadResults().map(FocusHourInsight.init(result:))

        if focusHourState.state != .idle {
            rows.insert(FocusHourInsight(state: focusHourState), at: 0)
        }

        return rows
    }

    func appInsights(limit: Int? = nil) -> [AttentionAppInsight] {
        let rows = appRowDetails()
            .filter { !Self.isSystemNoiseApp(name: $0.appName, bundleID: $0.bundleID) }
            .map { row in
                AttentionAppInsight(
                    name: ReadableLabels.appName(row.appName),
                    bundleID: row.bundleID,
                    focused: row.activeDuration,
                    open: row.openDuration,
                    firstSeen: row.firstSeen,
                    lastSeen: row.lastSeen,
                    windowCount: row.windowCount,
                    displayNames: row.displayNames
                )
            }
            .sorted { lhs, rhs in
                if lhs.focused == rhs.focused {
                    return lhs.open > rhs.open
                }
                return lhs.focused > rhs.focused
            }

        guard let limit else { return rows }
        return Array(rows.prefix(limit))
    }

    func websiteInsights(limit: Int? = nil) -> [AttentionWebsiteInsight] {
        let focusHourSites = focusHourSiteTouches()
        let rows = domainRowDetails()
            .filter { !$0.domain.isEmpty && $0.domain != "Unknown" }
            .map { row in
                AttentionWebsiteInsight(
                    domain: row.domain,
                    title: readableTitle(row.topTitle, fallback: row.domain),
                    displayURL: displayURL(row.topURL),
                    focused: row.activeDuration,
                    open: row.openDuration,
                    firstSeen: row.firstSeen,
                    lastSeen: row.lastSeen,
                    tabCount: row.distinctTabs,
                    favIconURL: row.favIconURL,
                    favIconDataURL: row.favIconDataURL,
                    focusHourTouches: focusHourSites[row.domain, default: 0]
                )
            }
            .sorted { lhs, rhs in
                if lhs.focused == rhs.focused {
                    return lhs.open > rhs.open
                }
                return lhs.focused > rhs.focused
            }

        guard let limit else { return rows }
        return Array(rows.prefix(limit))
    }

    func openPressureWebsiteInsights(limit: Int = 8) -> [AttentionWebsiteInsight] {
        Array(websiteInsights()
            .filter { $0.open > $0.focused }
            .sorted { ($0.open - $0.focused) > ($1.open - $1.focused) }
            .prefix(limit))
    }

    func tabInsights(limit: Int? = nil) -> [AttentionTabInsight] {
        let openNow = Dictionary(uniqueKeysWithValues: latestChromeTabs.map { ($0.id, $0) })
        let rows = chromeTabRowDetails().map { row in
            let openTab = openNow.values.first { tab in
                tab.url == row.url || (tab.title == row.title && insightDomain(from: tab.url) == row.domain)
            }
            return AttentionTabInsight(
                id: row.id,
                title: readableTitle(row.title, fallback: row.domain) ?? row.domain,
                domain: row.domain,
                displayURL: displayURL(row.url),
                focused: row.activeDuration,
                open: row.openDuration,
                firstSeen: row.firstSeen,
                lastSeen: row.lastSeen,
                favIconURL: row.favIconURL,
                favIconDataURL: row.favIconDataURL,
                profileLabel: row.profileLabel,
                isOpenNow: openTab != nil,
                isActiveNow: openTab?.active ?? false
            )
        }
        .sorted { lhs, rhs in
            if lhs.isActiveNow != rhs.isActiveNow { return lhs.isActiveNow }
            if lhs.isOpenNow != rhs.isOpenNow { return lhs.isOpenNow }
            if lhs.focused == rhs.focused { return lhs.open > rhs.open }
            return lhs.focused > rhs.focused
        }

        guard let limit else { return rows }
        return Array(rows.prefix(limit))
    }

    func openNowTabInsights() -> [AttentionTabInsight] {
        latestChromeTabs.map { tab in
            AttentionTabInsight(
                id: "\(tab.profileID ?? "default")|\(tab.windowID)|\(tab.tabID)|\(tab.url ?? "")",
                title: readableTitle(tab.title, fallback: tab.url ?? "Untitled tab") ?? "Untitled tab",
                domain: insightDomain(from: tab.url) ?? "Chrome",
                displayURL: displayURL(tab.url),
                focused: 0,
                open: 0,
                firstSeen: nil,
                lastSeen: nil,
                favIconURL: tab.favIconURL,
                favIconDataURL: tab.favIconDataURL,
                profileLabel: chromeProfileLabel(for: tab),
                isOpenNow: true,
                isActiveNow: tab.active
            )
        }
        .sorted {
            if $0.isActiveNow != $1.isActiveNow { return $0.isActiveNow }
            return $0.domain < $1.domain
        }
    }

    // MARK: - Per-app rich rows

    func appRowDetails() -> [AppRowDetail] {
        var grouped: [String: (active: TimeInterval, open: TimeInterval, first: Date?, last: Date?, bundle: String?, windows: Int, displays: Set<String>)] = [:]

        for s in todaySessions where s.kind == .activeApp || s.kind == .backgroundApp {
            let key = s.sourceName
            var entry = grouped[key] ?? (0, 0, nil, nil, nil, 0, [])
            if s.kind == .activeApp { entry.active += s.duration }
            if s.kind == .backgroundApp { entry.open += s.duration }
            if entry.first == nil || s.startedAt < entry.first! { entry.first = s.startedAt }
            if entry.last == nil || s.endedAt > entry.last! { entry.last = s.endedAt }
            if entry.bundle == nil { entry.bundle = s.bundleID }
            entry.windows = max(entry.windows, s.windowCount ?? 0)
            if let names = s.displayNames { entry.displays.formUnion(names) }
            grouped[key] = entry
        }

        return grouped.map { (name, e) in
            AppRowDetail(
                appName: name,
                bundleID: e.bundle,
                activeDuration: e.active,
                openDuration: e.open,
                firstSeen: e.first,
                lastSeen: e.last,
                windowCount: e.windows,
                displayNames: Array(e.displays).sorted()
            )
        }
        .sorted { $0.totalDuration > $1.totalDuration }
    }

    // MARK: - Per-domain rich rows

    func domainRowDetails() -> [DomainRowDetail] {
        struct Bucket {
            var active: TimeInterval = 0
            var open: TimeInterval = 0
            var first: Date?
            var last: Date?
            var tabIDs = Set<String>()
            var topTitle: String?
            var topURL: String?
            var topDuration: TimeInterval = 0
            var favIconURL: String?
            var favIconDataURL: String?
        }

        var buckets: [String: Bucket] = [:]

        for s in todaySessions where s.kind == .chromeTab || s.kind == .openChromeTab {
            let domain = s.domain ?? "Unknown"
            var b = buckets[domain] ?? Bucket()
            if s.kind == .chromeTab { b.active += s.duration }
            if s.kind == .openChromeTab { b.open += s.duration }
            if b.first == nil || s.startedAt < b.first! { b.first = s.startedAt }
            if b.last == nil || s.endedAt > b.last! { b.last = s.endedAt }
            if let tabID = s.tabID { b.tabIDs.insert("\(s.windowID ?? -1)-\(tabID)") }
            if s.duration > b.topDuration {
                b.topDuration = s.duration
                b.topTitle = s.detail.isEmpty ? nil : s.detail
                b.topURL = s.url
            }
            if b.favIconURL == nil { b.favIconURL = s.favIconURL }
            if b.favIconDataURL == nil { b.favIconDataURL = s.favIconDataURL }
            buckets[domain] = b
        }

        return buckets.map { (domain, b) in
            DomainRowDetail(
                domain: domain,
                activeDuration: b.active,
                openDuration: b.open,
                firstSeen: b.first,
                lastSeen: b.last,
                distinctTabs: b.tabIDs.count,
                topURL: b.topURL,
                topTitle: b.topTitle,
                favIconURL: b.favIconURL,
                favIconDataURL: b.favIconDataURL
            )
        }
        .sorted { $0.totalDuration > $1.totalDuration }
    }

    // MARK: - Per-tab rich rows

    func chromeTabRowDetails() -> [ChromeTabRowDetail] {
        struct Bucket {
            var session: ActivitySession
            var active: TimeInterval = 0
            var open: TimeInterval = 0
            var first: Date?
            var last: Date?
        }

        var buckets: [String: Bucket] = [:]

        for s in todaySessions where s.kind == .chromeTab || s.kind == .openChromeTab {
            // Key by (domain + tabID + windowID) so two different tabs on the
            // same domain stay separate, but the same tab's active and open
            // ledgers fold into one row.
            let key = "\(s.domain ?? "?")|\(s.windowID ?? -1)|\(s.tabID ?? -1)"
            var b = buckets[key] ?? Bucket(session: s)
            if s.kind == .chromeTab { b.active += s.duration }
            if s.kind == .openChromeTab { b.open += s.duration }
            if b.first == nil || s.startedAt < b.first! { b.first = s.startedAt }
            if b.last == nil || s.endedAt > b.last! { b.last = s.endedAt }
            // Prefer the active session as the canonical row source.
            if s.kind == .chromeTab { b.session = s }
            buckets[key] = b
        }

        return buckets.map { (key, b) in
            ChromeTabRowDetail(
                id: key,
                title: b.session.detail.isEmpty ? (b.session.domain ?? "Untitled tab") : b.session.detail,
                domain: b.session.domain ?? "Unknown",
                url: b.session.url,
                activeDuration: b.active,
                openDuration: b.open,
                firstSeen: b.first,
                lastSeen: b.last,
                favIconURL: b.session.favIconURL,
                favIconDataURL: b.session.favIconDataURL,
                profileLabel: chromeProfileLabel(for: b.session)
            )
        }
        .sorted { $0.totalDuration > $1.totalDuration }
    }

    private func focusHourSiteTouches() -> [String: Int] {
        var counts: [String: Int] = [:]
        for result in focusHourBridge.loadResults() {
            for domain in result.planning.websitesVisited + result.work.websitesUsed {
                counts[domain, default: 0] += 1
            }
        }
        return counts
    }

    private func readableTitle(_ title: String?, fallback: String) -> String? {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty, trimmed.lowercased() != fallback.lowercased() else { return nil }
        return trimmed
    }

    private func displayURL(_ rawURL: String?) -> String? {
        guard let rawURL, let components = URLComponents(string: rawURL) else {
            return rawURL
        }

        let host = components.host ?? ""
        let path = components.path
        let value = "\(host)\(path)"
        return value.isEmpty ? nil : value
    }

    private func insightDomain(from rawURL: String?) -> String? {
        guard let rawURL else { return nil }
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let value = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URLComponents(string: value)?.host else {
            return trimmed.lowercased()
        }

        let lowercased = host.lowercased()
        return lowercased.hasPrefix("www.") ? String(lowercased.dropFirst(4)) : lowercased
    }

    private static func isSystemNoiseApp(name: String, bundleID: String?) -> Bool {
        let app = name
            .replacingOccurrences(of: "\u{200E}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let bundle = (bundleID ?? "").lowercased()

        let noisyNames: Set<String> = [
            "loginwindow",
            "usernotificationcenter",
            "universalaccesscontrol",
            "universalaccessauthwarn",
            "coreservicesuiagent",
            "cleanmymac menu"
        ]

        if noisyNames.contains(app) { return true }
        if bundle.hasPrefix("com.apple.notificationcenter") { return true }
        if bundle.hasPrefix("com.apple.loginwindow") { return true }
        if bundle.hasPrefix("com.apple.universalaccess") { return true }
        if bundle.hasPrefix("com.macpaw.cleanmymac") { return true }
        return false
    }
}

private extension FocusHourInsight {
    init(result: FocusHourSessionResult) {
        id = result.sessionID
        state = result.state
        projectName = result.project.name
        taskName = result.task?.name
        profileName = FocusHourProfileID.label(for: result.profileID)
        startedAt = result.startedAt
        endedAt = result.endedAt
        plannedMinutes = result.plannedDurations.planMin + result.plannedDurations.workMin + result.plannedDurations.reflectMin
        actualMinutes = result.actualDurations.totalMin
        apps = result.work.appsUsed.map(ReadableLabels.appName)
        websites = result.work.websitesUsed
        blockedAttempts = result.work.blockedSiteAttempts
        rescued = result.rescue.used
    }

    init(state: FocusHourStateSnapshot) {
        id = state.sessionID ?? "active-focus-hour"
        self.state = state.state
        projectName = state.project?.name ?? "Focus Hour"
        taskName = state.task?.name
        profileName = state.profileID.map(FocusHourProfileID.label(for:)) ?? "Focus"
        startedAt = state.phaseStartedAt ?? state.updatedAt
        endedAt = nil
        plannedMinutes = 0
        actualMinutes = 0
        apps = []
        websites = []
        blockedAttempts = []
        rescued = state.rescue?.used ?? false
    }
}
