import Foundation
import SwiftUI

@MainActor
final class FocusStore: ObservableObject {
    @Published private(set) var sessions: [ActivitySession] = []
    @Published var projects: [FocusProject] = []
    @Published var rules: [CategorizationRule] = []
    @Published var settings = FocusSettings()
    @Published var blockConfig = BlockConfig()
    @Published var currentActivity = "Starting"
    @Published var chromeStatus = "Waiting for Chrome events"
    @Published var latestChromeTabs: [ChromeTabSnapshot] = []
    @Published var latestDisplays: [DisplaySnapshot] = []
    @Published var latestVisibleWindows: [VisibleWindow] = []
    @Published var loginStatus = LoginItemService.statusText
    @Published var lastExportMessage = "No export yet"
    @Published var diagnostics = FocusDiagnostics()
    @Published var focusHourState = FocusHourStateSnapshot.idle()
    /// Ticks every second while a focus session runs so the menu bar countdown stays live.
    @Published var menuClock = Date()

    private let tracker = AppTracker()
    private let idleMonitor = IdleMonitor()
    private let chromeReader = ChromeInboxReader()
    let focusHourBridge = FocusHourBridge()
    private let categorizer = Categorizer()
    private var trackingTask: Task<Void, Never>?
    private var menuClockTask: Task<Void, Never>?
    private var lastSampleDate = Date()
    private var activeFocusHour: ActiveFocusHour?

    init() {
        chromeReader.rotateOversizedEventLogIfNeeded()
        load()
        loadBlockConfig()
        focusHourState = focusHourBridge.loadState() ?? .idle()
        if projects.isEmpty {
            projects = [
                FocusProject(name: "Arel Focus", category: "Build", colorHex: "#2F6FED"),
                FocusProject(name: "Arel OS", category: "Operating System", colorHex: "#21A67A")
            ]
            save()
        }
        recoverActiveFocusHourIfNeeded()
        refreshDiagnostics()
    }

    var todaySessions: [ActivitySession] {
        sessions(in: reviewInterval(for: .today))
    }

    var timelineSessions: [ActivitySession] {
        coalesced(todaySessions)
    }

    var chromeTabSessions: [ActivitySession] {
        timelineSessions.filter { $0.kind == .chromeTab || $0.kind == .openChromeTab }
    }

    var focusHourStatusLabel: String? {
        guard focusHourState.state != .idle else { return nil }

        var parts = ["Focus Hour", focusHourState.state.label]
        if let profileID = focusHourState.profileID, !profileID.isEmpty {
            parts.append(FocusHourProfileID.label(for: profileID))
        }
        if let project = focusHourState.project {
            parts.append(project.name)
        }
        return parts.joined(separator: " - ")
    }

    /// Seconds left in the current focus phase (nil when no session is running).
    /// Computed from the active session's wall-clock phase ends, so it mirrors the
    /// arel-os focus page countdown exactly during the Work block.
    var focusHourRemaining: TimeInterval? {
        guard focusHourState.state.isRunning, let active = activeFocusHour else { return nil }
        let end: Date
        switch focusHourState.state {
        case .planning: end = active.planEnd
        case .working: end = active.workEnd
        case .reflecting: end = active.reflectEnd
        default: return nil
        }
        return max(0, end.timeIntervalSince(Date()))
    }

    /// Short phase tag for the current focus mode (nil when idle).
    var focusHourPhaseTag: String? {
        switch focusHourState.state {
        case .planning: return "Plan"
        case .working: return "Work"
        case .reflecting: return "Reflect"
        default: return nil
        }
    }

    /// Menu bar countdown text, e.g. "Work 38:35" — nil when no session is running.
    var menuBarTimerText: String? {
        guard let remaining = focusHourRemaining, let tag = focusHourPhaseTag else { return nil }
        return "\(tag) \(focusClockString(remaining))"
    }

    /// SF Symbol for the menu bar, varied by focus phase.
    var menuBarSystemImage: String {
        switch focusHourState.state {
        case .planning: return "hourglass"
        case .working: return "timer"
        case .reflecting: return "checkmark.circle"
        default: return "timer"
        }
    }

    /// "M:SS" (or "H:MM:SS" past an hour) — matches the arel-os focus page clock.
    private func focusClockString(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    var todayActiveDuration: TimeInterval {
        intervalUnionDuration(todaySessions.filter { $0.kind == .activeApp || $0.kind == .chromeTab })
    }

    var todayBackgroundDuration: TimeInterval {
        todaySessions
            .filter { $0.kind == .backgroundApp || $0.kind == .openChromeTab }
            .reduce(0) { $0 + $1.duration }
    }

    var todayIdleDuration: TimeInterval {
        intervalUnionDuration(todaySessions.filter { $0.kind == .idle })
    }

    var uncategorizedSessions: [ActivitySession] {
        todaySessions.filter(\.isUncategorized)
    }

    var reviewSessions: [ActivitySession] {
        reviewSessions(in: .last15Days)
    }

    func reviewSessions(days: Int) -> [ActivitySession] {
        let scope: ReviewScope = days <= 1 ? .today : .last15Days
        return reviewSessions(in: scope)
    }

    func sessions(in interval: DateInterval) -> [ActivitySession] {
        sessions.compactMap { clipped($0, to: interval) }
    }

    func reviewSessions(in scope: ReviewScope) -> [ActivitySession] {
        coalesced(sessions(in: reviewInterval(for: scope))).filter(\.isUncategorized)
    }

    func reviewCandidates(in scope: ReviewScope) -> [ReviewCandidate] {
        let source = sessions(in: reviewInterval(for: scope)).filter(\.isUncategorized)
        var buckets: [String: ReviewCandidate] = [:]

        for session in source {
            guard let identity = reviewIdentity(for: session) else { continue }
            let key = "\(identity.field.rawValue)|\(identity.pattern)"

            if var existing = buckets[key] {
                existing.sessionIDs.append(session.id)
                existing.sessionCount += 1
                existing.totalDuration += session.duration
                existing.firstSeen = min(existing.firstSeen, session.startedAt)
                existing.lastSeen = max(existing.lastSeen, session.endedAt)
                if existing.detail.isEmpty || session.duration > existing.totalDuration / Double(max(existing.sessionCount, 1)) {
                    existing.detail = session.detail
                    existing.sourceName = session.sourceName
                    existing.favIconURL = session.favIconURL ?? existing.favIconURL
                    existing.favIconDataURL = session.favIconDataURL ?? existing.favIconDataURL
                }
                buckets[key] = existing
            } else {
                buckets[key] = ReviewCandidate(
                    id: key,
                    field: identity.field,
                    pattern: identity.pattern,
                    sourceName: session.sourceName,
                    detail: session.detail,
                    representativeKind: session.kind,
                    bundleID: session.bundleID,
                    domain: session.domain,
                    favIconURL: session.favIconURL,
                    favIconDataURL: session.favIconDataURL,
                    sessionIDs: [session.id],
                    sessionCount: 1,
                    totalDuration: session.duration,
                    firstSeen: session.startedAt,
                    lastSeen: session.endedAt
                )
            }
        }

        return buckets.values.sorted {
            if $0.totalDuration == $1.totalDuration {
                return $0.firstSeen < $1.firstSeen
            }
            return $0.totalDuration > $1.totalDuration
        }
    }

    func reviewStats(in scope: ReviewScope) -> ReviewStats {
        let source = sessions(in: reviewInterval(for: scope)).filter(\.isUncategorized)
        return ReviewStats(
            sessionCount: source.count,
            candidateCount: reviewCandidates(in: scope).count,
            uncategorizedDuration: source.reduce(0) { $0 + $1.duration }
        )
    }

    func assign(_ candidate: ReviewCandidate, to project: FocusProject, learnRule: Bool) {
        let matchingIDs = Set(candidate.sessionIDs)
        for index in sessions.indices where matchingIDs.contains(sessions[index].id) {
            sessions[index].projectID = project.id
            sessions[index].category = project.category
        }

        if learnRule {
            let rule = CategorizationRule(field: candidate.field, pattern: candidate.pattern, projectID: project.id, category: project.category)
            let learnedRule: CategorizationRule
            if let existing = rules.first(where: { $0.field == rule.field && $0.pattern == rule.pattern && $0.projectID == rule.projectID }) {
                learnedRule = existing
            } else {
                rules.append(rule)
                learnedRule = rule
            }
            applyRuleToExistingSessions(learnedRule)
        }

        save()
    }

    func removeRule(_ rule: CategorizationRule) {
        rules.removeAll { $0.id == rule.id }
        save()
    }

    func unionDuration(_ source: [ActivitySession]) -> TimeInterval {
        intervalUnionDuration(source)
    }

    func start() {
        guard trackingTask == nil else { return }
        lastSampleDate = Date()
        recordSample()

        trackingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                await MainActor.run {
                    self?.recordSample()
                }
            }
        }

