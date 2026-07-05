import Foundation

struct IncomingChromeMessage: Codable {
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
    var active: Bool?
    var capturedAt: String?
    var openTabs: [IncomingChromeTab]?
    // Set on a "focusAllowDomain" control message from the block page.
    var sessionID: String?
}

struct IncomingChromeTab: Codable {
    var tabID: Int
    var windowID: Int
    var url: String?
    var title: String?
    var favIconURL: String?
    var favIconDataURL: String?
    var profileID: String?
    var profileName: String?
    var active: Bool
}

struct StoredChromeEvent: Codable {
    var id = UUID()
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
    var openTabs: [StoredChromeTab]
}

struct StoredChromeTab: Codable {
    var tabID: Int
    var windowID: Int
    var url: String?
    var title: String?
    var favIconURL: String?
    var favIconDataURL: String?
    var profileID: String?
    var profileName: String?
    var active: Bool
}

let input = FileHandle.standardInput
let output = FileHandle.standardOutput
let decoder = JSONDecoder()
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601
let maxEventLogBytes: UInt64 = 50 * 1_024 * 1_024

func applicationSupportURL() -> URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Arel Focus", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("chrome-events.jsonl")
}

func blockConfigURL() -> URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Arel Focus", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root.appendingPathComponent("block-config.json")
}

func bridgeCommandsURL() -> URL {
    let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Arel Focus", isDirectory: true)
        .appendingPathComponent("bridge", isDirectory: true)
        .appendingPathComponent("commands", isDirectory: true)
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// The block page's "Allow {domain} for this session" button routes here via the
/// service worker. We compute the new full effective block list (current minus the
/// allowed domain) and drop an `update_focus_hour` command file for the app to
/// consume on its next bridge poll (~2s), which re-emits block-config to Chrome.
func writeFocusAllowUpdate(sessionID: String, domain: String) -> Bool {
    let normalized = domain
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        .lowercased()
    guard !sessionID.isEmpty, !normalized.isEmpty else { return false }

    let current = (loadBlockConfig()?["blockedDomains"] as? [String]) ?? []
    let newBlocked = current.filter { $0.lowercased() != normalized }

    let command: [String: Any] = [
        "schema_version": "arel-focus-hour.v2",
        "command": "update_focus_hour",
        "session_id": sessionID,
        "blocked": newBlocked,
        "requested_at": ISO8601DateFormatter().string(from: Date()),
        "requested_by": "arel-os"
    ]

    guard JSONSerialization.isValidJSONObject(command),
          let data = try? JSONSerialization.data(withJSONObject: command, options: [.prettyPrinted])
    else { return false }

    let url = bridgeCommandsURL().appendingPathComponent("\(sessionID).update.json")
    do {
        try data.write(to: url, options: [.atomic])
        return true
    } catch {
        return false
    }
}

func readMessage() -> Data? {
    let lengthData = input.readData(ofLength: 4)
    guard lengthData.count == 4 else { return nil }

    let bytes = [UInt8](lengthData)
    let length = UInt32(bytes[0])
        | (UInt32(bytes[1]) << 8)
        | (UInt32(bytes[2]) << 16)
        | (UInt32(bytes[3]) << 24)

    guard length > 0, length < 1_000_000 else { return nil }
    let body = input.readData(ofLength: Int(length))
    return body.count == Int(length) ? body : nil
}

// All stdout writes go through this lock so the background block-config watcher
// (proactive push) and the main read loop's responses never interleave a frame.
let outputLock = NSLock()

func writeFramed(_ data: Data) {
    var length = UInt32(data.count).littleEndian
    let prefix = Data(bytes: &length, count: 4)
    outputLock.lock()
    defer { outputLock.unlock() }
    output.write(prefix)
    output.write(data)
}

func writeResponse(_ object: [String: String]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object) else { return }
    writeFramed(data)
}

func writeResponseObject(_ object: [String: Any]) {
    guard JSONSerialization.isValidJSONObject(object),
          let data = try? JSONSerialization.data(withJSONObject: object)
    else { return }
    writeFramed(data)
}

func normalize(_ message: IncomingChromeMessage) -> StoredChromeEvent {
    let parsedDate = message.capturedAt.flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
    return StoredChromeEvent(
        type: message.type,
        url: message.url,
        title: message.title,
        domain: message.domain,
        favIconURL: message.favIconURL,
        favIconDataURL: message.favIconDataURL,
        tabID: message.tabID,
        windowID: message.windowID,
        profileID: message.profileID,
        profileName: message.profileName,
        active: message.active ?? true,
        capturedAt: parsedDate,
        openTabs: (message.openTabs ?? []).map {
            StoredChromeTab(
                tabID: $0.tabID,
                windowID: $0.windowID,
                url: $0.url,
                title: $0.title,
                favIconURL: $0.favIconURL,
                favIconDataURL: $0.favIconDataURL,
                profileID: $0.profileID ?? message.profileID,
                profileName: $0.profileName ?? message.profileName,
                active: $0.active
            )
        }
    )
}

