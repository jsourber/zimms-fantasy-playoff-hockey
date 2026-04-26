import Foundation
import SwiftUI

/// Quick-lookup index from a StandingsResponse: NHL team tricode → fantasy owner,
/// NHL player id → fantasy owner. Used by the Today view to annotate goals.
struct RosterIndex {
    let ownerByTeam: [String: String]
    let ownerByPlayerId: [Int: String]
    /// Stable color per owner so the UI is consistent across rows.
    let colorByOwner: [String: Color]

    static let empty = RosterIndex(ownerByTeam: [:], ownerByPlayerId: [:], colorByOwner: [:])

    init(ownerByTeam: [String: String],
         ownerByPlayerId: [Int: String],
         colorByOwner: [String: Color]) {
        self.ownerByTeam = ownerByTeam
        self.ownerByPlayerId = ownerByPlayerId
        self.colorByOwner = colorByOwner
    }

    init(_ resp: StandingsResponse?) {
        guard let resp else {
            self = .empty
            return
        }
        var teams: [String: String] = [:]
        var players: [Int: String] = [:]
        for m in resp.standings {
            for t in m.teams { teams[t.tricode] = m.name }
            for s in m.skaters { players[s.playerId] = m.name }
        }
        // Distinct, deterministic palette so each manager keeps the same color.
        let palette: [Color] = [
            .red, .blue, .green, .orange, .purple,
            .pink, .teal, .indigo, .brown, .mint
        ]
        var colors: [String: Color] = [:]
        for (i, name) in resp.standings.map(\.name).enumerated() {
            colors[name] = palette[i % palette.count]
        }
        self.ownerByTeam = teams
        self.ownerByPlayerId = players
        self.colorByOwner = colors
    }

    func owner(forTeam tri: String?) -> String? {
        guard let tri else { return nil }
        return ownerByTeam[tri]
    }

    func owner(forPlayer id: Int?) -> String? {
        guard let id else { return nil }
        return ownerByPlayerId[id]
    }

    func ownerForScorerName(_ name: String?) -> String? {
        // Scorer/assist names from the landing endpoint use "F. Last" form.
        // We don't get player IDs in the goal payload, but we DO have them via
        // the global NHLLandingGoal — see the cache layer.
        nil
    }

    func color(for owner: String?) -> Color {
        guard let owner, let c = colorByOwner[owner] else { return .secondary }
        return c
    }
}
