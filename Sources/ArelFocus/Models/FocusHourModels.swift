import Foundation

// v2 is the current schema (notion owns profiles + block lists). v1 is still
// accepted on decode so an older arel-os caller keeps working.
let focusHourSchemaVersion = "arel-focus-hour.v2"
let focusHourSchemaVersionLegacy = "arel-focus-hour.v1"

func isAcceptedFocusHourSchema(_ version: String) -> Bool {
    version == focusHourSchemaVersion || version == focusHourSchemaVersionLegacy
}

// Fallback-only profile catalog. In v2 the block list comes inline from the
// `profile` object that notion sends; these hard-coded domains are used only
// when that inline list is empty/absent (safety net). `profile_id` itself is a
// free string on the wire — unknown ids are valid and just label the session.
enum FocusHourProfileID: String, Codable, CaseIterable, Identifiable {
    case deepWork = "deep_work"
    case research
    case coding
    case writing
    case admin

    var id: String { rawValue }

    var label: String {
        switch self {
        case .deepWork: "Deep Work"
        case .research: "Research"
        case .coding: "Coding"
        case .writing: "Writing"
        case .admin: "Admin"
        }
    }

    var blockedDomains: [String] {
        switch self {
        case .deepWork:
            return [
                "facebook.com", "instagram.com", "x.com", "twitter.com", "youtube.com",
                "reddit.com", "tiktok.com", "netflix.com", "primevideo.com",
                "hotstar.com", "news.google.com", "amazon.com", "flipkart.com"
            ]
        case .research:
            return [
                "facebook.com", "instagram.com", "x.com", "twitter.com",
                "reddit.com", "tiktok.com", "netflix.com", "primevideo.com",
                "amazon.com", "flipkart.com"
            ]
        case .coding:
            return [
                "facebook.com", "instagram.com", "x.com", "twitter.com", "youtube.com",
                "reddit.com", "tiktok.com", "netflix.com", "primevideo.com",
                "news.google.com", "amazon.com", "flipkart.com"
            ]
        case .writing:
            return [
                "facebook.com", "instagram.com", "x.com", "twitter.com", "youtube.com",
                "reddit.com", "tiktok.com", "netflix.com", "primevideo.com",
                "news.google.com"
            ]
        case .admin:
            return [
                "facebook.com", "instagram.com", "x.com", "twitter.com",
                "reddit.com", "tiktok.com", "netflix.com", "primevideo.com"
            ]
        }
    }

    /// Fallback domains for a free-string profile id, used only when notion
    /// sends no inline block list. Unknown ids resolve to no fallback domains.
    static func fallbackBlockedDomains(for rawID: String) -> [String] {
        FocusHourProfileID(rawValue: rawID)?.blockedDomains ?? []
    }

    /// Best-effort human label for a free-string profile id. Falls back to a
    /// title-cased version of the id so unknown profiles still read cleanly.
    static func label(for rawID: String) -> String {
        if let known = FocusHourProfileID(rawValue: rawID) {
            return known.label
        }
        let words = rawID.split(whereSeparator: { $0 == "_" || $0 == "-" })
        guard !words.isEmpty else { return rawID }
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}

enum FocusHourRuntimeState: String, Codable {
    case idle
    case planning
    case working
    case reflecting
    case rescued
    case completed
    case cancelled

    var isRunning: Bool {
        self == .planning || self == .working || self == .reflecting
    }

    var label: String {
        switch self {
        case .idle: "Idle"
        case .planning: "Planning"
        case .working: "Working"
        case .reflecting: "Reflecting"
        case .rescued: "Rescued"
        case .completed: "Completed"
        case .cancelled: "Cancelled"
        }
    }
}

struct FocusHourEntity: Codable, Equatable {
    var id: String
    var name: String
}

struct FocusHourDurations: Codable, Equatable {
    var planMin: Int
    var workMin: Int
    var reflectMin: Int

