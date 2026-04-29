import Foundation

/// Bundled rosters.json shape — mirrors the file that the Python scorer reads.
struct RosterFile: Decodable {
    let playoffStartDate: String
    let managers: [String: ManagerRoster]

    enum CodingKeys: String, CodingKey {
        case playoffStartDate = "playoff_start_date"
        case managers
    }
}

struct ManagerRoster: Decodable {
    let teams: [String]
    let skaters: [RosterSkater]
}

struct RosterSkater: Decodable {
    let id: Int
    let name: String
}

// MARK: - Persistent player metadata cache (file-backed in Caches/)

private struct PlayerMeta: Codable {
    var headshotUrl: String?
    var heroUrl: String?
    var teamTricode: String?
    var sweaterNumber: Int?
    var firstName: String?
    var lastName: String?
    var position: String?
}

private final class PlayerMetaCache {
    private var cache: [Int: PlayerMeta]
    private let fileURL: URL

    init() {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.fileURL = dir.appendingPathComponent("nhl-player-meta.json")
        if let data = try? Data(contentsOf: fileURL),
           let dict = try? JSONDecoder().decode([Int: PlayerMeta].self, from: data) {
            self.cache = dict
        } else {
            self.cache = [:]
        }
    }

    subscript(id: Int) -> PlayerMeta? { cache[id] }

    func set(_ meta: PlayerMeta, for id: Int) { cache[id] = meta }

    func persist() {
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}

// MARK: - Engine

/// Computes a `StandingsResponse` directly from the NHL API + a bundled roster.
/// Mirrors scorer.py:cmd_score behavior so the on-device output matches the GitHub-served file.
struct ScoringEngine {

    static let espnTriAliases: [String: String] = [
        "TBL": "tb", "LAK": "la", "SJS": "sj", "NJD": "nj"
    ]

    static func espnLogoURL(for tricode: String) -> URL? {
        let key = espnTriAliases[tricode.uppercased()] ?? tricode.lowercased()
        return URL(string: "https://a.espncdn.com/i/teamlogos/nhl/500/\(key).png")
    }

    static func loadBundledRosters() throws -> RosterFile {
        guard let url = Bundle.main.url(forResource: "rosters", withExtension: "json") else {
            throw NSError(domain: "ScoringEngine", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "rosters.json missing from bundle"])
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RosterFile.self, from: data)
    }

