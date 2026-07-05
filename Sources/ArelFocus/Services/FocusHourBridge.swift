import Foundation

/// Tolerant ISO8601 parsing — accepts timestamps with OR without fractional
/// seconds. arel-os writes every timestamp with JS `new Date().toISOString()`,
/// which always carries fractional seconds (…:00.000Z); Swift's own encoder omits
/// them. Both must decode. JSONDecoder's stock `.iso8601` strategy rejects the
/// fractional form, which silently dropped every command arel-os sent.
enum FocusISO8601 {
    private static let withFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func date(from string: String) -> Date? {
        withFractionalSeconds.date(from: string) ?? plain.date(from: string)
    }
}

enum FocusHourBridgeCommand {
    case start(FocusHourStartCommand)
    case update(FocusHourUpdateCommand)
    case rescue(FocusHourRescueCommand)
    case cancel(FocusHourCancelCommand)
}

struct FocusHourBridge {
    private let fileManager = FileManager.default
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init() {
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { dec in
            let container = try dec.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = FocusISO8601.date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognized ISO8601 date: \(raw)"
                )
            }
            return date
        }

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var bridgeRoot: URL {
        let root = supportRoot.appendingPathComponent("bridge", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    var commandsRoot: URL {
        let root = bridgeRoot.appendingPathComponent("commands", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    var processedRoot: URL {
        let root = bridgeRoot.appendingPathComponent("processed", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    var resultsRoot: URL {
        let root = bridgeRoot.appendingPathComponent("results", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    var stateURL: URL {
        bridgeRoot.appendingPathComponent("state.json")
    }

    var activeFocusHourURL: URL {
        bridgeRoot.appendingPathComponent("active-focus-hour.json")
    }

    func consumePendingCommands() -> [FocusHourBridgeCommand] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: commandsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            .filter { $0.pathExtension == "json" }
            .sorted { modifiedAt($0) < modifiedAt($1) }
            .compactMap { url in
                guard let command = decodeCommand(at: url) else {
                    archiveCommand(at: url, suffix: "invalid")
                    return nil
                }
                archiveCommand(at: url, suffix: "processed")
                return command
            }
    }

    func writeState(_ state: FocusHourStateSnapshot) {
        write(state, to: stateURL)
    }

    func loadState() -> FocusHourStateSnapshot? {
        guard let data = try? Data(contentsOf: stateURL) else { return nil }
        return try? decoder.decode(FocusHourStateSnapshot.self, from: data)
    }

    func writeActiveFocusHour(_ activeFocusHour: ActiveFocusHour) {
        write(activeFocusHour, to: activeFocusHourURL)
    }

    func loadActiveFocusHour() -> ActiveFocusHour? {
        guard let data = try? Data(contentsOf: activeFocusHourURL),
              let activeFocusHour = try? decoder.decode(ActiveFocusHour.self, from: data),
              activeFocusHour.command.isValid
        else { return nil }
        return activeFocusHour
    }

    func clearActiveFocusHour() {
        try? fileManager.removeItem(at: activeFocusHourURL)
    }

    func loadStartCommand(sessionID: String) -> FocusHourStartCommand? {
        guard !sessionID.isEmpty else { return nil }

        let roots = [commandsRoot, processedRoot]
        return roots
            .flatMap { startCommandCandidates(in: $0, sessionID: sessionID) }
            .sorted { modifiedAt($0) > modifiedAt($1) }
            .compactMap { url -> FocusHourStartCommand? in
                guard let data = try? Data(contentsOf: url),
                      let command = try? decoder.decode(FocusHourStartCommand.self, from: data),
                      command.isValid,
                      command.sessionID == sessionID
                else { return nil }
                return command
            }
            .first
    }

    func writeResult(_ result: FocusHourSessionResult) {
        let url = resultsRoot.appendingPathComponent("\(result.sessionID).json")
        write(result, to: url)
        // The result file is canonical — arel-os reads it via GET /focus/result.
        // (A stale best-effort POST to the old :1347 endpoint lived here; the new
        // arel-os has no such ingest route, so it was dead and has been removed.)
    }

    func loadResults() -> [FocusHourSessionResult] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: resultsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> FocusHourSessionResult? in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(FocusHourSessionResult.self, from: data)
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    private var supportRoot: URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Arel Focus", isDirectory: true)
        try? fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func decodeCommand(at url: URL) -> FocusHourBridgeCommand? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let name = url.lastPathComponent

        if name.hasSuffix(".start.json"),
           let command = try? decoder.decode(FocusHourStartCommand.self, from: data),
           command.isValid {
            return .start(command)
        }

        if name.hasSuffix(".update.json"),
           let command = try? decoder.decode(FocusHourUpdateCommand.self, from: data),
           command.isValid {
            return .update(command)
        }

        if name.hasSuffix(".rescue.json"),
           let command = try? decoder.decode(FocusHourRescueCommand.self, from: data),
           command.isValid {
            return .rescue(command)
        }

        if name.hasSuffix(".cancel.json"),
           let command = try? decoder.decode(FocusHourCancelCommand.self, from: data),
           command.isValid {
            return .cancel(command)
        }

        return nil
    }

    private func write<T: Encodable>(_ value: T, to url: URL) {
        guard let data = try? encoder.encode(value) else { return }
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: [.atomic])
    }

    private func archiveCommand(at url: URL, suffix: String) {
        let stamp = archiveStamp()
        let destination = processedRoot.appendingPathComponent("\(url.deletingPathExtension().lastPathComponent).\(stamp).\(suffix).json")
        try? fileManager.moveItem(at: url, to: destination)
    }

    private func startCommandCandidates(in root: URL, sessionID: String) -> [URL] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return urls.filter { url in
            let name = url.lastPathComponent
            return url.pathExtension == "json"
                && name.hasPrefix("\(sessionID).start")
        }
    }

    private func modifiedAt(_ url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate ?? .distantPast
    }

    private func archiveStamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmssSSS"
        return formatter.string(from: Date())
    }
}
