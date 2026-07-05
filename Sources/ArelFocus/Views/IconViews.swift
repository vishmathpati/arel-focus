import AppKit
import SwiftUI

struct ActivityIcon: View {
    var session: ActivitySession

    var body: some View {
        if (session.kind == .chromeTab || session.kind == .openChromeTab),
           session.favIconDataURL != nil || session.favIconURL != nil {
            FaviconView(favIconDataURL: session.favIconDataURL, favIconURL: session.favIconURL)
        } else if let bundleID = session.bundleID {
            AppIconView(bundleID: bundleID)
        } else {
            fallback
        }
    }

    private var fallback: some View {
        Image(systemName: fallbackSymbol)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var fallbackSymbol: String {
        switch session.kind {
        case .activeApp: "app"
        case .backgroundApp: "rectangle.3.group"
        case .chromeTab: "globe"
        case .openChromeTab: "rectangle.on.rectangle"
        case .idle: "moon"
        }
    }
}

struct SummaryIcon: View {
    var summary: DurationSummary

    var body: some View {
        if summary.favIconDataURL != nil || summary.favIconURL != nil {
            FaviconView(favIconDataURL: summary.favIconDataURL, favIconURL: summary.favIconURL)
        } else if let bundleID = summary.bundleID {
            AppIconView(bundleID: bundleID)
        } else {
            Image(systemName: "circle.grid.2x2")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct AppIconView: View {
    var bundleID: String

    var body: some View {
        if let nsImage = AppIconProvider.icon(for: bundleID) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: "app")
                .foregroundStyle(.secondary)
        }
    }
}

struct FaviconView: View {
    var favIconDataURL: String?
    var favIconURL: String?

    var body: some View {
        if let nsImage = FaviconImageProvider.image(fromDataURL: favIconDataURL) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 4))
        } else if let imageURL = usableURL {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case .empty:
                    fallback
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                case .failure:
                    fallback
                @unknown default:
                    fallback
                }
            }
        } else {
            fallback
        }
    }

    private var usableURL: URL? {
        guard let favIconURL,
              let url = URL(string: favIconURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return nil }

        return url
    }

    private var fallback: some View {
        Image(systemName: "globe")
            .foregroundStyle(.secondary)
    }
}

enum FaviconImageProvider {
    static func image(fromDataURL dataURL: String?) -> NSImage? {
        guard let dataURL,
              let commaIndex = dataURL.firstIndex(of: ",")
        else { return nil }

        let metadata = dataURL[..<commaIndex].lowercased()
        guard metadata.hasPrefix("data:image/"), metadata.contains(";base64") else { return nil }

        let payload = dataURL[dataURL.index(after: commaIndex)...]
        guard let data = Data(base64Encoded: String(payload), options: [.ignoreUnknownCharacters]) else {
            return nil
        }

        let image = NSImage(data: data)
        image?.size = NSSize(width: 32, height: 32)
        return image
    }
}

enum AppIconProvider {
    static func icon(for bundleID: String) -> NSImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }

        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 32, height: 32)
        return icon
    }
}