    /// Compute a fresh `StandingsResponse` from the NHL API.
    static func compute() async throws -> StandingsResponse {
        let rosters = try loadBundledRosters()
        let startDate = parseDate(rosters.playoffStartDate)
        let endDate = Date()

        // 1. Pull every day's score listing in [start, end] and keep finished playoff games.
        var allGames: [NHLScoreGame] = []
        var todayGames: [NHLScoreGame] = []
        let cal = Calendar(identifier: .gregorian)
        var cursor = startDate
        let endDay = cal.startOfDay(for: endDate)
        let todayStr = isoDay(endDate)

        while cal.startOfDay(for: cursor) <= endDay {
            let dStr = isoDay(cursor)
            do {
                let day: NHLScoreDay = try await NHLAPI.getJSON("score/\(dStr)")
                let playoffGames = day.games.filter { $0.gameType == 3 }
                if dStr == todayStr {
                    todayGames = playoffGames
                }
                // Include LIVE games too — skater goals/assists count in real time.
                // (Team result classification still gates W/OTL/SO/5+G on game completion.)
                let scorable = playoffGames.filter { isFinished($0.gameState) || isLive($0.gameState) }
                allGames.append(contentsOf: scorable)
            } catch {
                // Soft-fail individual days
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? endDate
        }

        // 2. Hydrate skater metadata (cached on disk).
        let allSkaterIds: Set<Int> = Set(rosters.managers.values.flatMap { $0.skaters.map(\.id) })
        let metaCache = PlayerMetaCache()
        for pid in allSkaterIds where metaCache[pid] == nil {
            do {
                let landing: NHLPlayerLanding = try await NHLAPI.getJSON("player/\(pid)/landing")
                metaCache.set(PlayerMeta(
                    headshotUrl: landing.headshot,
                    heroUrl: landing.heroImage,
                    teamTricode: landing.currentTeamAbbrev,
                    sweaterNumber: landing.sweaterNumber,
                    firstName: landing.firstName?.default,
                    lastName: landing.lastName?.default,
                    position: landing.position
                ), for: pid)
            } catch {
                metaCache.set(PlayerMeta(), for: pid)
            }
        }
        metaCache.persist()

        // 3. For each finished game: compute team result + skater stats.
        struct TeamResult { let gameId: Int; let tri: String; let pts: Int; let reasons: [String]; let game: NHLScoreGame }
        var teamResults: [TeamResult] = []
        var skaterTotals: [Int: SkaterAccum] = [:]

        for game in allGames {
            // Team points + game-log entries only get built for FINISHED games.
            // Live games' team result is unknown until the buzzer.
            if isFinished(game.gameState) {
                for tri in [game.awayTeam.abbrev, game.homeTeam.abbrev] {
                    let (pts, reasons) = classifyTeamResult(game: game, tricode: tri)
                    teamResults.append(TeamResult(gameId: game.id, tri: tri, pts: pts, reasons: reasons, game: game))
                }
            }
            // Skater stats accumulate from all scorable games (live + finished),
            // so a goal scored in a live game updates standings immediately.
            do {
                let box: NHLBoxscore = try await NHLAPI.getJSON("gamecenter/\(game.id)/boxscore")
                addSkaterStats(from: box, game: game, wanted: allSkaterIds, into: &skaterTotals)
            } catch {
                // skip game on boxscore failure
            }
        }

        // 4. Build per-manager standings, sorted by total desc.
        var standings: [Manager] = []
        // Stable manager ordering — Python uses dict insertion order (Python 3.7+); JSON preserves it.
        // We iterate the rosters file by re-decoding to keep order, but Dictionary loses order in Swift.
        // We instead sort by total below; for ties, name asc.
        for (name, m) in rosters.managers {
            var teamPts = 0
            var teamScores: [TeamScore] = []
            for tri in m.teams {
                var subtotal = 0
                var games: [Game] = []
                for r in teamResults where r.tri == tri {
                    subtotal += r.pts
                    let g = r.game
                    let (gf, ga, opp) = sideScores(game: g, myTri: tri)
                    games.append(Game(
                        opp: opp,
                        goalsFor: gf,
                        goalsAgainst: ga,
                        points: r.pts,
                        tags: r.reasons.isEmpty ? ["L"] : r.reasons,
                        date: dayString(from: g)
                    ))
                }
                teamPts += subtotal
                teamScores.append(TeamScore(
                    tricode: tri,
                    logoUrl: espnLogoURL(for: tri),
                    points: subtotal,
                    games: games
                ))
            }

            var sk: [Skater] = []
            var skPts = 0
            for rs in m.skaters {
                let acc = skaterTotals[rs.id] ?? SkaterAccum()
                let pts = acc.goals * 2 + acc.assists
                skPts += pts
                let meta = metaCache[rs.id]
                sk.append(Skater(
                    name: rs.name,
                    playerId: rs.id,
                    teamTricode: meta?.teamTricode,
                    sweaterNumber: meta?.sweaterNumber,
                    headshotUrl: meta?.headshotUrl.flatMap(URL.init),
                    heroUrl: meta?.heroUrl.flatMap(URL.init),
                    goals: acc.goals,
                    assists: acc.assists,
                    gamesPlayed: acc.games,
                    points: pts,
                    games: acc.log.sorted { $0.date < $1.date }
                ))
            }

            standings.append(Manager(
                rank: 0,  // assigned after sort
                name: name,
                total: teamPts + skPts,
                teamPts: teamPts,
                skaterPts: skPts,
                teams: teamScores,
                skaters: sk
            ))
        }
        standings.sort { (a, b) in a.total != b.total ? a.total > b.total : a.name < b.name }
        let ranked = standings.enumerated().map { (i, m) in
            Manager(rank: i + 1, name: m.name, total: m.total, teamPts: m.teamPts,
                    skaterPts: m.skaterPts, teams: m.teams, skaters: m.skaters)
        }

        // 5. Today slate
        let today = TodaySlate(
            date: todayStr,
            games: todayGames.map { mapTodayGame($0) }
        )

        // 6. Elimination tracking
        // Walk every game we've seen, group by series, take the latest seriesStatus
        // (the one with the highest gameNumberOfSeries). If a side hit neededToWin,
        // the other side is eliminated.
        var latestStatusBySeries: [String: NHLSeriesStatus] = [:]
        var latestGameNumBySeries: [String: Int] = [:]
        var activeTeams: Set<String> = []
        for g in (allGames + todayGames) {
            activeTeams.insert(g.awayTeam.abbrev)
            activeTeams.insert(g.homeTeam.abbrev)
            guard let ss = g.seriesStatus,
                  let top = ss.topSeedTeamAbbrev,
                  let bot = ss.bottomSeedTeamAbbrev else { continue }
            let key = [top, bot].sorted().joined(separator: "-")
            let n = ss.gameNumberOfSeries ?? 0
            if (latestGameNumBySeries[key] ?? -1) <= n {
                latestStatusBySeries[key] = ss
                latestGameNumBySeries[key] = n
            }
        }
        var eliminated: Set<String> = []
        for (_, ss) in latestStatusBySeries {
            let need = ss.neededToWin ?? 4
            let tw = ss.topSeedWins ?? 0
            let bw = ss.bottomSeedWins ?? 0
            guard let top = ss.topSeedTeamAbbrev,
                  let bot = ss.bottomSeedTeamAbbrev else { continue }
            if tw >= need { eliminated.insert(bot) }
            else if bw >= need { eliminated.insert(top) }
        }

        return StandingsResponse(
            updatedAt: Date(),
            playoffStartDate: rosters.playoffStartDate,
            gamesProcessed: allGames.count,
            standings: ranked,
            today: today,
            eliminatedTeams: Array(eliminated).sorted(),
            activePlayoffTeams: Array(activeTeams).sorted()
        )
    }

    // MARK: - Helpers

    private struct SkaterAccum {
        var goals: Int = 0
        var assists: Int = 0
        var games: Int = 0
        var log: [SkaterGame] = []
    }

    private static func isFinished(_ state: String?) -> Bool {
        switch (state ?? "").uppercased() {
        case "OFF", "FINAL", "OVER": return true
        default: return false
        }
    }

    private static func isLive(_ state: String?) -> Bool {
        switch (state ?? "").uppercased() {
        case "LIVE", "CRIT": return true
        default: return false
        }
    }

    static func parseDate(_ s: String) -> Date {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s) ?? Date()
    }

