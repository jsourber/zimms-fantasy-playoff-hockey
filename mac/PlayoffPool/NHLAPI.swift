import Foundation

/// Thin wrapper around the public NHL "api-web" endpoints.
struct NHLAPI {
    static let base = URL(string: "https://api-web.nhle.com/v1")!
    private static let userAgent = "fantasy-hockey-scorer-ios/1.0"

    static func get(_ path: String) async throws -> Data {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw NSError(
                domain: "NHL", code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) for /\(path)"])
        }
        return data
    }

    static func getJSON<T: Decodable>(_ path: String, as: T.Type = T.self) async throws -> T {
        let data = try await get(path)
        return try JSONDecoder().decode(T.self, from: data)
    }
}

// MARK: - Score endpoint

struct NHLScoreDay: Decodable {
    let games: [NHLScoreGame]
}

struct NHLScoreGame: Decodable {
    let id: Int
    let gameType: Int
    let gameDate: String?
    let startTimeUTC: String?
    let gameState: String?
    let awayTeam: NHLScoreTeam
    let homeTeam: NHLScoreTeam
    let periodDescriptor: NHLPeriod?
    let clock: NHLClock?
    let seriesStatus: NHLSeriesStatus?
}

struct NHLScoreTeam: Decodable {
    let id: Int
    let abbrev: String
    let name: NHLLocalized?
    let score: Int?
    let record: String?
    let logo: String?
}

struct NHLLocalized: Decodable {
    let `default`: String?
}

struct NHLPeriod: Decodable {
    let number: Int?
    let periodType: String?    // REG / OT / SO
}

struct NHLClock: Decodable {
    let timeRemaining: String?
    let inIntermission: Bool?
    let running: Bool?
}

struct NHLSeriesStatus: Decodable {
    let seriesTitle: String?
    let gameNumberOfSeries: Int?
    let topSeedTeamAbbrev: String?
    let bottomSeedTeamAbbrev: String?
    let topSeedWins: Int?
    let bottomSeedWins: Int?
}

// MARK: - Boxscore endpoint

struct NHLBoxscore: Decodable {
    let id: Int
    let playerByGameStats: NHLPlayerByGameStats?
}

struct NHLPlayerByGameStats: Decodable {
    let awayTeam: NHLTeamSkaters?
    let homeTeam: NHLTeamSkaters?
}

struct NHLTeamSkaters: Decodable {
    let forwards: [NHLBoxSkater]?
    let defense: [NHLBoxSkater]?
}

struct NHLBoxSkater: Decodable {
    let playerId: Int
    let goals: Int?
    let assists: Int?
}

// MARK: - Player landing

struct NHLPlayerLanding: Decodable {
    let firstName: NHLLocalized?
    let lastName: NHLLocalized?
    let sweaterNumber: Int?
    let position: String?
    let currentTeamAbbrev: String?
    let headshot: String?
    let heroImage: String?
}
