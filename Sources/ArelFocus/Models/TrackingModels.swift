import Foundation

enum ActivityKind: String, Codable, CaseIterable, Identifiable {
    case activeApp
    case backgroundApp
    case chromeTab
    case openChromeTab
    case idle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .activeApp: "Active App"
        case .backgroundApp: "Background App"
        case .chromeTab: "Chrome Tab"
        case .openChromeTab: "Open Chrome Tab"
        case .idle: "Idle"
        }
    }
}

enum MatchField: String, Codable, CaseIterable, Identifiable {
    case bundleID
    case appName
    case domain
    case url
    case title

    var id: String { rawValue }
}

struct ActivitySession: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var kind: ActivityKind
    var sourceName: String
    var detail: String
    var bundleID: String?
    var url: String?
    var domain: String?
    var favIconURL: String?
    var favIconDataURL: String?
    var tabID: Int?
    var windowID: Int?
    var chromeProfileID: String?
    var chromeProfileName: String?
    var windowCount: Int?
    var displayIDs: [UInt32]?
    var displayNames: [String]?
    var windowTitles: [String]?
    var projectID: UUID?
    var category: String?
    var startedAt: Date
    var duration: TimeInterval

    var endedAt: Date {
        startedAt.addingTimeInterval(duration)
    }

    var isUncategorized: Bool {
        projectID == nil && kind != .idle
    }
}

struct FocusProject: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var name: String
    var category: String
    var colorHex: String
    var createdAt: Date = Date()
}

struct CategorizationRule: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var field: MatchField
    var pattern: String
    var projectID: UUID
    var category: String
    var createdAt: Date = Date()
}

struct ChromeActivityEvent: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    var type: String
    var url: String?
    var title: String?
    var domain: String?
    var favIconURL: String?
    var favIconDataURL: String?
    var tabID: Int?
    var windowID: Int?
    var profileID: String?
    var profileName: String?
    var active: Bool
    var capturedAt: Date
    var openTabs: [ChromeTabSnapshot]
}

struct ChromeTabSnapshot: Identifiable, Codable, Equatable {
    var id: String { "\(windowID)-\(tabID)" }
    var tabID: Int
    var windowID: Int
    var profileID: String?
    var profileName: String?
    var url: String?
    var title: String?
    var favIconURL: String?
    var favIconDataURL: String?
    var active: Bool
}

struct FocusSettings: Codable, Equatable {
    var idleThresholdSeconds: TimeInterval = 180
    var trackingPaused: Bool = false
    var excludedBundleIDs: [String] = []
    var excludedDomains: [String] = []
}

/// Focus-session context the Chrome block page needs for its copy. Present only
/// while an Arel OS Focus Hour is in its Work phase; nil for plain Settings blocking.
struct BlockFocusContext: Codable, Equatable {
    var targetName: String
    var profileLabel: String
    var sessionID: String

    enum CodingKeys: String, CodingKey {
        case targetName = "target_name"
        case profileLabel = "profile_label"
        case sessionID = "session_id"
    }
}

struct BlockConfig: Codable, Equatable {
    var blockingEnabled: Bool = false
    var blockedDomains: [String] = []
    var focus: BlockFocusContext? = nil
    var updatedAt: Date = Date()
}

struct PersistedFocusState: Codable {
    var sessions: [ActivitySession]
    var projects: [FocusProject]
    var rules: [CategorizationRule]
    var settings: FocusSettings
}

struct AppSnapshot {
    var activeAppName: String
    var activeBundleID: String?
    var activeWindowTitle: String
    var visibleApps: [VisibleApp]
    var visibleWindows: [VisibleWindow]
    var displays: [DisplaySnapshot]
}

struct VisibleApp: Identifiable, Hashable {
    var id: String { bundleID ?? name }
    var name: String
    var bundleID: String?
    var windowCount: Int = 0
    var displayIDs: [UInt32] = []
    var displayNames: [String] = []
    var windowTitles: [String] = []
}

struct VisibleWindow: Identifiable, Hashable {
    var id: UInt32
    var appName: String
    var bundleID: String?
    var title: String
    var displayID: UInt32?
    var displayName: String?
}

struct DisplaySnapshot: Identifiable, Codable, Hashable {
    var id: UInt32
    var name: String
    var isMain: Bool
    var visibleWindowCount: Int
}

struct DurationSummary: Identifiable {
    var id: String { name }
    var name: String
    var duration: TimeInterval
    var bundleID: String?
    var favIconURL: String?
    var favIconDataURL: String?
}

enum ReviewScope: String, CaseIterable, Identifiable {
    case today
    case thisWeek
    case last15Days

    var id: String { rawValue }

    var label: String {
        switch self {
        case .today: "Today"
        case .thisWeek: "This week"
        case .last15Days: "15 days"
        }
    }
}

struct ReviewCandidate: Identifiable {
    var id: String
    var field: MatchField
    var pattern: String
    var sourceName: String
    var detail: String
    var representativeKind: ActivityKind
    var bundleID: String?
    var domain: String?
    var favIconURL: String?
    var favIconDataURL: String?
    var sessionIDs: [UUID]
    var sessionCount: Int
    var totalDuration: TimeInterval
    var firstSeen: Date
    var lastSeen: Date

    var ruleLabel: String {
        switch field {
        case .bundleID: "App"
        case .appName: "App name"
        case .domain: "Domain"
        case .url: "URL"
        case .title: "Title"
        }
    }
}

struct ReviewStats {
    var sessionCount: Int
    var candidateCount: Int
    var uncategorizedDuration: TimeInterval
}

struct FocusDiagnostics {
    var focusStateBytes: UInt64 = 0
    var focusStateModifiedAt: Date?
    var chromeEventLogBytes: UInt64 = 0
    var rotatedChromeLogCount: Int = 0
    var latestChromeEventAt: Date?
    var sessionDaysInLast15: Int = 0
    var reviewCandidateCount: Int = 0
    var reviewUncategorizedDuration: TimeInterval = 0
    var nativeHostPath: String?
    var nativeHostExists: Bool = false
    var nativeHostMatchesCurrentBridge: Bool = false
    var blockingEnabled: Bool = false
    var blockedDomainCount: Int = 0

    var chromeEventLogSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(chromeEventLogBytes), countStyle: .file)
    }

    var focusStateSizeLabel: String {
        ByteCountFormatter.string(fromByteCount: Int64(focusStateBytes), countStyle: .file)
    }
}
