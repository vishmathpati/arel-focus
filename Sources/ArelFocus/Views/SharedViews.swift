import SwiftUI

// MARK: - Page chrome

struct Header: View {
    var title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title)
                .font(AppFont.title)
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SectionHeader: View {
    var title: String
    var trailing: String?

    init(_ title: String, trailing: String? = nil) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(title)
                .font(AppFont.bodyStrong)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(AppFont.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Containers

struct Card<Content: View>: View {
    var padding: CGFloat = Space.sm
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
        }
        .padding(padding)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Palette.border.opacity(0.5), lineWidth: 0.5)
        )
        .arelShadow(Elevation.card)
    }
}

struct DividedList<Item: Identifiable, Row: View>: View {
    var items: [Item]
    @ViewBuilder var row: (Item) -> Row

    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    row(item)
                    if index < items.count - 1 {
                        Divider().opacity(0.22)
                    }
                }
            }
        }
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    var systemImage: String
    var title: String
    var message: String?

    var body: some View {
        VStack(spacing: Space.md) {
            ZStack {
                Circle()
                    .fill(Palette.primary.opacity(0.08))
                    .frame(width: 64, height: 64)
                Image(systemName: systemImage)
                    .font(.system(size: 26, weight: .regular))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Palette.primary)
            }
            Text(title)
                .font(AppFont.bodyStrong)
                .foregroundStyle(.primary)
            if let message {
                Text(message)
                    .font(AppFont.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
    }
}

// MARK: - Metric tile

struct MetricTile: View {
    var title: String
    var value: String
    var systemImage: String
    var emphasis: Emphasis = .regular

    enum Emphasis { case regular, accent }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack(spacing: Space.xs) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(emphasis == .accent ? Palette.primary : .secondary)
                Text(title)
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(emphasis == .accent ? Palette.primary : .secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(emphasis == .accent ? AppFont.metric : .system(size: 19, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.md)
        .background(background)
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(emphasis == .accent ? Palette.primary.opacity(0.35) : Palette.border.opacity(0.45), lineWidth: emphasis == .accent ? 1 : 0.5)
        )
        .arelShadow(Elevation.card)
    }

    @ViewBuilder
    private var background: some View {
        if emphasis == .accent {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Color(nsColor: .controlBackgroundColor))
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Gradients.accentMetric)
            }
        } else {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color(nsColor: .controlBackgroundColor))
        }
    }
}

// MARK: - Project chip + color bar

struct ProjectChip: View {
    var name: String
    var colorHex: String?

    var body: some View {
        let color = colorHex.map { Color(hex: $0) } ?? Palette.muted
        HStack(spacing: Space.xs) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(name)
                .font(AppFont.caption.weight(.medium))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, Space.sm)
        .padding(.vertical, 3)
        .background(color.opacity(0.12), in: Capsule())
        .overlay(
            Capsule()
                .stroke(color.opacity(0.18), lineWidth: 0.5)
        )
    }
}

struct ProjectColorBar: View {
    var colorHex: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(colorHex.map { Color(hex: $0) } ?? Color.clear)
            .frame(width: 3)
    }
}

// MARK: - Quiet metadata

struct ContextGlyphs: View {
    var windowCount: Int = 0
    var tabCount: Int = 0
    var displayNames: [String] = []
    var technicalIdentifier: String?

    var body: some View {
        HStack(spacing: Space.xs) {
            if tabCount > 0 {
                glyph(
                    systemImage: tabCount == 1 ? "rectangle.on.rectangle" : "square.stack",
                    help: tabCount == 1 ? "1 tab" : "\(tabCount) tabs"
                )
            }

            if windowCount > 0 {
                glyph(
                    systemImage: windowCount == 1 ? "macwindow" : "rectangle.stack",
                    help: windowCount == 1 ? "1 open window" : "\(windowCount) open windows"
                )
            }

            if !displayNames.isEmpty {
                glyph(
                    systemImage: displayNames.count == 1 ? "display" : "display.2",
                    help: displayHelp
                )
            }

            if let technicalIdentifier, !technicalIdentifier.isEmpty {
                glyph(systemImage: "info.circle", help: technicalIdentifier)
            }
        }
    }

    private var displayHelp: String {
        displayNames.count == 1
            ? "Shown on \(displayNames[0])"
            : "Shown on \(displayNames.joined(separator: ", "))"
    }

    private func glyph(systemImage: String, help: String) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
            .frame(width: 16, height: 16)
            .help(help)
    }
}

struct DurationSplitText: View {
    var focused: TimeInterval
    var open: TimeInterval

    var body: some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private var text: String {
        switch (focused > 0, open > 0) {
        case (true, true):
            return "\(Formatters.duration(focused)) focused - \(Formatters.duration(open)) open"
        case (true, false):
            return "\(Formatters.duration(focused)) focused"
        case (false, true):
            return "\(Formatters.duration(open)) open"
        case (false, false):
            return "Less than a minute"
        }
    }
}

// MARK: - Wrapping chip layout

struct FlexibleHStack<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(macOS 13.0, *) {
            WrapLayout(spacing: spacing) { content() }
        } else {
            HStack { content() }
        }
    }
}

@available(macOS 13.0, *)
private struct WrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var rows: [CGFloat] = [0]
        var rowHeights: [CGFloat] = [0]
        var x: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                rows.append(0)
                rowHeights.append(0)
                x = 0
            }
            rows[rows.count - 1] = max(rows[rows.count - 1], x + size.width)
            rowHeights[rowHeights.count - 1] = max(rowHeights[rowHeights.count - 1], size.height)
            x += size.width + spacing
        }

        let width = rows.max() ?? 0
        let height = rowHeights.reduce(0, +) + CGFloat(max(0, rowHeights.count - 1)) * spacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let maxWidth = bounds.width
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.minX + maxWidth, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Ranked duration row (used by Apps/Websites)

struct RankedDurationRow<Leading: View>: View {
    var name: String
    var duration: TimeInterval
    var fractionOfMax: Double
    var accent: Color
    var isLeader: Bool = false
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.md) {
                leading()
                    .frame(width: 22, height: 22)
                Text(name)
                    .font(isLeader ? AppFont.bodyStrong : AppFont.body)
                    .lineLimit(1)
                Spacer(minLength: Space.sm)
                Text(Formatters.duration(duration))
                    .font(AppFont.caption.weight(isLeader ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(isLeader ? .primary : .secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Palette.muted.opacity(0.10))
                        .frame(height: 4)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(isLeader ? AnyShapeStyle(Gradients.projectBar(accent)) : AnyShapeStyle(accent.opacity(0.55)))
                        .frame(width: max(3, geo.size.width * fractionOfMax), height: 4)
                }
            }
            .frame(height: 4)
            .padding(.leading, 34)
        }
        .padding(.horizontal, Space.md)
        .padding(.vertical, Space.sm)
    }
}
