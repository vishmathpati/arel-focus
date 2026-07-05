import Foundation

struct TodayExport: Codable {
    var exportedAt: Date
    var totals: ExportTotals
    var apps: [ExportSummary]
    var websites: [ExportSummary]
    var projects: [ExportSummary]
    var displays: [DisplaySnapshot]
    var timeline: [ActivitySession]
}

struct ExportTotals: Codable {
    var activeSeconds: TimeInterval
    var backgroundSeconds: TimeInterval
    var idleSeconds: TimeInterval
    var reviewBlockCount: Int
    var rawSessionCount: Int
    var timelineBlockCount: Int
}

struct ExportSummary: Codable {
    var name: String
    var seconds: TimeInterval
}

struct ExportResult {
    var jsonURL: URL
    var csvURL: URL
}
