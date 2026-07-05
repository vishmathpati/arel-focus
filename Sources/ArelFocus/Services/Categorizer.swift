import Foundation

struct Categorizer {
    func apply(to session: ActivitySession, rules: [CategorizationRule]) -> ActivitySession {
        guard session.projectID == nil else { return session }

        for rule in rules where matches(rule: rule, session: session) {
            var updated = session
            updated.projectID = rule.projectID
            updated.category = rule.category
            return updated
        }

        return session
    }

    func rule(from session: ActivitySession, project: FocusProject) -> CategorizationRule? {
        if let domain = session.domain, !domain.isEmpty {
            return CategorizationRule(field: .domain, pattern: domain, projectID: project.id, category: project.category)
        }

        if let bundleID = session.bundleID, !bundleID.isEmpty {
            return CategorizationRule(field: .bundleID, pattern: bundleID, projectID: project.id, category: project.category)
        }

        if !session.sourceName.isEmpty {
            return CategorizationRule(field: .appName, pattern: session.sourceName, projectID: project.id, category: project.category)
        }

        return nil
    }

    func matches(rule: CategorizationRule, session: ActivitySession) -> Bool {
        let needle = rule.pattern.lowercased()
        let haystack: String

        switch rule.field {
        case .bundleID:
            haystack = session.bundleID ?? ""
        case .appName:
            haystack = session.sourceName
        case .domain:
            haystack = session.domain ?? ""
        case .url:
            haystack = session.url ?? ""
        case .title:
            haystack = session.detail
        }

        let normalizedHaystack = haystack.lowercased()
        switch rule.field {
        case .bundleID, .appName, .domain:
            return normalizedHaystack == needle
        case .url, .title:
            return normalizedHaystack.contains(needle)
        }
    }
}
