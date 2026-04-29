#if os(iOS)
import Foundation
import SwiftUI

/// Loads the playoff slate (live + final + scheduled games) for an arbitrary date,
/// caching results in memory. Used by TodayView's day-paging swipe.
@MainActor
final class DaySlateLoader: ObservableObject {
    @Published private(set) var slatesByDay: [String: TodaySlate] = [:]
    @Published private(set) var loading: Set<String> = []
    private var inFlight: Set<String> = []

    /// Pre-seed today's slate from StandingsResponse so the first page is instant.
    func seed(_ slate: TodaySlate?) {
        guard let s = slate else { return }
        slatesByDay[s.date] = s
    }

    func ensureLoaded(date: Date) {
        let key = ScoringEngine.isoDay(date)
        if slatesByDay[key] != nil || inFlight.contains(key) { return }
        inFlight.insert(key)
        loading.insert(key)
        Task {
            defer {
                inFlight.remove(key)
                loading.remove(key)
            }
            do {
                let day: NHLScoreDay = try await NHLAPI.getJSON("score/\(key)")
                let games = day.games.filter { $0.gameType == 3 }
                slatesByDay[key] = TodaySlate(
                    date: key,
                    games: games.map { ScoringEngine.mapTodayGame($0) }
                )
            } catch {
                slatesByDay[key] = TodaySlate(date: key, games: [])
            }
        }
    }

    func invalidate(date: Date) {
        let key = ScoringEngine.isoDay(date)
        slatesByDay.removeValue(forKey: key)
    }
}
#endif
