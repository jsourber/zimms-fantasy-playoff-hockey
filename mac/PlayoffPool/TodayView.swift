#if os(iOS)
import SwiftUI

struct TodayView: View {
    let slate: TodaySlate?              // initial today slate (seeded from StandingsResponse)
    let roster: RosterIndex
    let playoffStartDate: String        // earliest date the user can swipe back to
    @StateObject private var loader = DaySlateLoader()
    @StateObject private var landings = GameLandingCache()
    @State private var selectedOffset: Int = 0    // 0 = today, -1 = yesterday, etc.

    private var earliestOffset: Int {
        let start = ScoringEngine.parseDate(playoffStartDate)
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.day], from: cal.startOfDay(for: start),
                                       to: cal.startOfDay(for: Date()))
        return -(comps.day ?? 0)
    }

    private var allOffsets: [Int] { Array(earliestOffset...0) }

    var body: some View {
        VStack(spacing: 0) {
            dayHeader

            TabView(selection: $selectedOffset) {
                ForEach(allOffsets, id: \.self) { offset in
                    DaySlatePage(
                        date: dateFor(offset: offset),
                        roster: roster,
                        loader: loader,
                        landings: landings
                    )
                    .tag(offset)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .onAppear {
            loader.seed(slate)
        }
        .onChange(of: slate?.date ?? "") { _, _ in
            loader.seed(slate)
            // Refresh today's slate on parent refresh
            if let s = slate { loader.invalidate(date: ScoringEngine.parseDate(s.date)); loader.seed(s) }
        }
    }

    @ViewBuilder
    private var dayHeader: some View {
        HStack(spacing: 12) {
            Button {
                if selectedOffset > earliestOffset {
                    withAnimation { selectedOffset -= 1 }
                }
            } label: { Image(systemName: "chevron.left") }
                .disabled(selectedOffset <= earliestOffset)

            Spacer()

            VStack(spacing: 1) {
                Text(headerTitle(for: selectedOffset))
                    .font(.headline.weight(.semibold))
                Text(headerSubtitle(for: selectedOffset))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if selectedOffset < 0 {
                    withAnimation { selectedOffset += 1 }
                }
            } label: { Image(systemName: "chevron.right") }
                .disabled(selectedOffset >= 0)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(Color.platformGroupedBackground)
    }

    private func dateFor(offset: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
    }

    private func headerTitle(for offset: Int) -> String {
        switch offset {
        case 0: return "Today"
        case -1: return "Yesterday"
        default:
            let f = DateFormatter()
            f.dateFormat = "EEEE"
            return f.string(from: dateFor(offset: offset))
        }
    }

    private func headerSubtitle(for offset: Int) -> String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: dateFor(offset: offset))
    }
}

/// A single day's slate (one page in the swipeable TabView).
private struct DaySlatePage: View {
    let date: Date
    let roster: RosterIndex
    @ObservedObject var loader: DaySlateLoader
    @ObservedObject var landings: GameLandingCache

    private var key: String { ScoringEngine.isoDay(date) }
    private var slate: TodaySlate? { loader.slatesByDay[key] }

    var body: some View {
        Group {
            if let slate {
                if slate.games.isEmpty {
                    ContentUnavailableView {
                        Label("No playoff games", systemImage: "calendar.badge.exclamationmark")
                    } description: {
                        Text("No NHL playoff games on this date.")
                    }
                } else {
                    List {
                        let liveGames = slate.games.filter { $0.isLive }
                        let upcoming  = slate.games.filter { $0.isScheduled }
                        let finals    = slate.games.filter { $0.isFinal }

                        if !liveGames.isEmpty {
                            Section(header: sectionHeader("Live", color: .red, pulsing: true)) {
                                ForEach(liveGames) { GameCard(game: $0, roster: roster).environmentObject(landings) }
                            }
                        }
                        if !upcoming.isEmpty {
                            Section(header: sectionHeader("Upcoming", color: .secondary)) {
                                ForEach(upcoming) { GameCard(game: $0, roster: roster).environmentObject(landings) }
                            }
                        }
                        if !finals.isEmpty {
                            Section(header: sectionHeader("Final", color: .secondary)) {
                                ForEach(finals) { GameCard(game: $0, roster: roster).environmentObject(landings) }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Loading…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            loader.ensureLoaded(date: date)
        }
        .onChange(of: slate?.games.map(\.id) ?? []) { _, _ in
            // Refetch live games' goals when the slate changes
            for g in (slate?.games ?? []) where g.isLive {
                landings.invalidate(gameId: g.id)
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
    let roster: RosterIndex
    @EnvironmentObject var landings: GameLandingCache

    var body: some View {
        VStack(spacing: 10) {
            // header — series + status
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

            // teams + score
            HStack(spacing: 12) {
                teamCol(game.away)
                Spacer(minLength: 8)
                centerCol
                Spacer(minLength: 8)
                teamCol(game.home, alignTrailing: true)
            }

            // owner annotations under team row
            if roster.owner(forTeam: game.away.tricode) != nil || roster.owner(forTeam: game.home.tricode) != nil {
                HStack(spacing: 8) {
                    if let o = roster.owner(forTeam: game.away.tricode) {
                        OwnerBadge(name: o, color: roster.color(for: o))
                    } else {
                        Color.clear.frame(width: 1, height: 1)
                    }
                    Spacer()
                    if let o = roster.owner(forTeam: game.home.tricode) {
                        OwnerBadge(name: o, color: roster.color(for: o))
                    } else {
                        Color.clear.frame(width: 1, height: 1)
                    }
                }
            }

            if let s = game.seriesStatus, !s.isEmpty {
                Text(s)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            // scoring summary (only fetch for live or final)
            if game.isLive || game.isFinal {
                ScoringSummaryView(gameId: game.id, isFinal: game.isFinal, roster: roster)
                    .environmentObject(landings)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func teamCol(_ t: TodayTeam, alignTrailing: Bool = false) -> some View {
        VStack(alignment: alignTrailing ? .trailing : .leading, spacing: 4) {
            TeamLogoImage(tricode: t.tricode, fallbackURL: t.logoUrl, size: 44)

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

private struct ScoringSummaryView: View {
    let gameId: Int
    let isFinal: Bool
    let roster: RosterIndex
    @EnvironmentObject var landings: GameLandingCache

    var body: some View {
        Group {
            if let periods = landings.periodsByGame[gameId] {
                let periodsWithGoals = periods.filter { !$0.goals.isEmpty }
                if periodsWithGoals.isEmpty {
                    Text("No goals yet.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 6)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider().padding(.top, 4)
                        ForEach(periodsWithGoals) { p in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(p.label) Period")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                ForEach(p.goals) { g in
                                    GoalRowView(goal: g, roster: roster)
                                }
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading goals…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 6)
            }
        }
        .onAppear { landings.ensureLoaded(gameId: gameId, isFinal: isFinal) }
    }
}

private struct GoalRowView: View {
    let goal: GoalView
    let roster: RosterIndex

    var body: some View {
        let scorerOwner = roster.owner(forPlayer: goal.scorerId)
        let teamOwner = roster.owner(forTeam: goal.team)
        let teamColor = roster.color(for: teamOwner)

        HStack(alignment: .top, spacing: 8) {
            // team tag — colored by owner if rostered
            VStack(spacing: 1) {
                Text(goal.team)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(teamOwner != nil ? teamColor : Color.secondary))
                    .frame(minWidth: 38)
                if let o = teamOwner {
                    Text(o)
                        .font(.system(size: 9).weight(.semibold))
                        .foregroundStyle(teamColor)
                        .lineLimit(1)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                // scorer line
                HStack(spacing: 6) {
                    PersonTag(name: goal.scorer,
                              owner: scorerOwner,
                              ownerColor: roster.color(for: scorerOwner),
                              isScorer: true)
                    if let s = goal.strength {
                        Text(s)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(s == "PP" ? .orange : .blue)
                    }
                    if let m = goal.modifier, m != "none" {
                        Text(modifierLabel(m))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.purple)
                    }
                }
                // assists line
                if !goal.assists.isEmpty {
                    let parts = goal.assists.map { a -> (String, String?, Color) in
                        let o = roster.owner(forPlayer: a.id)
                        return (a.name, o, roster.color(for: o))
                    }
                    AssistsLine(parts: parts)
                } else {
                    Text("unassisted")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(goal.awayScore)–\(goal.homeScore)")
                    .font(.caption.weight(.bold).monospacedDigit())
                Text(goal.timeInPeriod)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }

    private func modifierLabel(_ m: String) -> String {
        switch m {
        case "empty-net": return "EN"
        case "penalty-shot": return "PS"
        case "own-goal": return "OG"
        default: return m.uppercased()
        }
    }
}

/// Inline name + owner badge (highlighted background when the player is on someone's roster).
private struct PersonTag: View {
    let name: String
    let owner: String?
    let ownerColor: Color
    let isScorer: Bool

    var body: some View {
        HStack(spacing: 3) {
            Text(name)
                .font(isScorer ? .caption.weight(.semibold) : .caption2)
                .foregroundStyle(owner != nil ? ownerColor : .primary)
            if let o = owner {
                Text(o)
                    .font(.system(size: 9).weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(ownerColor))
            }
        }
    }
}

private struct AssistsLine: View {
    /// (name, owner?, ownerColor)
    let parts: [(String, String?, Color)]

    var body: some View {
        HStack(spacing: 3) {
            Text("from")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(0..<parts.count, id: \.self) { i in
                let (name, owner, color) = parts[i]
                PersonTag(name: name, owner: owner, ownerColor: color, isScorer: false)
                if i < parts.count - 1 {
                    Text(",")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct OwnerBadge: View {
    let name: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.12)))
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
