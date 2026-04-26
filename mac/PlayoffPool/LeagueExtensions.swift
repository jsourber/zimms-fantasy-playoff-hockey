import Foundation

// MARK: - Flattened views across all managers

struct OwnedSkater: Identifiable, Hashable {
    var id: Int { skater.playerId }
    let skater: Skater
    let owner: String
}

struct OwnedTeam: Identifiable, Hashable {
    var id: String { team.tricode }
    let team: TeamScore
    let owner: String

    static func == (l: OwnedTeam, r: OwnedTeam) -> Bool {
        l.team.tricode == r.team.tricode && l.owner == r.owner
    }
    func hash(into h: inout Hasher) {
        h.combine(team.tricode); h.combine(owner)
    }
}

extension StandingsResponse {
    var allSkaters: [OwnedSkater] {
        standings.flatMap { m in m.skaters.map { OwnedSkater(skater: $0, owner: m.name) } }
    }
    var allTeams: [OwnedTeam] {
        standings.flatMap { m in m.teams.map { OwnedTeam(team: $0, owner: m.name) } }
    }
}

// MARK: - Team-result counts derived from game tags

extension TeamScore {
    var wins: Int      { games.filter { $0.tags.contains("W") }.count }
    var otls: Int      { games.filter { $0.tags.contains("OTL") }.count }
    var shutouts: Int  { games.filter { $0.tags.contains("SO") }.count }
    var fivePlus: Int  { games.filter { $0.tags.contains("5+G") }.count }
    var losses: Int {
        games.filter { !$0.tags.contains("W") && !$0.tags.contains("OTL") }.count
    }
    var record: String { "\(wins)-\(losses)-\(otls)" }   // W-L-OTL
}