    enum CodingKeys: String, CodingKey {
        case planMin = "plan_min"
        case workMin = "work_min"
        case reflectMin = "reflect_min"
    }
}

struct FocusHourProfile: Codable, Equatable {
    var id: String
    var label: String
    var blocked: [String]
    var allowed: [String]
}

struct FocusHourPrivacy: Codable, Equatable {
    var screenshots: Bool
    var keylogging: Bool
    var clipboardCapture: Bool
    var teamSurveillance: Bool

    enum CodingKeys: String, CodingKey {
        case screenshots
        case keylogging
        case clipboardCapture = "clipboard_capture"
        case teamSurveillance = "team_surveillance"
    }
}

struct FocusHourStartCommand: Codable, Equatable {
    var schemaVersion: String
    var command: String
    var sessionID: String
    var project: FocusHourEntity
    var task: FocusHourEntity?
    var profileID: String
    var profile: FocusHourProfile?
    var durations: FocusHourDurations
    var planNotes: String
    var startAt: Date
    var requestedBy: String
    var privacy: FocusHourPrivacy

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case command
        case sessionID = "session_id"
        case project
        case task
        case profileID = "profile_id"
        case profile
        case durations
        case planNotes = "plan_notes"
        case startAt = "start_at"
        case requestedBy = "requested_by"
        case privacy
    }

    var isValid: Bool {
        isAcceptedFocusHourSchema(schemaVersion)
            && command == "start_focus_hour"
            && requestedBy == "arel-os"
            && !sessionID.isEmpty
            && !project.id.isEmpty
            && !project.name.isEmpty
            && !privacy.screenshots
            && !privacy.keylogging
            && !privacy.clipboardCapture
            && !privacy.teamSurveillance
    }

    /// Domains to enforce during Work: the inline list notion sent, falling
    /// back to the hard-coded catalog only when that list is empty/absent.
    var effectiveBlockedDomains: [String] {
        if let inline = profile?.blocked, !inline.isEmpty {
            return inline
        }
        return FocusHourProfileID.fallbackBlockedDomains(for: profileID)
    }

    /// Human label for the block page: prefer the inline profile label, else
    /// resolve from the id.
    var profileLabel: String {
        if let label = profile?.label, !label.isEmpty {
            return label
        }
        return FocusHourProfileID.label(for: profileID)
    }
}

struct FocusHourRescueCommand: Codable, Equatable {
    var schemaVersion: String
    var command: String
    var sessionID: String
    var reason: String?
    var requestedAt: Date
    var requestedBy: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case command
        case sessionID = "session_id"
        case reason
        case requestedAt = "requested_at"
        case requestedBy = "requested_by"
    }

    var isValid: Bool {
        isAcceptedFocusHourSchema(schemaVersion)
            && command == "rescue_focus_hour"
            && requestedBy == "arel-os"
            && !sessionID.isEmpty
    }
}

struct FocusHourUpdateCommand: Codable, Equatable {
    var schemaVersion: String
    var command: String
    var sessionID: String
    var blocked: [String]
    var requestedAt: Date
    var requestedBy: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case command
        case sessionID = "session_id"
        case blocked
        case requestedAt = "requested_at"
        case requestedBy = "requested_by"
    }

    var isValid: Bool {
        isAcceptedFocusHourSchema(schemaVersion)
            && command == "update_focus_hour"
            && requestedBy == "arel-os"
            && !sessionID.isEmpty
    }
}

struct FocusHourCancelCommand: Codable, Equatable {
    var schemaVersion: String
    var command: String
    var sessionID: String
    var requestedAt: Date
    var requestedBy: String

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case command
        case sessionID = "session_id"
        case requestedAt = "requested_at"
        case requestedBy = "requested_by"
    }

    var isValid: Bool {
        isAcceptedFocusHourSchema(schemaVersion)
            && command == "cancel_focus_hour"
            && requestedBy == "arel-os"
            && !sessionID.isEmpty
    }
}

