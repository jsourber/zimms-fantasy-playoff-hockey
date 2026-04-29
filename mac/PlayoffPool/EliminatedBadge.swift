import SwiftUI

/// Small red pill that says "ELIMINATED" — used on team and skater cards.
struct EliminatedBadge: View {
    var compact: Bool = false

    var body: some View {
        Text(compact ? "OUT" : "ELIMINATED")
            .font(.system(size: 9).weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(Color.red.opacity(0.85)))
            .accessibilityLabel("Eliminated from playoffs")
    }
}
