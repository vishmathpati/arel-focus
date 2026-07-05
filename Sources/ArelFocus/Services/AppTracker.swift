import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

struct AppTracker {
    func snapshot() -> AppSnapshot {
        let workspace = NSWorkspace.shared
        let active = workspace.frontmostApplication
        let activeName = active?.localizedName ?? "Unknown"
        let activeBundleID = active?.bundleIdentifier
        let activeTitle = active.flatMap { frontmostWindowTitle(for: $0.processIdentifier) } ?? ""
        let displays = displaySnapshots()
        let windows = visibleWindows(displays: displays)

        return AppSnapshot(
            activeAppName: activeName,
            activeBundleID: activeBundleID,
            activeWindowTitle: activeTitle,
            visibleApps: visibleWindowOwners(windows: windows, fallbackActive: active),
            visibleWindows: windows,
            displays: displaysWithWindowCounts(displays, windows: windows)
        )
    }

    private func frontmostWindowTitle(for pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value)

        guard focusedResult == .success, let window = value else {
            return nil
        }

        var titleValue: CFTypeRef?
        let titleResult = AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &titleValue)

        guard titleResult == .success else {
            return nil
        }

        return titleValue as? String
    }

    private func visibleWindowOwners(windows: [VisibleWindow], fallbackActive: NSRunningApplication?) -> [VisibleApp] {
        var ownerMap: [String: VisibleApp] = [:]

        for window in windows {
            let key = window.bundleID ?? window.appName
            var app = ownerMap[key] ?? VisibleApp(name: window.appName, bundleID: window.bundleID)
            app.windowCount += 1

            if let displayID = window.displayID, !app.displayIDs.contains(displayID) {
                app.displayIDs.append(displayID)
            }

            if let displayName = window.displayName, !app.displayNames.contains(displayName) {
                app.displayNames.append(displayName)
            }

            let title = window.title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty, !app.windowTitles.contains(title), app.windowTitles.count < 5 {
                app.windowTitles.append(title)
            }

            ownerMap[key] = app
        }

        var owners = Array(ownerMap.values)

        if owners.isEmpty {
            owners = NSWorkspace.shared.runningApplications
                .filter { $0.activationPolicy == .regular }
                .compactMap { app in
                    guard let name = app.localizedName else { return nil }
                    return VisibleApp(name: name, bundleID: app.bundleIdentifier, windowCount: 0)
                }
        }

        if let fallbackActive, let name = fallbackActive.localizedName {
            let key = fallbackActive.bundleIdentifier ?? name
            if !owners.contains(where: { ($0.bundleID ?? $0.name) == key }) {
                owners.append(VisibleApp(name: name, bundleID: fallbackActive.bundleIdentifier, windowCount: 0))
            }
        }

        return owners.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func visibleWindows(displays: [DisplaySnapshot]) -> [VisibleWindow] {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let regularApps = Dictionary(uniqueKeysWithValues: NSWorkspace.shared.runningApplications.compactMap { app -> (pid_t, NSRunningApplication)? in
            guard app.activationPolicy == .regular else { return nil }
            return (app.processIdentifier, app)
        })

        var visible: [VisibleWindow] = []

        for window in windowInfo {
            guard
                let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                let windowNumber = window[kCGWindowNumber as String] as? UInt32,
                let app = regularApps[pid],
                let name = app.localizedName
            else { continue }

            let bounds = windowBounds(from: window[kCGWindowBounds as String])
            let matchedDisplay: DisplaySnapshot?
            if let bounds {
                matchedDisplay = matchingDisplay(for: bounds, displays: displays)
            } else {
                matchedDisplay = nil
            }
            let title = window[kCGWindowName as String] as? String ?? ""

            visible.append(VisibleWindow(
                id: windowNumber,
                appName: name,
                bundleID: app.bundleIdentifier,
                title: title,
                displayID: matchedDisplay?.id,
                displayName: matchedDisplay?.name
            ))
        }

        return visible
    }

    private func displaySnapshots() -> [DisplaySnapshot] {
        NSScreen.screens.enumerated().map { index, screen in
            let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? UInt32(index)
            return DisplaySnapshot(
                id: id,
                name: screen.localizedName,
                isMain: screen == NSScreen.main,
                visibleWindowCount: 0
            )
        }
    }

    private func displaysWithWindowCounts(_ displays: [DisplaySnapshot], windows: [VisibleWindow]) -> [DisplaySnapshot] {
        displays.map { display in
            var copy = display
            copy.visibleWindowCount = windows.filter { $0.displayID == display.id }.count
            return copy
        }
    }

    private func matchingDisplay(for bounds: CGRect, displays: [DisplaySnapshot]) -> DisplaySnapshot? {
        guard !bounds.isNull, !bounds.isEmpty else { return nil }

        return displays.max { lhs, rhs in
            intersectionArea(bounds, displayID: lhs.id) < intersectionArea(bounds, displayID: rhs.id)
        }
    }

    private func intersectionArea(_ rect: CGRect, displayID: UInt32) -> CGFloat {
        let displayRect = CGDisplayBounds(displayID)
        let intersection = rect.intersection(displayRect)
        guard !intersection.isNull else { return 0 }
        return intersection.width * intersection.height
    }

    private func windowBounds(from value: Any?) -> CGRect? {
        guard let dictionary = value as? [String: Any] else { return nil }
        guard
            let x = numberValue(dictionary["X"]),
            let y = numberValue(dictionary["Y"]),
            let width = numberValue(dictionary["Width"]),
            let height = numberValue(dictionary["Height"])
        else { return nil }

        return CGRect(x: x, y: y, width: width, height: height)
    }

    private func numberValue(_ value: Any?) -> CGFloat? {
        if let number = value as? NSNumber {
            return CGFloat(truncating: number)
        }

        if let value = value as? CGFloat {
            return value
        }

        if let value = value as? Double {
            return CGFloat(value)
        }

        if let value = value as? Int {
            return CGFloat(value)
        }

        return nil
    }
}
