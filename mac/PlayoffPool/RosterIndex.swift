import Foundation
import SwiftUI

/// Quick-lookup index from a StandingsResponse: NHL team tricode → fantasy owner,
/// NHL player id → fantasy owner. Used by the Today view to annotate goals.
struct RosterIndex {
    let ownerByTeam: [String: String]
    let ownerByPlayerId: [Int: String]
    let colorByOwner: [String: Color]
    /// Tricodes of NHL teams eliminated from the playoffs.
    let eliminatedTeams: Set<String>
    /// Tricodes of NHL teams that are/were in the playoffs at all.
    let activePlayoffTeams: Set<String>

    static let empty = RosterIndex(
        ownerByTeam: [:], ownerByPlayerId: [:], colorByOwner: [:],
        eliminatedTeams: [], activePlayoffTeams: []
    )

    init(ownerByTeam: [String: String],
         ownerByPlayerId: [Int: String],
         colorByOwner: [String: Color],
         eliminatedTeams: Set<String>,
         activePlayoffTeams: Set<String>) {
        self.ownerByTeam = ownerByTeam
        self.ownerByPlayerId = ownerByPlayerId
        self.colorByOwner = colorByOwner
        self.eliminatedTeams = eliminatedTeams
        self.activePlayoffTeams = activePlayoffTeams
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
        self.eliminatedTeams = Set(resp.eliminatedTeams ?? [])
        self.activePlayoffTeams = Set(resp.activePlayoffTeams ?? [])
    }

    /// True if this team has been eliminated from the playoffs.
    func isEliminated(team tri: String?) -> Bool {
        guard let tri else { return false }
        return eliminatedTeams.contains(tri)
    }

    /// True if this skater's NHL team is eliminated, OR their team isn't in the playoffs at all.
    func isEliminated(skater: Skater) -> Bool {
        if let tri = skater.teamTricode {
            if eliminatedTeams.contains(tri) { return true }
            // Team isn't in any playoff series — counts as eliminated for fantasy purposes.
            if !activePlayoffTeams.isEmpty && !activePlayoffTeams.contains(tri) { return true }
        }
        return false
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
