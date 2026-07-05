import Foundation

struct ChromeInboxReader {
    static let maxEventLogBytes: UInt64 = 50 * 1_024 * 1_024

    private let decoder = JSONDecoder()

    var inboxURL: URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Arel Focus", isDirectory: true)
        return root.appendingPathComponent("chrome-events.jsonl")
    }

    var supportRoot: URL {
        inboxURL.deletingLastPathComponent()
    }

    func latestEvent() -> ChromeActivityEvent? {
        guard let data = tailData(maxBytes: 1_000_000),
              let text = String(data: data, encoding: .utf8) else { return nil }

        decoder.dateDecodingStrategy = .iso8601

        return text
            .split(separator: "\n")
            .reversed()
            .compactMap { line -> ChromeActivityEvent? in
                guard let row = String(line).data(using: .utf8) else { return nil }
                return try? decoder.decode(ChromeActivityEvent.self, from: row)
            }
            .first { $0.active }
    }

    func events(from start: Date, to end: Date, matchingType type: String? = nil) -> [ChromeActivityEvent] {
        guard end > start,
              let data = tailData(maxBytes: 5_000_000),
              let text = String(data: data, encoding: .utf8) else { return [] }

        decoder.dateDecodingStrategy = .iso8601

        return text
            .split(separator: "\n")
            .compactMap { line -> ChromeActivityEvent? in
                guard let row = String(line).data(using: .utf8),
                      let event = try? decoder.decode(ChromeActivityEvent.self, from: row),
                      event.capturedAt >= start,
                      event.capturedAt <= end
                else { return nil }

                if let type {
                    return event.type == type ? event : nil
                }

                return event
            }
    }

    func eventLogByteCount() -> UInt64 {
        fileSize(at: inboxURL)
    }

    func rotatedEventLogCount() -> Int {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: supportRoot,
            includingPropertiesForKeys: nil
        ) else { return 0 }

        return urls.filter {
            $0.lastPathComponent.hasPrefix("chrome-events-")
                && $0.pathExtension == "jsonl"
        }.count
    }

    func rotateOversizedEventLogIfNeeded(maxBytes: UInt64 = Self.maxEventLogBytes) {
        guard eventLogByteCount() > maxBytes else { return }

        let rotatedURL = supportRoot.appendingPathComponent("chrome-events-\(rotateDateStamp()).jsonl")
        try? FileManager.default.moveItem(at: inboxURL, to: rotatedURL)
        FileManager.default.createFile(atPath: inboxURL.path, contents: nil)
    }

    private func tailData(maxBytes: UInt64) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: inboxURL) else { return nil }
        defer { try? handle.close() }

        let size = (try? handle.seekToEnd()) ?? 0
        let offset = size > maxBytes ? size - maxBytes : 0
        try? handle.seek(toOffset: offset)
        return try? handle.readToEnd()
    }

    private func fileSize(at url: URL) -> UInt64 {
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber else {
            return 0
        }
        return size.uint64Value
    }

    private func rotateDateStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
