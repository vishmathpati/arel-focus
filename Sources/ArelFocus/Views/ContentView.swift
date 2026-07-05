import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case apps = "Apps"
    case websites = "Websites"
    case chromeTabs = "Tabs"
    case focusHours = "Focus Hours"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: "rectangle.grid.2x2"
        case .apps: "macwindow"
        case .websites: "globe"
        case .chromeTabs: "rectangle.on.rectangle"
        case .focusHours: "timer"
        case .settings: "gearshape"
        }
    }

    enum Group: String, CaseIterable { case overview = "Overview", analyze = "Analyze", system = "System" }

    var group: Group {
        switch self {
        case .dashboard: .overview
        case .apps, .websites, .chromeTabs, .focusHours: .analyze
        case .settings: .system
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: FocusStore
    @State private var selection: DashboardSection? = .dashboard

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            Group {
                switch selection ?? .dashboard {
                case .dashboard:
                    TodayView()
                case .apps:
                    AppsView()
                case .websites:
                    WebsitesView()
                case .chromeTabs:
                    ChromeTabsView()
                case .focusHours:
                    FocusHoursView()
                case .settings:
                    SettingsView()
                }
            }
            .environmentObject(store)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarHeader

            List(selection: $selection) {
                ForEach(DashboardSection.Group.allCases, id: \.self) { group in
                    Section {
                        ForEach(DashboardSection.allCases.filter { $0.group == group }) { section in
                            sidebarRow(section)
                                .tag(section)
                        }
                    } header: {
                        Text(group.rawValue)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .padding(.top, Space.xs)
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Divider().opacity(0.4)
            sidebarFooter
        }
        .navigationTitle("")
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
    }

    private var sidebarHeader: some View {
        HStack(spacing: Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(LinearGradient(colors: [Palette.primary, Palette.secondary], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text("Arel Focus")
                    .font(.system(size: 13, weight: .semibold))
                Text("Private focus log")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.md)
    }

    private func sidebarRow(_ section: DashboardSection) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: section.systemImage)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(selection == section ? Palette.primary : .secondary)
                .frame(width: 16)
            Text(section.rawValue)
                .font(.system(size: 13, weight: selection == section ? .semibold : .regular))
            Spacer()
            if section == .focusHours, store.focusHourState.state.isRunning {
                Text("Live")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.primary, in: Capsule())
            }
        }
    }

    private var sidebarFooter: some View {
        HStack(spacing: Space.sm) {
            Circle()
                .fill(store.settings.trackingPaused ? Palette.muted : Palette.secondary)
                .frame(width: 7, height: 7)
            Text(store.settings.trackingPaused ? "Paused" : "Tracking")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(Formatters.duration(store.todayActiveDuration))
                .font(.system(size: 11, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var store: FocusStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            currentActivityBlock

            if let focusHourStatusLabel = store.focusHourStatusLabel {
                focusHourBlock(focusHourStatusLabel)
            }

            statsBlock

            actions
        }
        .padding(Space.md)
        .frame(width: 304, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)
                .stroke(Palette.border.opacity(0.55), lineWidth: 0.5)
        )
        .onAppear {
            DashboardOpener.openAction = { openWindow(id: "dashboard") }
        }
    }

    private var currentActivityBlock: some View {
        HStack(alignment: .top, spacing: Space.sm) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(statusColor.opacity(0.14))
                    .frame(width: 34, height: 34)
                Image(systemName: store.settings.trackingPaused ? "pause.fill" : "timer")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(statusColor)
            }

            VStack(alignment: .leading, spacing: Space.xs) {
                Text(store.settings.trackingPaused ? "PAUSED" : "NOW")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                Text(store.currentActivity)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(store.settings.trackingPaused ? "Tracking is paused" : "Tracking locally")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
    }

    private var statsBlock: some View {
        VStack(spacing: 0) {
            statRow(label: "Active", value: Formatters.duration(store.todayActiveDuration), systemImage: "bolt.fill", tint: Palette.primary)
            Divider().opacity(0.45)
            statRow(label: "Open", value: Formatters.duration(store.todayBackgroundDuration), systemImage: "rectangle.3.group", tint: Palette.muted)
            Divider().opacity(0.45)
            statRow(label: "Idle", value: Formatters.duration(store.todayIdleDuration), systemImage: "moon", tint: Palette.muted)
            Divider().opacity(0.45)
            statRow(label: "Websites", value: Formatters.count(store.todayDistinctDomainCount), systemImage: "globe", tint: Palette.secondary)
        }
        .padding(.vertical, Space.xs)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Palette.border.opacity(0.45), lineWidth: 0.5)
        )
    }

    private func focusHourBlock(_ label: String) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: focusHourSystemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(focusHourTint)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
            Spacer(minLength: Space.sm)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .fill(focusHourTint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(focusHourTint.opacity(0.24), lineWidth: 0.5)
        )
    }

    private func statRow(label: String, value: String, systemImage: String, tint: Color) -> some View {
        HStack(spacing: Space.sm) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
            Text(label)
                .font(.system(size: 12))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 7)
    }

    private var actions: some View {
        VStack(spacing: Space.xs) {
            Button {
                DashboardOpener.openAction = { openWindow(id: "dashboard") }
                DashboardOpener.openDashboard()
            } label: {
                Label("Open Dashboard", systemImage: "rectangle.grid.2x2")
            }
            .buttonStyle(MenuActionButtonStyle(tint: Palette.primary))

            Button {
                store.pauseTracking(!store.settings.trackingPaused)
            } label: {
                Label(store.settings.trackingPaused ? "Resume tracking" : "Pause tracking",
                      systemImage: store.settings.trackingPaused ? "play.fill" : "pause.fill")
            }
            .buttonStyle(MenuActionButtonStyle(tint: store.settings.trackingPaused ? Palette.secondary : Palette.muted))

            if store.focusHourState.state.isRunning {
                Button(role: .destructive) {
                    store.rescueActiveFocusHour()
                } label: {
                    Label("Rescue Focus Hour", systemImage: "lifepreserver")
                }
                .buttonStyle(MenuActionButtonStyle(tint: .orange, isDestructive: true))
            }

            Button(role: .destructive) {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Arel Focus", systemImage: "power")
            }
            .buttonStyle(MenuActionButtonStyle(tint: Palette.muted, isDestructive: true))
        }
    }

    private var statusColor: Color {
        store.settings.trackingPaused ? Palette.muted : Palette.secondary
    }

    private var focusHourTint: Color {
        switch store.focusHourState.state {
        case .planning: Palette.primary
        case .working: .orange
        case .reflecting: Palette.secondary
        case .rescued, .cancelled: .red
        case .completed: Palette.secondary
        case .idle: Palette.muted
        }
    }

    private var focusHourSystemImage: String {
        switch store.focusHourState.state {
        case .planning: "doc.text.magnifyingglass"
        case .working: "shield.lefthalf.filled"
        case .reflecting: "text.bubble"
        case .rescued: "lifepreserver"
        case .completed: "checkmark.circle"
        case .cancelled: "xmark.circle"
        case .idle: "timer"
        }
    }

}

private struct MenuActionButtonStyle: ButtonStyle {
    var tint: Color
    var isDestructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .labelStyle(.titleAndIcon)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isDestructive ? Color.red : Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(configuration.isPressed ? tint.opacity(0.16) : tint.opacity(0.08))
            )
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                    .fill(tint.opacity(configuration.isPressed ? 0.75 : 0.45))
                    .frame(width: 3)
            }
    }
}
