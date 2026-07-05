import SwiftUI

// MARK: - Tabs

struct ChromeTabsView: View {
    @EnvironmentObject private var store: FocusStore

    private var openNow: [AttentionTabInsight] { store.openNowTabInsights() }
    private var tabs: [AttentionTabInsight] { store.tabInsights(limit: 40) }
    private var lowFocusTabs: [AttentionTabInsight] {
        tabs
            .filter { $0.open > 0 && $0.open > $0.focused * 3 }
            .prefix(12)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Header(title: "Tabs", subtitle: "Chrome context: what is open now, what pulled focus, and what is hanging around.")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Space.sm)], spacing: Space.sm) {
                    MetricTile(title: "Open now", value: Formatters.count(openNow.count), systemImage: "rectangle.on.rectangle", emphasis: .accent)
                    MetricTile(title: "Focused pages", value: Formatters.count(tabs.filter { $0.focused > 0 }.count), systemImage: "bolt.fill")
                    MetricTile(title: "Low-focus tabs", value: Formatters.count(lowFocusTabs.count), systemImage: "exclamationmark.circle")
                }

                if !openNow.isEmpty {
                    tabGrid(title: "Open now", trailing: "\(openNow.count) tabs", tabs: openNow)
                }

                if !lowFocusTabs.isEmpty {
                    tabGrid(title: "Open a long time, barely focused", trailing: "cleanup candidates", tabs: lowFocusTabs)
                }

                tabGrid(title: "Recently focused pages", trailing: "\(tabs.count) pages", tabs: tabs)
            }
            .padding(Space.lg)
            .frame(maxWidth: 1500, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Tabs")
    }

    private func tabGrid(title: String, trailing: String? = nil, tabs: [AttentionTabInsight]) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title, trailing: trailing)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: Space.md)], spacing: Space.md) {
                ForEach(tabs) { tab in
                    TabContextCard(tab: tab)
                }
            }
        }
    }
}

private struct TabContextCard: View {
    var tab: AttentionTabInsight

    var body: some View {
        Card(padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top, spacing: Space.md) {
                    FaviconView(favIconDataURL: tab.favIconDataURL, favIconURL: tab.favIconURL)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.sm) {
                            Text(tab.title)
                                .font(AppFont.bodyStrong)
                                .lineLimit(2)
                            if tab.isActiveNow {
                                StateBadge(label: "Active", tint: Palette.secondary)
                            } else if tab.isOpenNow {
                                StateBadge(label: "Open", tint: Palette.primary)
                            }
                        }
                        Text(tab.displayURL ?? tab.domain)
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()
                }

                HStack(spacing: Space.sm) {
                    MetricPill(label: "Focused", value: Formatters.duration(tab.focused), tint: Palette.primary)
                    MetricPill(label: "Open", value: Formatters.duration(tab.open), tint: Palette.muted)
                }

                HStack {
                    Text(tab.domain)
                        .font(AppFont.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                    Spacer()
                    if let profileLabel = tab.profileLabel {
                        Image(systemName: "person.crop.circle")
                            .foregroundStyle(.tertiary)
                            .help(profileLabel)
                    }
                    if let lastSeen = tab.lastSeen {
                        Text("Last \(Formatters.shortTime(lastSeen))")
                            .font(AppFont.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

private struct StateBadge: View {
    var label: String
    var tint: Color

    var body: some View {
        Text(label)
            .font(AppFont.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

// MARK: - Focus Hours

struct FocusHoursView: View {
    @EnvironmentObject private var store: FocusStore

    private var focusHours: [FocusHourInsight] { store.focusHourInsights }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Header(title: "Focus Hours", subtitle: "Planned sessions compared with the apps and websites actually used.")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Space.sm)], spacing: Space.sm) {
                    MetricTile(title: "Sessions", value: Formatters.count(focusHours.count), systemImage: "timer", emphasis: .accent)
                    MetricTile(title: "Completed", value: Formatters.count(focusHours.filter { $0.state == .completed }.count), systemImage: "checkmark.circle")
                    MetricTile(title: "Rescued", value: Formatters.count(focusHours.filter { $0.rescued || $0.state == .rescued }.count), systemImage: "exclamationmark.triangle")
                    MetricTile(title: "Blocked attempts", value: Formatters.count(focusHours.flatMap(\.blockedAttempts).count), systemImage: "hand.raised")
                }

                if focusHours.isEmpty {
                    Card {
                        EmptyStateView(
                            systemImage: "timer",
                            title: "No Focus Hour history yet",
                            message: "Start one from Arel OS and the result will show apps, websites, rescue state, and blocked attempts here."
                        )
                    }
                } else {
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader("Session history", trailing: "\(focusHours.count)")
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: Space.md)], spacing: Space.md) {
                            ForEach(focusHours) { focusHour in
                                FocusHourResultCard(focusHour: focusHour)
                            }
                        }
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: 1500, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Focus Hours")
    }
}

private struct FocusHourResultCard: View {
    var focusHour: FocusHourInsight

    var body: some View {
        Card(padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top, spacing: Space.md) {
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(focusHour.projectName)
                            .font(AppFont.bodyStrong)
                            .lineLimit(1)
                        Text(subtitle)
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()

                    Text(focusHour.state.label)
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }

                HStack(spacing: Space.sm) {
                    MetricPill(label: "Actual", value: "\(focusHour.actualMinutes)m", tint: Palette.primary)
                    if focusHour.plannedMinutes > 0 {
                        MetricPill(label: "Planned", value: "\(focusHour.plannedMinutes)m", tint: Palette.muted)
                    }
                    MetricPill(label: "Sites", value: Formatters.count(focusHour.websites.count), tint: Palette.secondary)
                    MetricPill(label: "Apps", value: Formatters.count(focusHour.apps.count), tint: Palette.secondary)
                }

                if !focusHour.websites.isEmpty {
                    LabelList(title: "Websites", values: focusHour.websites.prefix(5).map { $0 })
                }

                if !focusHour.apps.isEmpty {
                    LabelList(title: "Apps", values: focusHour.apps.prefix(5).map { $0 })
                }

                if !focusHour.blockedAttempts.isEmpty {
                    LabelList(title: "Blocked", values: focusHour.blockedAttempts.prefix(5).map { $0 })
                }
            }
        }
    }

    private var subtitle: String {
        var parts = [focusHour.profileName, Formatters.shortTime(focusHour.startedAt)]
        if let taskName = focusHour.taskName {
            parts.insert(taskName, at: 0)
        }
        return parts.joined(separator: " - ")
    }

    private var icon: String {
        switch focusHour.state {
        case .working: "bolt.fill"
        case .rescued: "exclamationmark.triangle.fill"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        default: "timer"
        }
    }

    private var tint: Color {
        switch focusHour.state {
        case .working, .completed: Palette.secondary
        case .rescued, .cancelled: .orange
        default: Palette.primary
        }
    }
}

private struct LabelList: View {
    var title: String
    var values: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .font(AppFont.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            FlexibleHStack(spacing: Space.xs) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(AppFont.caption)
                        .lineLimit(1)
                        .padding(.horizontal, Space.sm)
                        .padding(.vertical, 3)
                        .background(Palette.muted.opacity(0.10), in: Capsule())
                }
            }
        }
    }
}
