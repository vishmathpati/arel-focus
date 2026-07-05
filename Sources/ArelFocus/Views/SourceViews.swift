import SwiftUI

// MARK: - Apps

struct AppsView: View {
    @EnvironmentObject private var store: FocusStore

    private var apps: [AttentionAppInsight] { store.appInsights() }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Header(title: "Apps", subtitle: "Mac apps by real focus and open background presence.")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Space.sm)], spacing: Space.sm) {
                    MetricTile(title: "Focused in apps", value: Formatters.duration(store.todayActiveAppDuration), systemImage: "bolt.fill", emphasis: .accent)
                    MetricTile(title: "Open nearby", value: Formatters.duration(store.todayOpenAppDuration), systemImage: "rectangle.3.group")
                    MetricTile(title: "Apps seen", value: Formatters.count(apps.count), systemImage: "square.grid.2x2")
                }

                insightGrid(title: "Most used today", trailing: "\(apps.count) apps") {
                    ForEach(apps) { app in
                        AppUsageCard(app: app)
                    }
                }
            }
            .padding(Space.lg)
            .frame(maxWidth: 1500, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Apps")
    }

    private func insightGrid<Content: View>(
        title: String,
        trailing: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title, trailing: trailing)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: Space.md)], spacing: Space.md) {
                content()
            }
        }
    }
}

private struct AppUsageCard: View {
    var app: AttentionAppInsight

    var body: some View {
        Card(padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top, spacing: Space.md) {
                    icon
                        .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(app.name)
                            .font(AppFont.bodyStrong)
                            .lineLimit(1)
                        DurationSplitText(focused: app.focused, open: app.open)
                    }

                    Spacer()
                }

                HStack(spacing: Space.sm) {
                    MetricPill(label: "Focused", value: Formatters.duration(app.focused), tint: Palette.primary)
                    MetricPill(label: "Open", value: Formatters.duration(app.open), tint: Palette.muted)
                }

                HStack(spacing: Space.sm) {
                    ContextGlyphs(windowCount: app.windowCount, displayNames: app.displayNames)
                    Spacer()
                    if let lastSeen = app.lastSeen {
                        Text("Last \(Formatters.shortTime(lastSeen))")
                            .font(AppFont.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var icon: some View {
        if let bundleID = app.bundleID {
            AppIconView(bundleID: bundleID)
        } else {
            Image(systemName: "app")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Websites

struct WebsitesView: View {
    @EnvironmentObject private var store: FocusStore

    private var sites: [AttentionWebsiteInsight] { store.websiteInsights() }
    private var pressure: [AttentionWebsiteInsight] { store.openPressureWebsiteInsights(limit: 8) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                Header(title: "Websites", subtitle: "Web attention by site. Domains are the main review unit; tabs explain the detail.")

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: Space.sm)], spacing: Space.sm) {
                    MetricTile(title: "Focused on web", value: Formatters.duration(store.todayActiveChromeDuration), systemImage: "bolt.fill", emphasis: .accent)
                    MetricTile(title: "Open tab pressure", value: Formatters.duration(store.todayOpenChromeDuration), systemImage: "rectangle.on.rectangle")
                    MetricTile(title: "Sites", value: Formatters.count(sites.count), systemImage: "globe")
                }

                if !pressure.isEmpty {
                    websiteGrid(title: "Open pressure", trailing: "open longer than focused", sites: pressure)
                }

                websiteGrid(title: "Focused websites", trailing: "\(sites.count) sites", sites: sites)
            }
            .padding(Space.lg)
            .frame(maxWidth: 1500, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Websites")
    }

    private func websiteGrid(title: String, trailing: String? = nil, sites: [AttentionWebsiteInsight]) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            SectionHeader(title, trailing: trailing)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: Space.md)], spacing: Space.md) {
                ForEach(sites) { site in
                    WebsiteUsageCard(site: site)
                }
            }
        }
    }
}

private struct WebsiteUsageCard: View {
    var site: AttentionWebsiteInsight

    var body: some View {
        Card(padding: Space.md) {
            VStack(alignment: .leading, spacing: Space.md) {
                HStack(alignment: .top, spacing: Space.md) {
                    FaviconView(favIconDataURL: site.favIconDataURL, favIconURL: site.favIconURL)
                        .frame(width: 38, height: 38)

                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.sm) {
                            Text(site.domain)
                                .font(AppFont.bodyStrong)
                                .lineLimit(1)
                            if site.focusHourTouches > 0 {
                                Image(systemName: "timer")
                                    .foregroundStyle(Palette.secondary)
                                    .help("Used during \(site.focusHourTouches) Focus Hour\(site.focusHourTouches == 1 ? "" : "s")")
                            }
                        }
                        Text(site.title ?? site.displayURL ?? "Website")
                            .font(AppFont.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Spacer()
                }

                HStack(spacing: Space.sm) {
                    MetricPill(label: "Focused", value: Formatters.duration(site.focused), tint: Palette.primary)
                    MetricPill(label: "Open", value: Formatters.duration(site.open), tint: Palette.muted)
                    MetricPill(label: "Tabs", value: Formatters.count(site.tabCount), tint: Palette.secondary)
                }

                HStack {
                    FocusRatioBar(ratio: site.focusRatio)
                    Spacer()
                    if let lastSeen = site.lastSeen {
                        Text("Last \(Formatters.shortTime(lastSeen))")
                            .font(AppFont.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

// MARK: - Shared source widgets

struct MetricPill: View {
    var label: String
    var value: String
    var tint: Color

    var body: some View {
        HStack(spacing: Space.xs) {
            Circle()
                .fill(tint)
                .frame(width: 5, height: 5)
            Text(label)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .font(AppFont.caption)
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 4)
        .background(tint.opacity(0.10), in: Capsule())
    }
}

struct FocusRatioBar: View {
    var ratio: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.muted.opacity(0.12))
                RoundedRectangle(cornerRadius: 2)
                    .fill(Palette.secondary.opacity(0.7))
                    .frame(width: max(3, proxy.size.width * min(max(ratio, 0), 1)))
            }
        }
        .frame(width: 96, height: 4)
        .help("\(Int((ratio * 100).rounded()))% of this site's context was focused")
    }
}