struct FocusHourRescueInfo: Codable, Equatable {
    var used: Bool
    var activatedAt: Date?
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case used
        case activatedAt = "activated_at"
        case reason
    }
}

struct FocusHourStateSnapshot: Codable, Equatable {
    var schemaVersion: String = focusHourSchemaVersion
    var state: FocusHourRuntimeState
    var sessionID: String?
    var updatedAt: Date
    var source: String = "arel-focus"
    var project: FocusHourEntity?
    var task: FocusHourEntity?
    var profileID: String?
    var blockedNow: [String]?
    var allowedOverrides: [String]?
    var phaseStartedAt: Date?
    var rescue: FocusHourRescueInfo?

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case state
        case sessionID = "session_id"
        case updatedAt = "updated_at"
        case source
        case project
        case task
        case profileID = "profile_id"
        case blockedNow = "blocked_now"
        case allowedOverrides = "allowed_overrides"
        case phaseStartedAt = "phase_started_at"
        case rescue
    }

    static func idle(now: Date = Date()) -> FocusHourStateSnapshot {
        FocusHourStateSnapshot(state: .idle, sessionID: nil, updatedAt: now)
    }
}

struct FocusHourActualDurations: Codable, Equatable {
    var planMin: Int
    var workMin: Int
    var reflectMin: Int
    var totalMin: Int

    enum CodingKeys: String, CodingKey {
        case planMin = "plan_min"
        case workMin = "work_min"
        case reflectMin = "reflect_min"
        case totalMin = "total_min"
    }
}

struct FocusHourPlanningSummary: Codable, Equatable {
    var websitesVisited: [String]

    enum CodingKeys: String, CodingKey {
        case websitesVisited = "websites_visited"
    }
}

struct FocusHourWorkSummary: Codable, Equatable {
    var appsUsed: [String]
    var websitesUsed: [String]
    var blockedSiteAttempts: [String]

    enum CodingKeys: String, CodingKey {
        case appsUsed = "apps_used"
        case websitesUsed = "websites_used"
        case blockedSiteAttempts = "blocked_site_attempts"
    }
}

struct FocusHourReflectionSummary: Codable, Equatable {
    var status: String
    var text: String?
}

struct FocusHourSessionResult: Codable, Equatable {
    var schemaVersion: String = focusHourSchemaVersion
    var sessionID: String
    var state: FocusHourRuntimeState
    var startedAt: Date
    var endedAt: Date
    var project: FocusHourEntity
    var task: FocusHourEntity?
    var profileID: String
    var plannedDurations: FocusHourDurations
    var actualDurations: FocusHourActualDurations
    var planNotes: String?
    var planning: FocusHourPlanningSummary
    var work: FocusHourWorkSummary
    var allowedOverrides: [String]
    var rescue: FocusHourRescueInfo
    var reflection: FocusHourReflectionSummary

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sessionID = "session_id"
        case state
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case project
        case task
        case profileID = "profile_id"
        case plannedDurations = "planned_durations"
        case actualDurations = "actual_durations"
        case planNotes = "plan_notes"
        case planning
        case work
        case allowedOverrides = "allowed_overrides"
        case rescue
        case reflection
    }
}

struct ActiveFocusHour: Codable, Equatable {
    var command: FocusHourStartCommand
    var localProjectID: UUID?
    var localProjectCategory: String?
    var originalBlockConfig: BlockConfig
    var phaseStartedAt: Date
    // Domains allowed for the rest of this session via temp-allow (§3).
    // Subtracted from the profile's block list when enforcing during Work.
    var allowedOverrides: [String] = []

    var startedAt: Date { command.startAt }
    var planEnd: Date { startedAt.addingTimeInterval(TimeInterval(command.durations.planMin * 60)) }
    var workEnd: Date { planEnd.addingTimeInterval(TimeInterval(command.durations.workMin * 60)) }
    var reflectEnd: Date { workEnd.addingTimeInterval(TimeInterval(command.durations.reflectMin * 60)) }
}