    static func isoDay(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "America/New_York") // NHL uses US/Eastern day boundaries
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private static func dayString(from g: NHLScoreGame) -> String {
        if let d = g.gameDate, !d.isEmpty { return String(d.prefix(10)) }
        if let s = g.startTimeUTC { return String(s.prefix(10)) }
        return ""
    }

    private static func sideScores(game g: NHLScoreGame, myTri: String) -> (gf: Int, ga: Int, opp: String) {
        if myTri == g.awayTeam.abbrev {
            return (g.awayTeam.score ?? 0, g.homeTeam.score ?? 0, g.homeTeam.abbrev)
        } else {
            return (g.homeTeam.score ?? 0, g.awayTeam.score ?? 0, g.awayTeam.abbrev)
        }
    }

    private static func classifyTeamResult(game g: NHLScoreGame, tricode tri: String) -> (Int, [String]) {
        // Team points only count for finished games; live games' final result is unknown.
        guard isFinished(g.gameState) else { return (0, []) }
        let (mine, opp) = (g.awayTeam.abbrev == tri) ? (g.awayTeam, g.homeTeam)
                       : (g.homeTeam.abbrev == tri) ? (g.homeTeam, g.awayTeam)
                       : (g.awayTeam, g.homeTeam)
        guard mine.abbrev == tri else { return (0, []) }
        let myG = mine.score ?? 0
        let oppG = opp.score ?? 0
        let lastPeriod = (g.periodDescriptor?.periodType ?? "REG").uppercased()

        var pts = 0
        var reasons: [String] = []
        if myG > oppG {
            pts += 2; reasons.append("W")
            if oppG == 0 { pts += 1; reasons.append("SO") }
        } else if myG < oppG && (lastPeriod == "OT" || lastPeriod == "SO") {
            pts += 1; reasons.append("OTL")
        }
        if myG >= 5 { pts += 1; reasons.append("5+G") }
        return (pts, reasons)
    }

