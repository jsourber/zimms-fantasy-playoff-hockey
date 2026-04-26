import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Skater headshot loader — prefers a bundled PNG (`headshot-<playerId>.png`)
/// and falls back to the network URL only if the bundled asset is missing.
struct SkaterHeadshotImage: View {
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
                    Image(systemName: "person.fill")
                        .resizable().scaledToFit()
                        .padding(8)
                        .foregroundStyle(.secondary.opacity(0.5))
                @unknown default:
                    EmptyView()
                }
            }
        }
    }

    #if canImport(UIKit)
    private func bundledImage(for pid: Int) -> UIImage? {
        guard let url = Bundle.main.url(forResource: "headshot-\(pid)", withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    #else
    private func bundledImage(for pid: Int) -> NSImage? {
        guard let url = Bundle.main.url(forResource: "headshot-\(pid)", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
    #endif
}
