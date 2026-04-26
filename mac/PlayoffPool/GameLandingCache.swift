#if os(iOS)
import Foundation
import SwiftUI

/// Per-game scoring summary for the Today view.
/// Fetched on-demand from /v1/gamecenter/{id}/landing.
struct ScoringPeriodView: Identifiable {
    let id: Int          // period number
    let label: String    // "1st", "2nd", "3rd", "OT", "SO"
    let goals: [GoalView]
}

struct GoalView: Identifiable {
    let id: Int          // index within game
    let scorer: String
    let assists: [String]
    let team: String
    let timeInPeriod: String
    let strength: String?     // "PP" | "SH" | nil for even
    let modifier: String?     // "EN" for empty-net, etc.
    let awayScore: Int
    let homeScore: Int
}

@MainActor
final class GameLandingCache: ObservableObject {
    /// gameId → loaded periods (or nil while loading / failed)
    @Published private(set) var periodsByGame: [Int: [ScoringPeriodView]] = [:]
    private var inFlight: Set<Int> = []

    /// Cached landings for finals never need refetch within a session.
    /// Live game refetches happen when caller invalidates by calling `invalidate(gameId:)`.
    private var lockedFinals: Set<Int> = []

    func ensureLoaded(gameId: Int, isFinal: Bool) {
        if periodsByGame[gameId] != nil && lockedFinals.contains(gameId) { return }
        if inFlight.contains(gameId) { return }
        inFlight.insert(gameId)
        Task {
            defer { inFlight.remove(gameId) }
            do {
                let landing: NHLGameLanding = try await NHLAPI.getJSON("gamecenter/\(gameId)/landing")
                let periods = (landing.summary?.scoring ?? []).enumerated().compactMap { (idx, p) -> ScoringPeriodView? in
                    let n = p.periodDescriptor?.number ?? (idx + 1)
                    let type = (p.periodDescriptor?.periodType ?? "REG").uppercased()
                    let label: String
                    if type == "OT" { label = n > 3 ? "\(n - 3)OT" : "OT" }
                    else if type == "SO" { label = "SO" }
                    else {
                        switch n {
                        case 1: label = "1st"; case 2: label = "2nd"; case 3: label = "3rd"
                        default: label = "\(n)th"
                        }
                    }
                    let goals = (p.goals ?? []).enumerated().map { (gi, g) -> GoalView in
                        GoalView(
                            id: n * 1000 + gi,
                            scorer: g.name?.default ?? "?",
                            assists: (g.assists ?? []).compactMap { $0.name?.default },
                            team: g.teamAbbrev?.default ?? "",
                            timeInPeriod: g.timeInPeriod ?? "",
                            strength: (g.strength ?? "ev").lowercased() == "ev" ? nil : (g.strength ?? "").uppercased(),
                            modifier: (g.goalModifier ?? "none") == "none" ? nil : g.goalModifier,
                            awayScore: g.awayScore ?? 0,
                            homeScore: g.homeScore ?? 0
                        )
                    }
                    return ScoringPeriodView(id: n, label: label, goals: goals)
                }
                periodsByGame[gameId] = periods
                if isFinal { lockedFinals.insert(gameId) }
            } catch {
                periodsByGame[gameId] = []   // mark as loaded-empty so we don't retry forever
            }
        }
    }

    func invalidate(gameId: Int) {
        periodsByGame.removeValue(forKey: gameId)
        lockedFinals.remove(gameId)
    }

    func invalidateAll() {
        periodsByGame.removeAll()
        lockedFinals.removeAll()
    }
}
#endif
