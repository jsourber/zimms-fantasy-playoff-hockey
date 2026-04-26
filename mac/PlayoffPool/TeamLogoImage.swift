import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// A team-logo image that prefers a bundled PNG (`logo-<TRI>.png`) and falls back
/// to the network URL only if the bundled asset is missing. Bundling avoids ESPN's
/// rate-limiting / AsyncImage flakiness in lists.
struct TeamLogoImage: View {
    let tricode: String?
    let fallbackURL: URL?
    var size: CGFloat = 32

    var body: some View {
        if let tri = tricode, let img = bundledImage(for: tri) {
            #if canImport(UIKit)
            Image(uiImage: img).resizable().scaledToFit()
                .frame(width: size, height: size)
            #else
            Image(nsImage: img).resizable().scaledToFit()
                .frame(width: size, height: size)
            #endif
        } else {
            AsyncImage(url: fallbackURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure, .empty:
                    Image(systemName: "shield.fill")
                        .resizable().scaledToFit()
                        .foregroundStyle(.secondary.opacity(0.4))
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: size, height: size)
        }
    }

    #if canImport(UIKit)
    private func bundledImage(for tri: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: "logo-\(tri.uppercased())", withExtension: "png"),
              let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    #else
    private func bundledImage(for tri: String) -> NSImage? {
        guard let url = Bundle.main.url(forResource: "logo-\(tri.uppercased())", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
    #endif
}
