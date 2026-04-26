import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Skater action-shot ("hero") loader — bundled JPEG first, network fallback.
struct SkaterHeroImage: View {
    let playerId: Int?
    let fallbackURL: URL?

    var body: some View {
        if let pid = playerId, let img = bundledImage(for: pid) {
            #if canImport(UIKit)
            Image(uiImage: img).resizable().scaledToFill()
            #else
            Image(nsImage: img).resizable().scaledToFill()
            #endif
        } else {
            AsyncImage(url: fallbackURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure, .empty:
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0.5), Color.accentColor.opacity(0.1)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                @unknown default:
                    EmptyView()
                }
            }
        }
    }

    #if canImport(UIKit)
    private func bundledImage(for pid: Int) -> UIImage? {
        guard let url = Bundle.main.url(forResource: "hero-\(pid)", withExtension: "jpg"),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    #else
    private func bundledImage(for pid: Int) -> NSImage? {
        guard let url = Bundle.main.url(forResource: "hero-\(pid)", withExtension: "jpg") else { return nil }
        return NSImage(contentsOf: url)
    }
    #endif
}
