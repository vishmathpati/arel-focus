import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: FocusStore
    @State private var excludedBundleID = ""
    @State private var excludedDomain = ""
    @State private var blockedDomain = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Header(title: "Settings", subtitle: "Local controls. Nothing leaves this Mac.")

                trackingCard
                loginCard
                chromeCard
                blockingCard
                exportCard
                privacyCard
            }
            .padding(Space.lg)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .navigationTitle("Settings")
    }

    // MARK: Tracking

    private var trackingCard: some View {
        SettingsSection(title: "Tracking", systemImage: "bolt.fill") {
            Toggle(isOn: Binding(
                get: { !store.settings.trackingPaused },
                set: { store.pauseTracking(!$0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.settings.trackingPaused ? "Paused" : "Tracking active")
                        .font(AppFont.body)
                    Text("Pause to stop recording any app, window, or Chrome tab activity.")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider().opacity(0.5)

            VStack(alignment: .leading, spacing: Space.xs) {
                HStack {
                    Text("Idle threshold")
                        .font(AppFont.body)
                    Spacer()
                    Text("\(Int(store.settings.idleThresholdSeconds)) seconds")
                        .font(AppFont.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Stepper("", value: Binding(
                    get: { Int(store.settings.idleThresholdSeconds) },
                    set: { store.setIdleThreshold($0) }
                ), in: 30...1800, step: 30)
                .labelsHidden()
                Text("How long without input before Arel Focus marks time as idle.")
                    .font(AppFont.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Login

    private var loginCard: some View {
        SettingsSection(title: "Launch at login", systemImage: "power") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Current status")
                        .font(AppFont.body)
                    Text(store.loginStatus)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: Space.sm) {
                    Button("Register") { store.setLoginEnabled(true) }
                    Button("Unregister") { store.setLoginEnabled(false) }
                }
            }
        }
    }

    // MARK: Chrome

    private var chromeCard: some View {
        SettingsSection(title: "Chrome bridge", systemImage: "globe") {
            HStack(alignment: .top, spacing: Space.md) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(store.chromeStatus)
                        .font(AppFont.body)
                    Text(bridgeStatusLabel)
                        .font(AppFont.caption)
                        .foregroundStyle(bridgeStatusColor)
                }
                Spacer()
                Button {
                    store.refreshDiagnostics()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }

            Divider().opacity(0.5)

            VStack(spacing: Space.xs) {
                DiagnosticRow(label: "Event log", value: store.diagnostics.chromeEventLogSizeLabel)
                DiagnosticRow(label: "Rotated logs", value: "\(store.diagnostics.rotatedChromeLogCount)")
                DiagnosticRow(label: "Latest event", value: dateLabel(store.diagnostics.latestChromeEventAt))
                DiagnosticRow(label: "15-day session days", value: "\(store.diagnostics.sessionDaysInLast15)")
                DiagnosticRow(label: "Needs sorting", value: "\(store.diagnostics.reviewCandidateCount) items")
                DiagnosticRow(label: "Blocked domains", value: blockedDomainsLabel)
            }
        }
    }

    private var bridgeStatusLabel: String {
        guard let path = store.diagnostics.nativeHostPath else {
            return "Native host manifest missing"
        }

        if !store.diagnostics.nativeHostExists {
            return "Native host binary missing at \(path)"
        }

        if !store.diagnostics.nativeHostMatchesCurrentBridge {
            return "Native host points outside this build"
        }

        return "Native host installed"
    }

    private var bridgeStatusColor: Color {
        store.diagnostics.nativeHostExists && store.diagnostics.nativeHostMatchesCurrentBridge ? Palette.secondary : .orange
    }

    private var blockedDomainsLabel: String {
        store.diagnostics.blockingEnabled
            ? "\(store.diagnostics.blockedDomainCount) active"
            : "\(store.diagnostics.blockedDomainCount) configured, off"
    }

    // MARK: Blocking

    private var blockingCard: some View {
        SettingsSection(title: "Blocking", systemImage: "hand.raised.fill") {
            Toggle(isOn: Binding(
                get: { store.blockConfig.blockingEnabled },
                set: store.setBlockingEnabled
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.blockConfig.blockingEnabled ? "Blocking active" : "Blocking off")
                        .font(AppFont.body)
                    Text("\(store.blockConfig.blockedDomains.count) websites configured")
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)

            Divider().opacity(0.5)

            domainGroup(
                title: "Blocked websites",
                placeholder: "Domain, for example instagram.com",
                text: $blockedDomain,
                items: store.blockConfig.blockedDomains,
                emptyText: "No blocked websites",
                onAdd: addBlockedDomain,
                onRemove: store.removeBlockedDomain
            )
        }
    }

    // MARK: Export

    private var exportCard: some View {
        SettingsSection(title: "Export today", systemImage: "square.and.arrow.up") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.lastExportMessage)
                        .font(AppFont.body)
                    Text("Writes JSON + CSV to ~/Library/Application Support/Arel Focus/Exports.")
                        .font(AppFont.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button {
                    if let result = store.exportToday() {
                        NSWorkspace.shared.activateFileViewerSelecting([result.jsonURL, result.csvURL])
                    }
                } label: {
                    Label("Export", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Privacy

    private var privacyCard: some View {
        SettingsSection(title: "Privacy", systemImage: "lock.shield") {
            Text("V1 stores metadata only. No screenshots, no keylogging, no screen recording.")
                .font(AppFont.caption)
                .foregroundStyle(.secondary)

            Divider().opacity(0.5)

            domainGroup(
                title: "Excluded apps",
                placeholder: "Bundle ID, for example com.apple.Notes",
                text: $excludedBundleID,
                items: store.settings.excludedBundleIDs,
                emptyText: "No excluded apps",
                onAdd: addExcludedBundleID,
                onRemove: store.removeExcludedBundleID
            )

            Divider().opacity(0.5)

            domainGroup(
                title: "Excluded websites from tracking",
                placeholder: "Domain, for example youtube.com",
                text: $excludedDomain,
                items: store.settings.excludedDomains,
                emptyText: "No excluded websites",
                onAdd: addExcludedDomain,
                onRemove: store.removeExcludedDomain
            )
        }
    }

    @ViewBuilder
    private func domainGroup(
        title: String,
        placeholder: String,
        text: Binding<String>,
        items: [String],
        emptyText: String,
        onAdd: @escaping () -> Void,
        onRemove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            Text(title.uppercased())
                .font(AppFont.section)
                .foregroundStyle(.secondary)
            HStack(spacing: Space.sm) {
                TextField(placeholder, text: text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(onAdd)
                Button("Add", action: onAdd)
                    .buttonStyle(.bordered)
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            if items.isEmpty {
                Text(emptyText)
                    .font(AppFont.caption)
                    .foregroundStyle(.tertiary)
            } else {
                FlowChips(items: items, onRemove: onRemove)
            }
        }
    }

    private func addExcludedBundleID() {
        store.addExcludedBundleID(excludedBundleID)
        excludedBundleID = ""
    }

    private func addExcludedDomain() {
        store.addExcludedDomain(excludedDomain)
        excludedDomain = ""
    }

    private func addBlockedDomain() {
        store.addBlockedDomain(blockedDomain)
        blockedDomain = ""
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let date else { return "None" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Settings section card

private struct SettingsSection<Content: View>: View {
    var title: String
    var systemImage: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            HStack(spacing: Space.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.primary)
                Text(title.uppercased())
                    .font(AppFont.section)
                    .foregroundStyle(.secondary)
            }
            Card(padding: Space.md) {
                VStack(alignment: .leading, spacing: Space.sm) {
                    content()
                }
            }
        }
    }
}

private struct DiagnosticRow: View {
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: Space.sm) {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(AppFont.caption.monospacedDigit())
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - Removable chips

private struct FlowChips: View {
    var items: [String]
    var onRemove: (String) -> Void

    var body: some View {
        FlexibleHStack(spacing: Space.xs) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 4) {
                    Text(item)
                        .font(AppFont.caption)
                        .lineLimit(1)
                    Button(role: .destructive) {
                        onRemove(item)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Space.sm)
                .padding(.vertical, 4)
                .background(Palette.muted.opacity(0.10), in: Capsule())
            }
        }
    }
}
