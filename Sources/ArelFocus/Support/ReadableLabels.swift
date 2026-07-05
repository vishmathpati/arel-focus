import Foundation

enum ReadableLabels {
    static func appName(_ rawValue: String) -> String {
        let cleaned = rawValue
            .replacingOccurrences(of: "\u{200E}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return "Unknown" }

        switch cleaned.lowercased() {
        case "usernotificationcenter":
            return "Notifications"
        case "coreservicesuiagent":
            return "System Prompt"
        default:
            return cleaned
        }
    }
}
