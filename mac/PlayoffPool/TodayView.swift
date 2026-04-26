#if os(iOS)
import SwiftUI

struct TodayView: View {
    let slate: TodaySlate?

    var body: some View {
        Group {
            if let slate, !slate.games.isEmpty {
                List {
                    let liveGames = slate.games.filter { $0.isLive }
                    let upcoming  = slate.games.filter { $0.isScheduled }
                    let finals    = slate.games.filter { $0.isFinal }

                    if !liveGames.isEmpty {
                        Section(header: sectionHeader("Live", color: .red, pulsing: true)) {
                            ForEach(liveGames) { GameCard(game: $0) }
                        }
                    }
                    if !upcoming.isEmpty {
                        Section(header: sectionHeader("Upcoming", color: .secondary)) {
                            ForEach(upcoming) { GameCard(game: $0) }
                        }
                    }
                    if !finals.isEmpty {
                        Section(header: sectionHeader("Final", color: .secondary)) {
                            ForEach(finals) { GameCard(game: $0) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            } else {
                ContentUnavailableView {
                    Label("No playoff games today", systemImage: "calendar.badge.exclamationmark")
                } description: {
                    Text("Check back tomorrow.")
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, color: Color, pulsing: Bool = false) -> some View {
        HStack(spacing: 6) {
            if pulsing {
                Circle().fill(color).frame(width: 8, height: 8)
                    .modifier(PulseModifier())
            }
            Text(title)
                .font(.caption.weight(.bold))
                .foregroundStyle(color)
        }
    }
}

private struct PulseModifier: ViewModifier {
    @State private var on = false
    func body(content: Content) -> some View {
        content
            .opacity(on ? 0.35 : 1.0)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

private struct GameCard: View {
    let game: TodayGame

    var body: some View {
        VStack(spacing: 8) {
            if let title = game.seriesTitle, !title.isEmpty {
                HStack {
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    statusPill
                }
            } else {
                HStack { Spacer(); statusPill }
            }

            HStack(spacing: 12) {
                teamCol(game.away)
                Spacer(minLength: 8)
                centerCol
                Spacer(minLength: 8)
                teamCol(game.home, alignTrailing: true)
            }

            if let s = game.seriesStatus, !s.isEmpty {
                Text(s)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func teamCol(_ t: TodayTeam, alignTrailing: Bool = false) -> some View {
        VStack(alignment: alignTrailing ? .trailing : .leading, spacing: 4) {
            AsyncImage(url: t.logoUrl) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFit()
                case .failure, .empty:
                    Image(systemName: "shield.fill").resizable().scaledToFit()
                        .foregroundStyle(.secondary.opacity(0.4))
                @unknown default: EmptyView()
                }
            }
            .frame(width: 44, height: 44)

            Text(t.tricode ?? "?")
                .font(.subheadline.weight(.bold))
            if let r = t.record {
                Text(r)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity, alignment: alignTrailing ? .trailing : .leading)
    }

    @ViewBuilder
    private var centerCol: some View {
        if game.isFuture {
            VStack(spacing: 2) {
                Text(formattedStartTime)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("Tonight")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack(alignment: .center, spacing: 6) {
                Text("\(game.away.score ?? 0)")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor(for: game.away.score, vs: game.home.score))
                Text("–").font(.title3).foregroundStyle(.secondary)
                Text("\(game.home.score ?? 0)")
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(scoreColor(for: game.home.score, vs: game.away.score))
            }
        }
    }

    private func scoreColor(for me: Int?, vs them: Int?) -> Color {
        guard let me, let them else { return .primary }
        return me > them ? .primary : (me < them ? .secondary : .primary)
    }

    @ViewBuilder
    private var statusPill: some View {
        let (label, color) = statusLabelAndColor
        Text(label)
            .font(.caption2.weight(.bold))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private var statusLabelAndColor: (String, Color) {
        if game.isLive {
            // e.g. "P2 12:34" or "INT 2"
            if game.clock?.inIntermission == true, let n = game.period?.number {
                return ("INT \(n)", .orange)
            }
            let pType = game.period?.type ?? "REG"
            let pNum = game.period?.number ?? 0
            let prefix = pType == "REG" ? "P\(pNum)" : (pType == "OT" ? "OT\(pNum > 3 ? "\(pNum - 3)" : "")" : pType)
            let tr = (game.clock?.timeRemaining).flatMap { $0.isEmpty ? nil : $0 }
            let label = tr.map { "\(prefix) \($0)" } ?? prefix
            return (label, .red)
        } else if game.isFinal {
            let pType = game.period?.type ?? "REG"
            return (pType == "REG" ? "FINAL" : "FINAL/\(pType)", .secondary)
        } else if game.isFuture {
            return (formattedStartTime, .blue)
        } else {
            return (game.state ?? "—", .secondary)
        }
    }

    private var formattedStartTime: String {
        guard let s = game.startUtc, let d = ISO8601DateFormatter().date(from: s) else {
            return "—"
        }
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f.string(from: d)
    }
}

extension TodayGame {
    var isLive: Bool {
        switch (state ?? "").uppercased() {
        case "LIVE", "CRIT": return true
        default: return false
        }
    }
    var isFinal: Bool {
        switch (state ?? "").uppercased() {
        case "OFF", "FINAL", "OVER": return true
        default: return false
        }
    }
    var isFuture: Bool {
        switch (state ?? "").uppercased() {
        case "FUT", "PRE": return true
        default: return false
        }
    }
    var isScheduled: Bool { isFuture }
}
#endif