func append(_ event: StoredChromeEvent) {
    guard let data = try? encoder.encode(event),
          let line = String(data: data, encoding: .utf8)?.appending("\n").data(using: .utf8)
    else { return }

    let url = applicationSupportURL()
    rotateEventLogIfNeeded(url)
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    guard let handle = try? FileHandle(forWritingTo: url) else { return }
    defer { try? handle.close() }
    _ = try? handle.seekToEnd()
    handle.write(line)
}

func rotateEventLogIfNeeded(_ url: URL) {
    guard let sizeNumber = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber,
          sizeNumber.uint64Value > maxEventLogBytes
    else { return }

    let rotatedURL = url.deletingLastPathComponent()
        .appendingPathComponent("chrome-events-\(rotateDateStamp()).jsonl")
    try? FileManager.default.moveItem(at: url, to: rotatedURL)
}

func rotateDateStamp() -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd-HHmmss"
    return formatter.string(from: Date())
}

func loadBlockConfig() -> [String: Any]? {
    guard let data = try? Data(contentsOf: blockConfigURL()),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }

    var config: [String: Any] = [
        "blockingEnabled": object["blockingEnabled"] as? Bool ?? false,
        "blockedDomains": object["blockedDomains"] as? [String] ?? []
    ]
    // Pass the Focus Hour context through so the branded block page has its copy.
    if let focus = object["focus"] as? [String: Any] {
        config["focus"] = [
            "target_name": focus["target_name"] as? String ?? "",
            "profile_label": focus["profile_label"] as? String ?? "",
            "session_id": focus["session_id"] as? String ?? ""
        ]
    }
    return config
}

// ── Proactive block-config push ─────────────────────────────────────────────
// The extension only pulls block-config in RESPONSE to its own tab events, so a
// mid-session change — arel-os temp-allow toggle, the block-page "Allow" button,
// session start/end — wouldn't reach Chrome until the next event, and then the
// rule update races the navigation. Watch the support dir and push the new
// block-config the instant the app rewrites block-config.json (an atomic write is
// a directory change), so Chrome's dynamic block rules track it live. The
// extension's existing port.onMessage handler applies any pushed blockConfig.
var blockConfigWatchSource: DispatchSourceFileSystemObject?
var lastPushedBlockConfigData: Data? = try? Data(contentsOf: blockConfigURL())

func pushBlockConfigIfChanged() {
    let data = try? Data(contentsOf: blockConfigURL())
    guard data != lastPushedBlockConfigData else { return }
    lastPushedBlockConfigData = data
    if let blockConfig = loadBlockConfig() {
        writeResponseObject(["ok": true, "blockConfig": blockConfig])
    }
}

func startBlockConfigWatcher() {
    let dir = blockConfigURL().deletingLastPathComponent()
    let fd = open(dir.path, O_EVTONLY)
    guard fd >= 0 else { return }
    let queue = DispatchQueue(label: "com.arel.focus.blockconfig-watch")
    let source = DispatchSource.makeFileSystemObjectSource(
        fileDescriptor: fd,
        eventMask: [.write],
        queue: queue
    )
    source.setEventHandler(handler: pushBlockConfigIfChanged)
    source.setCancelHandler { close(fd) }
    source.resume()
    blockConfigWatchSource = source
}

startBlockConfigWatcher()

while let body = readMessage() {
    do {
        let message = try decoder.decode(IncomingChromeMessage.self, from: body)

        // Control message from the branded block page: allow a domain for the
        // rest of the active session. Don't log it as browsing activity.
        if message.type == "focusAllowDomain" {
            let ok = writeFocusAllowUpdate(
                sessionID: message.sessionID ?? "",
                domain: message.domain ?? ""
            )
            writeResponseObject(["ok": ok, "type": "focusAllowDomain"])
            continue
        }

        append(normalize(message))
        if let blockConfig = loadBlockConfig() {
            writeResponseObject(["ok": true, "blockConfig": blockConfig])
        } else {
            writeResponse(["ok": "true"])
        }
    } catch {
        writeResponse(["ok": "false", "error": error.localizedDescription])
    }
}
