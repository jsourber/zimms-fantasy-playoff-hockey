import Foundation

struct StandingsResponse: Codable {
    let updatedAt: Date
    let playoffStartDate: String
    let gamesProcessed: Int
    let standings: [Manager]
    let today: TodaySlate?
}

struct TodaySlate: Codable {
    let date: String
    let games: [TodayGame]
}

struct TodayGame: Codable, Identifiable {
    let id: Int
    let state: String?              // FUT/PRE/LIVE/CRIT/OFF/FINAL/OVER/INT
    let startUtc: String?
    let period: TodayPeriod?
    let clock: TodayClock?
    let away: TodayTeam
    let home: TodayTeam
    let seriesTitle: String?
    let seriesStatus: String?
}

struct TodayPeriod: Codable {
    let number: Int?
    let type: String?  // REG/OT/SO
}

struct TodayClock: Codable {
    let timeRemaining: String?
    let inIntermission: Bool?
    let running: Bool?
}

struct TodayTeam: Codable {
    let tricode: String?
    let name: String?
    let logoUrl: URL?
    let score: Int?
    let record: String?
}

struct Manager: Codable, Identifiable {
    var id: String { name }
    let rank: Int
    let name: String
    let total: Int
    let teamPts: Int
    let skaterPts: Int
    let teams: [TeamScore]
    let skaters: [Skater]
}

struct TeamScore: Codable, Identifiable {
    var id: String { tricode }
    let tricode: String
    let logoUrl: URL?
    let points: Int
    let games: [Game]
}

struct Game: Codable, Identifiable {
    var id: String { "\(date)-\(opp)" }
    let opp: String
    let goalsFor: Int
    let goalsAgainst: Int
    let points: Int
    let tags: [String]
    let date: String
}

struct Skater: Codable, Identifiable, Hashable {
    var id: Int { playerId }
    let name: String
    let playerId: Int
    let teamTricode: String?
    let sweaterNumber: Int?
    let headshotUrl: URL?
    let heroUrl: URL?
    let goals: Int
    let assists: Int
    let gamesPlayed: Int
    let points: Int
    let games: [SkaterGame]

    static func == (l: Skater, r: Skater) -> Bool { l.playerId == r.playerId }
    func hash(into h: inout Hasher) { h.combine(playerId) }
}

struct SkaterGame: Codable, Identifiable, Hashable {
    var id: String { "\(date)-\(opp)" }
    let date: String
    let opp: String
    let homeOrAway: String   // "home" | "away"
    let teamScore: Int
    let oppScore: Int
    let goals: Int
    let assists: Int
    let points: Int
}