        // Drive the live menu bar countdown: tick every second while a session
        // runs, idle at 2s otherwise so we don't churn the UI when nothing's up.
        menuClockTask = Task { [weak self] in
            while !Task.isCancelled {
                let running = await MainActor.run { self?.focusHourState.state.isRunning ?? false }
                if running {
                    await MainActor.run { self?.menuClock = Date() }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                } else {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                }
            }
        }
    }

    func pauseTracking(_ paused: Bool) {
        settings.trackingPaused = paused
        save()
    }

    func rescueActiveFocusHour(reason: String = "Arel Focus menu") {
        guard activeFocusHour != nil else { return }
        let now = Date()
        let rescue = FocusHourRescueInfo(used: true, activatedAt: now, reason: reason)
        finishActiveFocusHour(state: .rescued, endedAt: now, rescue: rescue)
    }

    func setIdleThreshold(_ seconds: Int) {
        settings.idleThresholdSeconds = TimeInterval(seconds)
        save()
    }

    func createProject(name: String, category: String, colorHex: String = "#2F6FED") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        projects.append(FocusProject(name: trimmed, category: category.isEmpty ? "Work" : category, colorHex: colorHex))
        save()
    }

    func assign(_ session: ActivitySession, to project: FocusProject) {
        let matchingIndexes = assignmentIndexes(for: session)

        for index in matchingIndexes {
            sessions[index].projectID = project.id
            sessions[index].category = project.category
        }

        let ruleSource = matchingIndexes.first.map { sessions[$0] } ?? session
        if let rule = categorizer.rule(from: ruleSource, project: project) {
            let learnedRule: CategorizationRule
            if let existing = rules.first(where: { $0.field == rule.field && $0.pattern == rule.pattern && $0.projectID == rule.projectID }) {
                learnedRule = existing
            } else {
                rules.append(rule)
                learnedRule = rule
            }
            applyRuleToExistingSessions(learnedRule)
        }

        save()
    }

    func projectName(for id: UUID?) -> String {
        guard let id, let project = projects.first(where: { $0.id == id }) else {
            return "Unassigned"
        }
        return project.name
    }

    func summaries(for kind: ActivityKind? = nil, key: KeyPath<ActivitySession, String>) -> [DurationSummary] {
        var grouped: [String: TimeInterval] = [:]
        var bundleIDs: [String: String] = [:]
        var favIcons: [String: String] = [:]
        var favIconDataURLs: [String: String] = [:]

        for session in todaySessions where kind == nil || session.kind == kind {
            let name = session[keyPath: key].isEmpty ? "Untitled" : session[keyPath: key]
            grouped[name, default: 0] += session.duration
            if let bundleID = session.bundleID, bundleIDs[name] == nil {
                bundleIDs[name] = bundleID
            }
            if let favIconURL = session.favIconURL, favIcons[name] == nil {
                favIcons[name] = favIconURL
            }
            if let favIconDataURL = session.favIconDataURL, favIconDataURLs[name] == nil {
                favIconDataURLs[name] = favIconDataURL
            }
        }
        return grouped.map {
            DurationSummary(
                name: $0.key,
                duration: $0.value,
                bundleID: bundleIDs[$0.key],
                favIconURL: favIcons[$0.key],
                favIconDataURL: favIconDataURLs[$0.key]
            )
        }
            .sorted { $0.duration > $1.duration }
    }

    func appSummaries() -> [DurationSummary] {
        let appKinds: Set<ActivityKind> = [.activeApp, .backgroundApp]
        var grouped: [String: TimeInterval] = [:]
        var bundleIDs: [String: String] = [:]

        for session in todaySessions where appKinds.contains(session.kind) {
            grouped[session.sourceName, default: 0] += session.duration
            if let bundleID = session.bundleID, bundleIDs[session.sourceName] == nil {
                bundleIDs[session.sourceName] = bundleID
            }
        }

        return grouped.map { DurationSummary(name: $0.key, duration: $0.value, bundleID: bundleIDs[$0.key], favIconURL: nil, favIconDataURL: nil) }
            .sorted { $0.duration > $1.duration }
    }

    func domainSummaries() -> [DurationSummary] {
        var grouped: [String: TimeInterval] = [:]
        var favIcons: [String: String] = [:]
        var favIconDataURLs: [String: String] = [:]

        for session in todaySessions where session.kind == .chromeTab || session.kind == .openChromeTab {
            let name = session.domain ?? "Unknown"
            grouped[name, default: 0] += session.duration
            if let favIconURL = session.favIconURL, favIcons[name] == nil {
                favIcons[name] = favIconURL
            }
            if let favIconDataURL = session.favIconDataURL, favIconDataURLs[name] == nil {
                favIconDataURLs[name] = favIconDataURL
            }
        }

        return grouped.map {
            DurationSummary(
                name: $0.key,
                duration: $0.value,
                bundleID: nil,
                favIconURL: favIcons[$0.key],
                favIconDataURL: favIconDataURLs[$0.key]
            )
        }
            .sorted { $0.duration > $1.duration }
    }

    func setLoginEnabled(_ enabled: Bool) {
        loginStatus = LoginItemService.setEnabled(enabled)
    }

    func refreshDiagnostics() {
        updateDiagnostics(rotateChromeLog: true)
    }

    func setBlockingEnabled(_ enabled: Bool) {
        blockConfig.blockingEnabled = enabled
        saveBlockConfig()
    }

    func addBlockedDomain(_ rawValue: String) {
        guard let domain = normalizedDomain(from: rawValue),
              !blockConfig.blockedDomains.contains(domain) else { return }
        blockConfig.blockedDomains.append(domain)
        blockConfig.blockedDomains.sort()
        saveBlockConfig()
    }

    func removeBlockedDomain(_ domain: String) {
        guard let normalized = normalizedDomain(from: domain) else { return }
        blockConfig.blockedDomains.removeAll { $0 == domain || $0 == normalized }
        saveBlockConfig()
    }

    func addExcludedBundleID(_ rawValue: String) {
        let bundleID = normalizedBundleID(rawValue)
        guard !bundleID.isEmpty,
              !settings.excludedBundleIDs.contains(where: { normalizedBundleID($0) == bundleID })
        else { return }
        settings.excludedBundleIDs.append(bundleID)
        save()
    }

    func removeExcludedBundleID(_ bundleID: String) {
        let normalized = normalizedBundleID(bundleID)
        settings.excludedBundleIDs.removeAll { $0 == bundleID || normalizedBundleID($0) == normalized }
        save()
    }

    func addExcludedDomain(_ rawValue: String) {
        guard let domain = normalizedDomain(from: rawValue),
              !settings.excludedDomains.contains(domain) else { return }
        settings.excludedDomains.append(domain)
        save()
    }

    func removeExcludedDomain(_ domain: String) {
        settings.excludedDomains.removeAll { $0 == domain }
        save()
    }

    @discardableResult
    func exportToday() -> ExportResult? {
        do {
            let result = try writeTodayExport()
            lastExportMessage = "Exported \(result.jsonURL.lastPathComponent)"
            return result
        } catch {
            lastExportMessage = "Export failed: \(error.localizedDescription)"
            return nil
        }
    }

    private func processFocusHourBridge(now: Date) {
        for command in focusHourBridge.consumePendingCommands() {
            switch command {
            case .start(let startCommand):
                handleFocusHourStart(startCommand, now: now)
            case .update(let updateCommand):
                handleFocusHourUpdate(updateCommand, now: now)
            case .rescue(let rescueCommand):
                handleFocusHourRescue(rescueCommand, now: now)
            case .cancel(let cancelCommand):
                handleFocusHourCancel(cancelCommand, now: now)
            }
        }

        advanceFocusHourIfNeeded(now: now)
    }

    private func handleFocusHourStart(_ command: FocusHourStartCommand, now: Date) {
        if activeFocusHour != nil {
            finishActiveFocusHour(state: .cancelled, endedAt: now, rescue: nil)
        }

        let project = localProject(for: command.project)
        let active = ActiveFocusHour(
            command: command,
            localProjectID: project.id,
            localProjectCategory: project.category,
            originalBlockConfig: blockConfig,
            phaseStartedAt: command.startAt
        )
        activeFocusHour = active
        focusHourBridge.writeActiveFocusHour(active)

        setFocusBlockingEnabled(false)
        updateFocusHourState(.planning, phaseStartedAt: command.startAt, now: now)
        advanceFocusHourIfNeeded(now: now)
    }

    private func handleFocusHourUpdate(_ command: FocusHourUpdateCommand, now: Date) {
        if activeFocusHour == nil {
            recoverActiveFocusHourIfNeeded()
        }

        guard var active = activeFocusHour,
              active.command.sessionID == command.sessionID
        else { return }

        // `command.blocked` is the FULL new effective block list (authoritative).
        // Anything in the profile's block list but not in the new list becomes a
        // temp-allow override for the rest of the session.
        let newBlocked = Set(command.blocked.compactMap { normalizedDomain(from: $0) })
        let profileDomains = Set(active.command.effectiveBlockedDomains.compactMap { normalizedDomain(from: $0) })
        let overrides = profileDomains.subtracting(newBlocked)

        active.allowedOverrides = Array(overrides).sorted()
        activeFocusHour = active
        focusHourBridge.writeActiveFocusHour(active)

        // Push the new block list to Chrome immediately if we're in the Work phase;
        // otherwise the override is recorded and applied when Work begins.
        if focusHourState.state == .working {
            applyFocusProfileBlocking(active)
        }
        updateFocusHourState(focusHourState.state, phaseStartedAt: active.phaseStartedAt, now: now)
    }

    private func handleFocusHourRescue(_ command: FocusHourRescueCommand, now: Date) {
        if activeFocusHour == nil {
            recoverActiveFocusHourIfNeeded()
        }

        let activatedAt = command.requestedAt
        let rescue = FocusHourRescueInfo(used: true, activatedAt: activatedAt, reason: command.reason)

        if let activeFocusHour,
           activeFocusHour.command.sessionID == command.sessionID {
            finishActiveFocusHour(state: .rescued, endedAt: activatedAt, rescue: rescue)
            return
        }

        setFocusBlockingEnabled(false)
        focusHourState = FocusHourStateSnapshot(
            state: .rescued,
            sessionID: command.sessionID,
            updatedAt: now,
            rescue: rescue
        )
        focusHourBridge.writeState(focusHourState)
    }

    private func handleFocusHourCancel(_ command: FocusHourCancelCommand, now: Date) {
        if activeFocusHour == nil {
            recoverActiveFocusHourIfNeeded()
        }

        if let activeFocusHour,
           activeFocusHour.command.sessionID == command.sessionID {
            finishActiveFocusHour(state: .cancelled, endedAt: command.requestedAt, rescue: nil)
            return
        }

        focusHourState = FocusHourStateSnapshot(
            state: .cancelled,
            sessionID: command.sessionID,
            updatedAt: now
        )
        focusHourBridge.writeState(focusHourState)
    }

    private func advanceFocusHourIfNeeded(now: Date) {
        guard var active = activeFocusHour else {
            if focusHourState.state == .idle {
                focusHourBridge.writeState(focusHourState)
            }
            return
        }

        let next = focusHourPhase(for: active, now: now)
        if next.state == .completed {
            finishActiveFocusHour(state: .completed, endedAt: active.reflectEnd, rescue: nil)
            return
        }

        if focusHourState.state != next.state || active.phaseStartedAt != next.phaseStartedAt {
            active.phaseStartedAt = next.phaseStartedAt
            activeFocusHour = active
            focusHourBridge.writeActiveFocusHour(active)
            updateFocusHourState(next.state, phaseStartedAt: next.phaseStartedAt, now: now)
        }

        if next.state == .working {
            applyFocusProfileBlocking(active)
        } else {
            setFocusBlockingEnabled(false)
        }
    }

    private func focusHourPhase(for active: ActiveFocusHour, now: Date) -> (state: FocusHourRuntimeState, phaseStartedAt: Date) {
        if now < active.planEnd {
            return (.planning, active.startedAt)
        }

        if now < active.workEnd {
            return (.working, active.planEnd)
        }

        if now < active.reflectEnd {
            return (.reflecting, active.workEnd)
        }

        return (.completed, active.reflectEnd)
    }

    private func finishActiveFocusHour(state: FocusHourRuntimeState, endedAt: Date, rescue: FocusHourRescueInfo?) {
        guard let active = activeFocusHour else { return }

        switch state {
        case .rescued:
            setFocusBlockingEnabled(false)
        default:
            restoreBlockConfig(active.originalBlockConfig)
        }

        let result = focusHourResult(for: active, state: state, endedAt: endedAt, rescue: rescue)
        focusHourBridge.writeResult(result)

        focusHourState = FocusHourStateSnapshot(
            state: state,
            sessionID: active.command.sessionID,
            updatedAt: endedAt,
            project: active.command.project,
            task: active.command.task,
            profileID: active.command.profileID,
            phaseStartedAt: active.phaseStartedAt,
            rescue: result.rescue
        )
        focusHourBridge.writeState(focusHourState)
        activeFocusHour = nil
        focusHourBridge.clearActiveFocusHour()
    }

    private func updateFocusHourState(_ state: FocusHourRuntimeState, phaseStartedAt: Date, now: Date) {
        guard let active = activeFocusHour else { return }

        let blockedNow = state == .working ? focusEnforcedDomains(for: active) : nil
        focusHourState = FocusHourStateSnapshot(
            state: state,
            sessionID: active.command.sessionID,
            updatedAt: now,
            project: active.command.project,
            task: active.command.task,
            profileID: active.command.profileID,
            blockedNow: blockedNow,
            allowedOverrides: active.allowedOverrides.isEmpty ? nil : active.allowedOverrides,
            phaseStartedAt: phaseStartedAt
        )
        focusHourBridge.writeState(focusHourState)
    }

    private func recoverActiveFocusHourIfNeeded() {
        guard focusHourState.state.isRunning,
              let sessionID = focusHourState.sessionID
        else {
            focusHourBridge.clearActiveFocusHour()
            return
        }

        if let persisted = focusHourBridge.loadActiveFocusHour(),
           persisted.command.sessionID == sessionID {
            let recovered = recoveredActiveFocusHour(persisted)
            activeFocusHour = recovered
            focusHourBridge.writeActiveFocusHour(recovered)
            advanceFocusHourIfNeeded(now: Date())
            return
        }

        guard let command = focusHourBridge.loadStartCommand(sessionID: sessionID) else {
            setFocusBlockingEnabled(false)
            focusHourState = FocusHourStateSnapshot(
                state: .cancelled,
                sessionID: sessionID,
                updatedAt: Date(),
                project: focusHourState.project,
                task: focusHourState.task,
                profileID: focusHourState.profileID,
                phaseStartedAt: focusHourState.phaseStartedAt
            )
            focusHourBridge.writeState(focusHourState)
            focusHourBridge.clearActiveFocusHour()
            return
        }

        let project = localProject(for: command.project)
        let active = recoveredActiveFocusHour(ActiveFocusHour(
            command: command,
            localProjectID: project.id,
            localProjectCategory: project.category,
            originalBlockConfig: blockConfig,
            phaseStartedAt: focusHourState.phaseStartedAt ?? command.startAt
        ))
        activeFocusHour = active
        focusHourBridge.writeActiveFocusHour(active)
        advanceFocusHourIfNeeded(now: Date())
    }

    private func applyFocusProfileBlocking(_ active: ActiveFocusHour) {
        let domains = focusEnforcedDomains(for: active)
        let focusContext = BlockFocusContext(
            targetName: active.command.task?.name ?? active.command.project.name,
            profileLabel: active.command.profileLabel,
            sessionID: active.command.sessionID
        )
        guard blockConfig.blockingEnabled != true
            || blockConfig.blockedDomains != domains
            || blockConfig.focus != focusContext
        else { return }
        blockConfig.blockingEnabled = true
        blockConfig.blockedDomains = domains
        blockConfig.focus = focusContext
        saveBlockConfig()
    }

    private func recoveredActiveFocusHour(_ active: ActiveFocusHour) -> ActiveFocusHour {
        var recovered = active
        let profileDomains = focusEnforcedDomains(for: active)
        let originalLooksLikeAutoWorkProfile = recovered.originalBlockConfig.blockingEnabled
            && recovered.originalBlockConfig.blockedDomains == profileDomains
            && recovered.originalBlockConfig.updatedAt >= active.planEnd

        if originalLooksLikeAutoWorkProfile {
            recovered.originalBlockConfig.blockingEnabled = false
        }

        return recovered
    }

    /// The domains actually enforced during Work: notion's effective block list
    /// (inline, or hard-coded fallback) minus any per-session temp-allow overrides.
    private func focusEnforcedDomains(for active: ActiveFocusHour) -> [String] {
        let overrides = Set(active.allowedOverrides.compactMap { normalizedDomain(from: $0) })
        let domains = active.command.effectiveBlockedDomains
            .compactMap { normalizedDomain(from: $0) }
            .filter { !overrides.contains($0) }
        return Array(Set(domains)).sorted()
    }

    private func setFocusBlockingEnabled(_ enabled: Bool) {
        let clearsFocus = !enabled && blockConfig.focus != nil
        guard blockConfig.blockingEnabled != enabled || clearsFocus else { return }
        blockConfig.blockingEnabled = enabled
        if !enabled {
            blockConfig.focus = nil
        }
        saveBlockConfig()
    }

    private func restoreBlockConfig(_ config: BlockConfig) {
        guard blockConfig != config else { return }
        blockConfig = config
        saveBlockConfig()
    }

    private func localProject(for entity: FocusHourEntity) -> FocusProject {
        if let project = projects.first(where: { normalized($0.name).caseInsensitiveCompare(normalized(entity.name)) == .orderedSame }) {
            return project
        }

        let project = FocusProject(name: entity.name, category: "Arel OS", colorHex: "#21A67A")
        projects.append(project)
        save()
        return project
    }

    private func sessionTaggedForActiveFocusHour(_ session: ActivitySession) -> ActivitySession {
        guard let activeFocusHour,
              focusHourState.state.isRunning,
              session.kind != .idle,
              session.endedAt >= activeFocusHour.startedAt,
              session.startedAt <= activeFocusHour.reflectEnd,
              let localProjectID = activeFocusHour.localProjectID
        else { return session }

        var focused = session
        focused.projectID = focused.projectID ?? localProjectID
        focused.category = focused.category ?? activeFocusHour.localProjectCategory
        return focused
    }

    private func focusHourResult(
        for active: ActiveFocusHour,
        state: FocusHourRuntimeState,
        endedAt: Date,
        rescue: FocusHourRescueInfo?
    ) -> FocusHourSessionResult {
        let actual = actualDurations(for: active, endedAt: endedAt)
        let planInterval = DateInterval(start: active.startedAt, end: min(active.planEnd, endedAt))
        let workInterval = DateInterval(start: min(active.planEnd, endedAt), end: min(active.workEnd, endedAt))
        let blockedAttempts = chromeReader
            .events(from: workInterval.start, to: workInterval.end, matchingType: "blockedAttempt")
            .compactMap { $0.domain ?? normalizedDomain(from: $0.url) }

        return FocusHourSessionResult(
            sessionID: active.command.sessionID,
            state: state,
            startedAt: active.startedAt,
            endedAt: endedAt,
            project: active.command.project,
            task: active.command.task,
            profileID: active.command.profileID,
            plannedDurations: active.command.durations,
            actualDurations: actual,
            planNotes: active.command.planNotes.isEmpty ? nil : active.command.planNotes,
            planning: FocusHourPlanningSummary(
                websitesVisited: uniqueDomains(in: planInterval)
            ),
            work: FocusHourWorkSummary(
                appsUsed: uniqueApps(in: workInterval),
                websitesUsed: uniqueDomains(in: workInterval),
                blockedSiteAttempts: unique(blockedAttempts)
            ),
            allowedOverrides: active.allowedOverrides,
            rescue: rescue ?? FocusHourRescueInfo(used: false, activatedAt: nil, reason: nil),
            reflection: FocusHourReflectionSummary(status: state == .completed ? "missing" : "skipped", text: nil)
        )
    }

    private func actualDurations(for active: ActiveFocusHour, endedAt: Date) -> FocusHourActualDurations {
        let boundedEnd = max(endedAt, active.startedAt)
        let total = boundedEnd.timeIntervalSince(active.startedAt)
        let plan = overlapSeconds(start: active.startedAt, end: active.planEnd, clipEnd: boundedEnd)
        let work = overlapSeconds(start: active.planEnd, end: active.workEnd, clipEnd: boundedEnd)
        let reflect = overlapSeconds(start: active.workEnd, end: active.reflectEnd, clipEnd: boundedEnd)

        return FocusHourActualDurations(
            planMin: minutes(plan),
            workMin: minutes(work),
            reflectMin: minutes(reflect),
            totalMin: minutes(total)
        )
    }

    private func overlapSeconds(start: Date, end: Date, clipEnd: Date) -> TimeInterval {
        let clippedEnd = min(end, clipEnd)
        guard clippedEnd > start else { return 0 }
        return clippedEnd.timeIntervalSince(start)
    }

    private func minutes(_ seconds: TimeInterval) -> Int {
        Int((max(seconds, 0) / 60).rounded())
    }

    private func uniqueDomains(in interval: DateInterval) -> [String] {
        unique(sessionsOverlapping(interval)
            .filter { $0.kind == .chromeTab || $0.kind == .openChromeTab }
            .compactMap { $0.domain ?? normalizedDomain(from: $0.url) })
    }

    private func uniqueApps(in interval: DateInterval) -> [String] {
        unique(sessionsOverlapping(interval)
            .filter { $0.kind == .activeApp || $0.kind == .backgroundApp }
            .map(\.sourceName))
    }

    private func sessionsOverlapping(_ interval: DateInterval) -> [ActivitySession] {
        guard interval.end > interval.start else { return [] }
        return sessions.filter { session in
            session.startedAt < interval.end && session.endedAt > interval.start
        }
    }

    private func unique(_ values: [String]) -> [String] {
        Array(Set(values.map { normalized($0) }.filter { !$0.isEmpty })).sorted()
    }

    private func recordSample() {
        let now = Date()
        processFocusHourBridge(now: now)

        let elapsed = min(max(now.timeIntervalSince(lastSampleDate), 0), 30)
        lastSampleDate = now

        guard elapsed > 0.25, !settings.trackingPaused else {
            currentActivity = settings.trackingPaused ? "Paused" : currentActivity
            return
        }

        let isIdle = idleMonitor.isIdle(threshold: settings.idleThresholdSeconds)
        let snapshot = tracker.snapshot()
        let latestChrome = chromeReader.latestEvent()
        latestDisplays = snapshot.displays
        latestVisibleWindows = snapshot.visibleWindows

        if let latestChrome {
            let age = max(Date().timeIntervalSince(latestChrome.capturedAt), 0)
            let ageLabel = age < 60 ? "just now" : "\(Int((age / 60).rounded()))m ago"
            chromeStatus = "Chrome updated \(ageLabel)"
            latestChromeTabs = latestChrome.openTabs.sorted { lhs, rhs in
                if lhs.active != rhs.active {
                    return lhs.active
                }

                if chromeProfileLabel(for: lhs) != chromeProfileLabel(for: rhs) {
                    return chromeProfileLabel(for: lhs) < chromeProfileLabel(for: rhs)
                }

                if lhs.windowID != rhs.windowID {
                    return lhs.windowID < rhs.windowID
                }

                return lhs.tabID < rhs.tabID
            }
        }

        if isIdle {
            appendSession(ActivitySession(
                kind: .idle,
                sourceName: "Idle",
                detail: "No interaction",
                startedAt: now.addingTimeInterval(-elapsed),
                duration: elapsed
            ))
            currentActivity = "Idle"
            return
        }

        if isExcluded(snapshot: snapshot) {
            currentActivity = "Excluded"
            return
        }

        let activeVisibleApp = matchingVisibleApp(in: snapshot, bundleID: snapshot.activeBundleID, name: snapshot.activeAppName)

        if snapshot.activeBundleID == "com.google.Chrome", let chrome = latestChrome {
            if !isFreshChromeEvent(chrome) {
                appendSession(ActivitySession(
                    kind: .activeApp,
                    sourceName: snapshot.activeAppName,
                    detail: "Waiting for fresh Chrome tab event",
                    bundleID: snapshot.activeBundleID,
                    windowCount: activeVisibleApp?.windowCount,
                    displayIDs: activeVisibleApp?.displayIDs,
                    displayNames: activeVisibleApp?.displayNames,
                    windowTitles: activeVisibleApp?.windowTitles,
                    startedAt: now.addingTimeInterval(-elapsed),
                    duration: elapsed
                ))
                currentActivity = "Chrome (stale tab event)"
            } else if isExcludedChrome(chrome) {
                currentActivity = "Excluded Site"
            } else {
                appendSession(ActivitySession(
                    kind: .chromeTab,
                    sourceName: chrome.domain ?? "Chrome",
                    detail: chrome.title ?? chrome.url ?? "Active Chrome tab",
                    bundleID: snapshot.activeBundleID,
                    url: chrome.url,
                    domain: chrome.domain,
                    favIconURL: chrome.favIconURL,
                    favIconDataURL: chrome.favIconDataURL,
                    tabID: chrome.tabID,
                    windowID: chrome.windowID,
                    chromeProfileID: chrome.profileID,
                    chromeProfileName: chrome.profileName,
                    windowCount: activeVisibleApp?.windowCount,
                    displayIDs: activeVisibleApp?.displayIDs,
                    displayNames: activeVisibleApp?.displayNames,
                    windowTitles: activeVisibleApp?.windowTitles,
                    startedAt: now.addingTimeInterval(-elapsed),
                    duration: elapsed
                ))
                currentActivity = chrome.domain ?? "Chrome"
            }
        } else {
            appendSession(ActivitySession(
                kind: .activeApp,
                sourceName: snapshot.activeAppName,
                detail: snapshot.activeWindowTitle,
                bundleID: snapshot.activeBundleID,
                windowCount: activeVisibleApp?.windowCount,
                displayIDs: activeVisibleApp?.displayIDs,
                displayNames: activeVisibleApp?.displayNames,
                windowTitles: activeVisibleApp?.windowTitles,
                startedAt: now.addingTimeInterval(-elapsed),
                duration: elapsed
            ))
            currentActivity = snapshot.activeAppName
        }

        if let latestChrome, isFreshChromeEvent(latestChrome) {
            recordOpenChromeTabs(
                from: latestChrome,
                startedAt: now.addingTimeInterval(-elapsed),
                duration: elapsed
            )
        }

        for app in snapshot.visibleApps where app.bundleID != snapshot.activeBundleID {
            guard !isExcludedBundleID(app.bundleID) else { continue }
            appendSession(ActivitySession(
                kind: .backgroundApp,
                sourceName: app.name,
                detail: backgroundDetail(for: app),
                bundleID: app.bundleID,
                windowCount: app.windowCount,
                displayIDs: app.displayIDs,
                displayNames: app.displayNames,
                windowTitles: app.windowTitles,
                startedAt: now.addingTimeInterval(-elapsed),
                duration: elapsed
            ))
        }

        pruneOldSamples()
        save()
    }

    private func appendSession(_ session: ActivitySession) {
        let focused = sessionTaggedForActiveFocusHour(session)
        let categorized = categorizer.apply(to: focused, rules: rules)

        if let index = recentCoalescingIndex(for: categorized, in: sessions) {
            sessions[index] = merged(existing: sessions[index], incoming: categorized)
        } else {
            sessions.append(categorized)
        }
    }

    private func coalesced(_ source: [ActivitySession]) -> [ActivitySession] {
        var result: [ActivitySession] = []

        for session in source.sorted(by: { $0.startedAt < $1.startedAt }) {
            if let index = recentCoalescingIndex(for: session, in: result) {
                result[index] = merged(existing: result[index], incoming: session)
            } else {
                result.append(session)
            }
        }

        return result
    }

    private func recentCoalescingIndex(for incoming: ActivitySession, in source: [ActivitySession]) -> Int? {
        if isForegroundExclusive(incoming.kind) {
            return recentForegroundCoalescingIndex(for: incoming, in: source)
        }

        let lowerBound = max(source.count - 80, 0)

        for index in stride(from: source.count - 1, through: lowerBound, by: -1) {
            guard index >= 0, index < source.count else { continue }
            if canCoalesce(source[index], incoming) {
                return index
            }
        }

        return nil
    }

    private func recentForegroundCoalescingIndex(for incoming: ActivitySession, in source: [ActivitySession]) -> Int? {
        for index in stride(from: source.count - 1, through: 0, by: -1) {
            guard index >= 0, index < source.count else { continue }
            guard isForegroundExclusive(source[index].kind) else { continue }
            return canCoalesce(source[index], incoming) ? index : nil
        }

        return nil
    }

    private func canCoalesce(_ existing: ActivitySession, _ incoming: ActivitySession) -> Bool {
        guard existing.kind == incoming.kind else { return false }
        guard existing.projectID == incoming.projectID else { return false }
        guard existing.category == incoming.category else { return false }
        guard gapBetween(existing, incoming) <= coalescingGap(for: incoming.kind) else { return false }

        switch incoming.kind {
        case .chromeTab, .openChromeTab:
            return sameChromeIdentity(existing, incoming)
                && same(existing.bundleID, incoming.bundleID)
        case .activeApp:
            return same(existing.bundleID, incoming.bundleID)
                && existing.sourceName == incoming.sourceName
                && normalized(existing.detail) == normalized(incoming.detail)
        case .backgroundApp:
            return same(existing.bundleID, incoming.bundleID)
                && existing.sourceName == incoming.sourceName
        case .idle:
            return true
        }
    }

    private func isForegroundExclusive(_ kind: ActivityKind) -> Bool {
        kind == .activeApp || kind == .chromeTab || kind == .idle
    }

    private func reviewInterval(for scope: ReviewScope) -> DateInterval {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        switch scope {
        case .today:
            return DateInterval(start: startOfToday, end: endOfToday)
        case .thisWeek:
            let week = calendar.dateInterval(of: .weekOfYear, for: now)
            return DateInterval(start: week?.start ?? startOfToday, end: endOfToday)
        case .last15Days:
            let start = calendar.date(byAdding: .day, value: -14, to: startOfToday) ?? startOfToday
            return DateInterval(start: start, end: endOfToday)
        }
    }

    private func clipped(_ session: ActivitySession, to interval: DateInterval) -> ActivitySession? {
        let start = max(session.startedAt, interval.start)
        let end = min(session.endedAt, interval.end)
        guard end > start else { return nil }

        var clipped = session
        clipped.startedAt = start
        clipped.duration = end.timeIntervalSince(start)
        return clipped
    }

    private func reviewIdentity(for session: ActivitySession) -> (field: MatchField, pattern: String)? {
        if session.kind == .chromeTab || session.kind == .openChromeTab {
            if let domain = normalizedDomain(from: session.domain ?? session.url), !domain.isEmpty {
                return (.domain, domain)
            }
        }

        let bundleID = normalizedBundleID(session.bundleID)
        if !bundleID.isEmpty {
            return (.bundleID, bundleID)
        }

        let sourceName = normalized(session.sourceName)
        if !sourceName.isEmpty {
            return (.appName, sourceName)
        }

        return nil
    }

    private func applyRuleToExistingSessions(_ rule: CategorizationRule) {
        for index in sessions.indices where sessions[index].projectID == nil && categorizer.matches(rule: rule, session: sessions[index]) {
            sessions[index].projectID = rule.projectID
            sessions[index].category = rule.category
        }
    }

    private func intervalUnionDuration(_ source: [ActivitySession]) -> TimeInterval {
        let intervals = source
            .map { ($0.startedAt, $0.endedAt) }
            .sorted { lhs, rhs in lhs.0 < rhs.0 }

        var total: TimeInterval = 0
        var currentStart: Date?
        var currentEnd: Date?

        for (start, end) in intervals where end > start {
            guard let existingStart = currentStart, let existingEnd = currentEnd else {
                currentStart = start
                currentEnd = end
                continue
            }

            if start <= existingEnd {
                currentEnd = max(existingEnd, end)
            } else {
                total += existingEnd.timeIntervalSince(existingStart)
                currentStart = start
                currentEnd = end
            }
        }

        if let currentStart, let currentEnd {
            total += currentEnd.timeIntervalSince(currentStart)
        }

        return total
    }

    private func assignmentIndexes(for block: ActivitySession) -> [Int] {
        sessions.indices.filter { index in
            let session = sessions[index]
            guard session.projectID == nil else { return false }
            guard session.kind == block.kind else { return false }
            guard intervalsOverlap(session, block, tolerance: 1) else { return false }
            return sameActivityIdentity(session, block)
        }
    }

    private func intervalsOverlap(_ lhs: ActivitySession, _ rhs: ActivitySession, tolerance: TimeInterval = 0) -> Bool {
        lhs.startedAt < rhs.endedAt.addingTimeInterval(tolerance)
            && rhs.startedAt < lhs.endedAt.addingTimeInterval(tolerance)
    }

    private func sameActivityIdentity(_ lhs: ActivitySession, _ rhs: ActivitySession) -> Bool {
        switch rhs.kind {
        case .chromeTab, .openChromeTab:
            return sameChromeIdentity(lhs, rhs)
                && same(lhs.bundleID, rhs.bundleID)
        case .activeApp:
            return same(lhs.bundleID, rhs.bundleID)
                && lhs.sourceName == rhs.sourceName
                && normalized(lhs.detail) == normalized(rhs.detail)
        case .backgroundApp:
            return same(lhs.bundleID, rhs.bundleID)
                && lhs.sourceName == rhs.sourceName
        case .idle:
            return false
        }
    }

    private func merged(existing: ActivitySession, incoming: ActivitySession) -> ActivitySession {
        let start = min(existing.startedAt, incoming.startedAt)
        let end = max(existing.endedAt, incoming.endedAt)

        var merged = existing
        merged.startedAt = start
        merged.duration = max(end.timeIntervalSince(start), 0)

        if merged.detail.isEmpty {
            merged.detail = incoming.detail
        }

        if merged.favIconURL == nil {
            merged.favIconURL = incoming.favIconURL
        }

        if merged.favIconDataURL == nil {
            merged.favIconDataURL = incoming.favIconDataURL
        }

        if merged.url == nil {
            merged.url = incoming.url
        }

        if merged.domain == nil {
            merged.domain = incoming.domain
        }

        if merged.tabID == nil {
            merged.tabID = incoming.tabID
        }

        if merged.windowID == nil {
            merged.windowID = incoming.windowID
        }

        if merged.chromeProfileID == nil {
            merged.chromeProfileID = incoming.chromeProfileID
        }

        if merged.chromeProfileName == nil {
            merged.chromeProfileName = incoming.chromeProfileName
        }

        if merged.windowCount == nil {
            merged.windowCount = incoming.windowCount
        } else if let incomingCount = incoming.windowCount {
            merged.windowCount = max(merged.windowCount ?? 0, incomingCount)
        }

        merged.displayIDs = union(merged.displayIDs, incoming.displayIDs)
        merged.displayNames = union(merged.displayNames, incoming.displayNames)
        merged.windowTitles = union(merged.windowTitles, incoming.windowTitles, limit: 8)

        return merged
    }

    private func gapBetween(_ existing: ActivitySession, _ incoming: ActivitySession) -> TimeInterval {
        if incoming.startedAt >= existing.endedAt {
            return incoming.startedAt.timeIntervalSince(existing.endedAt)
        }

        if existing.startedAt >= incoming.endedAt {
            return existing.startedAt.timeIntervalSince(incoming.endedAt)
        }

        return 0
    }

    private func coalescingGap(for kind: ActivityKind) -> TimeInterval {
        switch kind {
        case .chromeTab, .openChromeTab:
            return 30
        case .activeApp, .backgroundApp, .idle:
            return 8
        }
    }

    private func recordOpenChromeTabs(from event: ChromeActivityEvent, startedAt: Date, duration: TimeInterval) {
        for tab in event.openTabs {
            guard !isActiveChromeTab(tab, event: event),
                  isTrackableChromeTab(tab),
                  !isExcludedChrome(tab)
            else { continue }

            let domain = chromeDomain(for: tab)
            appendSession(ActivitySession(
                kind: .openChromeTab,
                sourceName: domain ?? "Chrome",
                detail: tab.title ?? tab.url ?? "Open Chrome tab",
                bundleID: "com.google.Chrome",
                url: tab.url,
                domain: domain,
                favIconURL: tab.favIconURL,
                favIconDataURL: tab.favIconDataURL,
                tabID: tab.tabID,
                windowID: tab.windowID,
                chromeProfileID: tab.profileID ?? event.profileID,
                chromeProfileName: tab.profileName ?? event.profileName,
                startedAt: startedAt,
                duration: duration
            ))
        }
    }

    private func isActiveChromeTab(_ tab: ChromeTabSnapshot, event: ChromeActivityEvent) -> Bool {
        tab.tabID == event.tabID
            && tab.windowID == event.windowID
            && same(tab.profileID, event.profileID)
    }

    private func isTrackableChromeTab(_ tab: ChromeTabSnapshot) -> Bool {
        guard let url = tab.url?.trimmingCharacters(in: .whitespacesAndNewlines),
              let components = URLComponents(string: url),
              let scheme = components.scheme?.lowercased()
        else { return false }

        return scheme == "http" || scheme == "https"
    }

    private func chromeDomain(for tab: ChromeTabSnapshot) -> String? {
        normalizedDomain(from: tab.url)
    }

    private func sameChromeIdentity(_ lhs: ActivitySession, _ rhs: ActivitySession) -> Bool {
        let sameURL = lhs.url == rhs.url && lhs.domain == rhs.domain
        let sameProfile = same(lhs.chromeProfileID, rhs.chromeProfileID)

        if let lhsTabID = lhs.tabID,
           let rhsTabID = rhs.tabID,
           let lhsWindowID = lhs.windowID,
           let rhsWindowID = rhs.windowID {
            return lhsTabID == rhsTabID && lhsWindowID == rhsWindowID && sameProfile && sameURL
        }

        return sameProfile && sameURL
    }

    private func same(_ lhs: String?, _ rhs: String?) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    private func normalized(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedBundleID(_ rawValue: String?) -> String {
        let trimmed = normalized(rawValue).lowercased()
        guard !trimmed.isEmpty else { return "" }

        let parts = trimmed.split(separator: ".").map(String.init)
        if parts.count == 2, parts[1] == "com" {
            return "\(parts[1]).\(parts[0])"
        }

        return trimmed
    }

    private func isExcludedBundleID(_ bundleID: String?) -> Bool {
        let candidate = normalizedBundleID(bundleID)
        guard !candidate.isEmpty else { return false }

        return settings.excludedBundleIDs.contains { rawExcluded in
            let excluded = normalizedBundleID(rawExcluded)
            return candidate == excluded || candidate.hasPrefix("\(excluded).")
        }
    }

    private func isExcluded(snapshot: AppSnapshot) -> Bool {
        guard let bundleID = snapshot.activeBundleID else { return false }
        return isExcludedBundleID(bundleID)
    }

    private func matchingVisibleApp(in snapshot: AppSnapshot, bundleID: String?, name: String) -> VisibleApp? {
        snapshot.visibleApps.first { app in
            if let bundleID {
                return app.bundleID == bundleID
            }
            return app.name == name
        }
    }

    private func backgroundDetail(for app: VisibleApp) -> String {
        let windows = app.windowCount == 1 ? "1 window" : "\(app.windowCount) windows"
        guard !app.displayNames.isEmpty else { return "Visible/open app - \(windows)" }
        return "Visible/open app - \(windows) on \(app.displayNames.joined(separator: ", "))"
    }

    func chromeProfileLabel(for session: ActivitySession) -> String? {
        if let name = session.chromeProfileName, !name.isEmpty {
            return name
        }

        guard let profileID = session.chromeProfileID, !profileID.isEmpty else { return nil }
        return "Chrome Profile \(String(profileID.prefix(8)))"
    }

    func chromeProfileLabel(for tab: ChromeTabSnapshot) -> String {
        chromeProfileLabel(profileID: tab.profileID, profileName: tab.profileName)
    }

    private func chromeProfileLabel(profileID: String?, profileName: String?) -> String {
        if let name = profileName, !name.isEmpty {
            return name
        }

        guard let profileID, !profileID.isEmpty else { return "Chrome Profile" }
        return "Chrome Profile \(String(profileID.prefix(8)))"
    }

    private func isExcludedChrome(_ event: ChromeActivityEvent) -> Bool {
        let candidates = [event.domain, event.url].compactMap { normalizedDomain(from: $0) }
        return candidates.contains { candidate in
            settings.excludedDomains.contains { excluded in
                candidate == excluded || candidate.hasSuffix(".\(excluded)")
            }
        }
    }

    private func isExcludedChrome(_ tab: ChromeTabSnapshot) -> Bool {
        guard let candidate = normalizedDomain(from: tab.url) else { return false }
        return settings.excludedDomains.contains { excluded in
            candidate == excluded || candidate.hasSuffix(".\(excluded)")
        }
    }

    private func isFreshChromeEvent(_ event: ChromeActivityEvent) -> Bool {
        Date().timeIntervalSince(event.capturedAt) <= 90
    }

    private func normalizedDomain(from rawValue: String?) -> String? {
        guard let rawValue else { return nil }

        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let value = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let host = URLComponents(string: value)?.host else {
            return trimmed.lowercased()
        }

        let lowercased = host.lowercased()
        return lowercased.hasPrefix("www.") ? String(lowercased.dropFirst(4)) : lowercased
    }

    private func pruneOldSamples() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        sessions.removeAll { $0.startedAt < cutoff }
    }

    private var stateURL: URL {
        supportRoot.appendingPathComponent("focus-state.json")
    }

    private var blockConfigURL: URL {
        supportRoot.appendingPathComponent("block-config.json")
    }

    private var nativeHostManifestURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Google/Chrome/NativeMessagingHosts/com.arel.focus.bridge.json")
    }

    private var expectedNativeBridgeURL: URL {
        // The bridge ships INSIDE the app bundle, beside the main executable
        // (BRIEF v1.11: the installed runtime is self-contained). The diagnostic
        // previously expected a sibling of the .app, which falsely warned
        // "Native host points outside this build" on a correctly bundled install.
        (Bundle.main.executableURL ?? Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/ArelFocus"))
            .deletingLastPathComponent()
            .appendingPathComponent("ArelFocusNativeBridge")
            .standardizedFileURL
    }

    private var supportRoot: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Arel Focus", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private var exportsRoot: URL {
        let root = supportRoot.appendingPathComponent("Exports", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func updateDiagnostics(rotateChromeLog: Bool = false) {
        if rotateChromeLog {
            chromeReader.rotateOversizedEventLogIfNeeded()
        }

        let reviewStats = reviewStats(in: .last15Days)
        let focusAttributes = fileAttributes(at: stateURL)
        let nativeHostPath = installedNativeHostPath()
        let nativeHostURL = nativeHostPath.map { URL(fileURLWithPath: $0).standardizedFileURL }
        diagnostics = FocusDiagnostics(
            focusStateBytes: focusAttributes.size,
            focusStateModifiedAt: focusAttributes.modifiedAt,
            chromeEventLogBytes: chromeReader.eventLogByteCount(),
            rotatedChromeLogCount: chromeReader.rotatedEventLogCount(),
            latestChromeEventAt: chromeReader.latestEvent()?.capturedAt,
            sessionDaysInLast15: sessionDayCount(in: reviewInterval(for: .last15Days)),
            reviewCandidateCount: reviewStats.candidateCount,
            reviewUncategorizedDuration: reviewStats.uncategorizedDuration,
            nativeHostPath: nativeHostPath,
            nativeHostExists: nativeHostURL.map { FileManager.default.isExecutableFile(atPath: $0.path) } ?? false,
            nativeHostMatchesCurrentBridge: nativeHostURL?.path == expectedNativeBridgeURL.path,
            blockingEnabled: blockConfig.blockingEnabled,
            blockedDomainCount: blockConfig.blockedDomains.count
        )
    }

    private func sessionDayCount(in interval: DateInterval) -> Int {
        let calendar = Calendar.current
        let days = sessions.compactMap { session -> Date? in
            guard intervalsOverlap(session, ActivitySession(
                kind: session.kind,
                sourceName: session.sourceName,
                detail: session.detail,
                startedAt: interval.start,
                duration: interval.duration
            )) else { return nil }
            return calendar.startOfDay(for: session.startedAt)
        }
        return Set(days).count
    }

    private func fileAttributes(at url: URL) -> (size: UInt64, modifiedAt: Date?) {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return (0, nil)
        }

        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        let modifiedAt = attributes[.modificationDate] as? Date
        return (size, modifiedAt)
    }

    private func installedNativeHostPath() -> String? {
        guard let data = try? Data(contentsOf: nativeHostManifestURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return object["path"] as? String
    }

    private func load() {
        guard let data = try? Data(contentsOf: stateURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let state = try? decoder.decode(PersistedFocusState.self, from: data) else { return }
        sessions = state.sessions
        projects = state.projects
        rules = state.rules
        settings = state.settings
        pruneOldSamples()
    }

    private func loadBlockConfig() {
        guard let data = try? Data(contentsOf: blockConfigURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        let domains = object["blockedDomains"] as? [String] ?? []
        let updatedAt = (object["updatedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        var focus: BlockFocusContext?
        if let focusObject = object["focus"] as? [String: Any],
           let target = focusObject["target_name"] as? String,
           let label = focusObject["profile_label"] as? String,
           let session = focusObject["session_id"] as? String {
            focus = BlockFocusContext(targetName: target, profileLabel: label, sessionID: session)
        }
        blockConfig = BlockConfig(
            blockingEnabled: object["blockingEnabled"] as? Bool ?? false,
            blockedDomains: Array(Set(domains.compactMap { normalizedDomain(from: $0) })).sorted(),
            focus: focus,
            updatedAt: updatedAt
        )
    }

    private func save() {
        pruneOldSamples()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let state = PersistedFocusState(sessions: sessions, projects: projects, rules: rules, settings: settings)
        guard let data = try? encoder.encode(state) else { return }
        try? data.write(to: stateURL, options: [.atomic])
        updateDiagnostics()
    }

    private func saveBlockConfig() {
        blockConfig.updatedAt = Date()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(blockConfig) else { return }
        try? data.write(to: blockConfigURL, options: [.atomic])
        updateDiagnostics()
    }

    private func writeTodayExport() throws -> ExportResult {
        let dateStamp = Formatters.fileDate(Date())
        let jsonURL = exportsRoot.appendingPathComponent("arel-focus-today-\(dateStamp).json")
        let csvURL = exportsRoot.appendingPathComponent("arel-focus-today-\(dateStamp).csv")
        let timeline = timelineSessions

        let export = TodayExport(
            exportedAt: Date(),
            totals: ExportTotals(
                activeSeconds: todayActiveDuration,
                backgroundSeconds: todayBackgroundDuration,
                idleSeconds: todayIdleDuration,
                reviewBlockCount: reviewSessions.count,
                rawSessionCount: todaySessions.count,
                timelineBlockCount: timeline.count
            ),
            apps: appSummaries().map { ExportSummary(name: $0.name, seconds: $0.duration) },
            websites: domainSummaries().map { ExportSummary(name: $0.name, seconds: $0.duration) },
            projects: projectSummaries(),
            displays: latestDisplays,
            timeline: timeline
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(export).write(to: jsonURL, options: [.atomic])
        try csv(for: timeline).write(to: csvURL, atomically: true, encoding: .utf8)

        return ExportResult(jsonURL: jsonURL, csvURL: csvURL)
    }

    private func projectSummaries() -> [ExportSummary] {
        var grouped: [String: TimeInterval] = [:]

        for session in todaySessions {
            grouped[projectName(for: session.projectID), default: 0] += session.duration
        }

        return grouped.map { ExportSummary(name: $0.key, seconds: $0.value) }
            .sorted { $0.seconds > $1.seconds }
    }

    private func csv(for timeline: [ActivitySession]) -> String {
        var rows = ["kind,source,detail,project,category,domain,url,chromeProfile,windowID,tabID,windowCount,displays,windowTitles,startedAt,durationSeconds"]

        for session in timeline {
            let windowID = session.windowID.map(String.init) ?? ""
            let tabID = session.tabID.map(String.init) ?? ""
            let windowCount = session.windowCount.map(String.init) ?? ""
            let displayNames = session.displayNames?.joined(separator: " | ") ?? ""
            let windowTitles = session.windowTitles?.joined(separator: " | ") ?? ""
            let startedAt = ISO8601DateFormatter().string(from: session.startedAt)
            let duration = String(format: "%.2f", session.duration)

            let values: [String] = [
                session.kind.label,
                session.sourceName,
                session.detail,
                projectName(for: session.projectID),
                session.category ?? "",
                session.domain ?? "",
                session.url ?? "",
                chromeProfileLabel(for: session) ?? "",
                windowID,
                tabID,
                windowCount,
                displayNames,
                windowTitles,
                startedAt,
                duration
            ]
            rows.append(values.map(escapeCSV).joined(separator: ","))
        }

        return rows.joined(separator: "\n") + "\n"
    }

    private func escapeCSV(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
            return "\"\(escaped)\""
        }
        return escaped
    }

    private func union<T: Hashable>(_ lhs: [T]?, _ rhs: [T]?, limit: Int = .max) -> [T]? {
        var result: [T] = []

        for value in (lhs ?? []) + (rhs ?? []) where !result.contains(value) {
            result.append(value)
            if result.count >= limit {
                break
            }
        }

        return result.isEmpty ? nil : result
    }
}