    private static func addSkaterStats(
        from box: NHLBoxscore,
        game g: NHLScoreGame,
        wanted: Set<Int>,
        into totals: inout [Int: SkaterAccum]
    ) {
        let sides: [(side: String, team: NHLTeamSkaters?)] = [
            ("away", box.playerByGameStats?.awayTeam),
            ("home", box.playerByGameStats?.homeTeam),
        ]
        for entry in sides {
            let side = entry.side
            let team = entry.team
            for s in (team?.forwards ?? []) + (team?.defense ?? []) {
                guard wanted.contains(s.playerId) else { continue }
                var acc = totals[s.playerId] ?? SkaterAccum()
                let goals = s.goals ?? 0
                let assists = s.assists ?? 0
                acc.goals += goals
                acc.assists += assists
                acc.games += 1
                let (myScore, oppScore, opp) = sideScores(game: g, myTri: side == "away" ? g.awayTeam.abbrev : g.homeTeam.abbrev)
                acc.log.append(SkaterGame(
                    date: dayString(from: g),
                    opp: opp,
                    homeOrAway: side,
                    teamScore: myScore,
                    oppScore: oppScore,
                    goals: goals,
                    assists: assists,
                    points: goals * 2 + assists
                ))
                totals[s.playerId] = acc
            }
        }
    }

    static func mapTodayGame(_ g: NHLScoreGame) -> TodayGame {
        var seriesTitle = g.seriesStatus?.seriesTitle ?? ""
        if let n = g.seriesStatus?.gameNumberOfSeries {
            seriesTitle = seriesTitle.isEmpty ? "Game \(n)" : "\(seriesTitle) · Game \(n)"
        }
        var seriesStatus = ""
        if let top = g.seriesStatus?.topSeedTeamAbbrev,
           let bot = g.seriesStatus?.bottomSeedTeamAbbrev {
            let tw = g.seriesStatus?.topSeedWins ?? 0
            let bw = g.seriesStatus?.bottomSeedWins ?? 0
            if tw > bw { seriesStatus = "\(top) leads \(tw)-\(bw)" }
            else if bw > tw { seriesStatus = "\(bot) leads \(bw)-\(tw)" }
            else { seriesStatus = "Tied \(tw)-\(bw)" }
        }
        return TodayGame(
            id: g.id,
            state: g.gameState,
            startUtc: g.startTimeUTC,
            period: g.periodDescriptor.map { TodayPeriod(number: $0.number, type: $0.periodType) },
            clock: g.clock.map { TodayClock(timeRemaining: $0.timeRemaining,
                                            inIntermission: $0.inIntermission,
                                            running: $0.running) },
            away: TodayTeam(
                tricode: g.awayTeam.abbrev,
                name: g.awayTeam.name?.default,
                logoUrl: espnLogoURL(for: g.awayTeam.abbrev),
                score: g.awayTeam.score,
                record: g.awayTeam.record
            ),
            home: TodayTeam(
                tricode: g.homeTeam.abbrev,
                name: g.homeTeam.name?.default,
                logoUrl: espnLogoURL(for: g.homeTeam.abbrev),
                score: g.homeTeam.score,
                record: g.homeTeam.record
            ),
            seriesTitle: seriesTitle.isEmpty ? nil : seriesTitle,
            seriesStatus: seriesStatus.isEmpty ? nil : seriesStatus
        )
    }
}
