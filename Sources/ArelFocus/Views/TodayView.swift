import SwiftUI

struct TodayView: View {
    @EnvironmentObject private var store: FocusStore

    private var topApps: [AttentionAppInsight] { store.appInsights(limit: 5) }
    private var topWebsites: [AttentionWebsiteInsight] { store.websiteInsights(limit: 5) }
    private var focusHours: [FocusHourInsight] { store.todayFocusHourInsights }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Header(title: "Dashboard", subtitle: "Today at a glance: focus, apps, websites, and Focus Hours.")

                overviewGrid
                focusHourStrip

                HStack(alignment: .top, spacing: Space.lg) {
                    insightColumn(title: "Top apps", trailing: "\(topApps.count)") {
                        ForEach(topApps) { app in
                            AppInsightCard(app: app)
                        }
                    }

                    insightColumn(title: "Top websites", trailing: "\(topWebsites.count)") {
                        ForEach(topWebsites) { site in
                            WebsiteInsightCard(site: site)
                        }
                    }
                }

                if !store.openPressureWebsiteInsights(limit: 4).isEmpty {
                    insightColumn(title: "Open tab pressure", trailing: "open longer than focused") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: Space.md)], spacing: Space.md) {
                            ForEach(store.openPressureWebsiteInsights(limit: 4)) { site in
                                PressureCard(site: site)
                            }
                        }
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: 1500, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Dashboard")
    }

    private var overviewGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Space.sm)], spacing: Space.sm) {
            MetricTile(title: "Screen on", value: Formatters.duration(store.todayScreenOnDuration), systemImage: "display", emphasis: .accent)
            MetricTile(title: "Focused", value: Formatters.duration(store.todayActiveDuration), systemImage: "bolt.fill")
            MetricTile(title: "Open nearby", value: Formatters.duration(store.todayBackgroundDuration), systemImage: "rectangle.3.group")
            MetricTile(title: "Away", value: Formatters.duration(store.todayIdleDuration), systemImage: "moon")
            MetricTile(title: "Apps", value: Formatters.count(store.todayDistinctAppCount), systemImage: "macwindow")
            MetricTile(title: "Websites", value: Formatters.count(store.todayDistinctDomainCount), systemImage: "globe")
        }
    }

    @ViewBuilder
    private var focusHourStrip: some View {
        if focusHours.isEmpty, store.focusHourState.state == .idle {
            Card(padding: Space.md) {
                HStack(spacing: Space.md) {
                    Image(systemName: "timer")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Palette.primary)
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("No Focus Hour today")
                            .font(AppFont.bodyStrong)
                        Text("Focus Hour summaries will show planned time, actual apps, websites, and blocked attempts.")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        } else {
            insightColumn(title: "Focus Hours today", trailing: "\(focusHours.count)") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: Space.md)], spacing: Space.md) {
                    ForEach(focusHours.prefix(4)) { focusHour in
                        FocusHourMiniCard(focusHour: focusHour)
                    }
                }
            }
        }
    }

    private func insightColumn<Content: View>(
        title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title, trailing: trailing)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

struct AppInsightCard: View {
    var app: AttentionAppInsight

    var body: some View {
        Card(padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .top, spacing: Space.md) {
                    appIcon
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(app.name)
                            .font(AppFont.bodyStrong)
                            .lineLimit(1)
                        DurationSplitText(focused: app.focused, open: app.open)
                    }

                    Spacer(minLength: Space.sm)
                }

                HStack(spacing: Space.sm) {
                    MetricPill(label: "Focused", value: Formatters.duration(app.focused), tint: Palette.primary)
                    if app.open > 0 {
                        MetricPill(label: "Open", value: Formatters.duration(app.open), tint: Palette.muted)
                    }
                    Spacer()
                    ContextGlyphs(windowCount: app.windowCount, displayNames: app.displayNames)
                }
            }
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let bundleID = app.bundleID {
            AppIconView(bundleID: bundleID)
        } else {
            Image(systemName: "app")
                .foregroundStyle(.secondary)
        }
    }
}

struct WebsiteInsightCard: View {
    var site: AttentionWebsiteInsight

    var body: some View {
        Card(padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(alignment: .top, spacing: Space.md) {
                    FaviconView(favIconDataURL: site.favIconDataURL, favIconURL: site.favIconURL)
                        .frame(width: 34, height: 34)

                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.sm) {
                            Text(site.domain)
                                .font(AppFont.bodyStrong)
                                .lineLimit(1)
                            if site.focusHourTouches > 0 {
                                Label("Focus Hour", systemImage: "timer")
                                    .labelStyle(.titleAndIcon)
                                    .font(AppFont.caption)
                                    .foregroundStyle(Palette.secondary)
                                    .padding(.horizontal, Space.sm)
                                    .padding(.vertical, 2)
                                    .background(Palette.secondary.opacity(0.12), in: Capsule())
                            }
                        }

                        Text(site.title ?? site.displayURL ?? "Website")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: Space.sm)
                }

                HStack(spacing: Space.sm) {
                    MetricPill(label: "Focused", value: Formatters.duration(site.focused), tint: Palette.primary)
                    if site.open > 0 {
                        MetricPill(label: "Open", value: Formatters.duration(site.open), tint: Palette.muted)
                    }
                    if site.tabCount > 0 {
                        MetricPill(label: "Tabs", value: Formatters.count(site.tabCount), tint: Palette.secondary)
                    }
                }
            }
        }
    }
}

private struct PressureCard: View {
    var site: AttentionWebsiteInsight

    var body: some View {
        Card(padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    FaviconView(favIconDataURL: site.favIconDataURL, favIconURL: site.favIconURL)
                        .frame(width: 24, height: 24)
                    Text(site.domain)
                        .font(AppFont.bodyStrong)
                        .lineLimit(1)
                    Spacer()
                    Text(Formatters.duration(site.open))
                        .font(AppFont.caption.weight(.semibold).monospacedDigit())
                }
                Text("Open nearby with \(Formatters.duration(site.focused)) focused")
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct FocusHourMiniCard: View {
    var focusHour: FocusHourInsight

    var body: some View {
        Card(padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.sm) {
                HStack(spacing: Space.sm) {
                    Image(systemName: icon)
                        .foregroundStyle(tint)
                    Text(focusHour.projectName)
                        .font(AppFont.bodyStrong)
                        .lineLimit(1)
                    Spacer()
                    Text(focusHour.state.label)
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(tint)
                }

                if let taskName = focusHour.taskName {
                    Text(taskName)
                        .font(AppFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: Space.md) {
                    Label("\(focusHour.actualMinutes)m", systemImage: "clock")
                    Label("\(focusHour.websites.count) sites", systemImage: "globe")
                    Label("\(focusHour.apps.count) apps", systemImage: "macwindow")
                }
                .font(AppFont.caption)
                .foregroundStyle(.secondary)
            }
        }
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
