#if os(iOS)
import SwiftUI

struct iOSRootView: View {
    @StateObject private var service = StandingsService()
    @State private var showSettings = false

    var body: some View {
        TabView {
            todayTab
                .tabItem { Label("Today", systemImage: "hockey.puck.fill") }

            standingsTab
                .tabItem { Label("Standings", systemImage: "trophy.fill") }

            skaterRankingsTab
                .tabItem { Label("Skaters", systemImage: "person.2.fill") }

            teamRankingsTab
                .tabItem { Label("Teams", systemImage: "shield.lefthalf.filled") }
        }
        .task { await service.refresh() }
        .sheet(isPresented: $showSettings) {
            iOSSettingsSheet(service: service)
        }
    }

    // MARK: - Today tab (live / upcoming / final games)

    private var todayTab: some View {
        NavigationStack {
            Group {
                if let data = service.data {
                    TodayView(slate: data.today,
                              roster: RosterIndex(service.data),
                              playoffStartDate: data.playoffStartDate)
                } else {
                    loadingOrError
                }
            }
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { commonToolbar }
            .refreshable { await service.refresh() }
        }
    }

    // MARK: - Standings tab (managers + drill-in)

    private var standingsTab: some View {
        NavigationStack {
            Group {
                if let data = service.data {
                    List {
                        Section {
                            ForEach(data.standings) { manager in
                                NavigationLink(value: manager) {
                                    LeaderboardRow(manager: manager)
                                }
                            }
                        } footer: {
                            footerView
                        }
                    }
                    .listStyle(.insetGrouped)
                } else {
                    loadingOrError
                }
            }
            .navigationTitle("Playoff Pool")
            .navigationDestination(for: Manager.self) { ManagerDetailView(manager: $0, roster: RosterIndex(service.data)) }
            .navigationDestination(for: Skater.self) { SkaterDetailView(skater: $0) }
            .toolbar { commonToolbar }
            .refreshable { await service.refresh() }
        }
    }

    private var skaterRankingsTab: some View {
        NavigationStack {
            Group {
                if let data = service.data {
                    SkaterRankingsView(skaters: data.allSkaters, roster: RosterIndex(service.data))
                } else {
                    loadingOrError
                }
            }
            .navigationTitle("Skater Rankings")
            .navigationDestination(for: Skater.self) { SkaterDetailView(skater: $0) }
            .toolbar { commonToolbar }
            .refreshable { await service.refresh() }
        }
    }

    private var teamRankingsTab: some View {
        NavigationStack {
            Group {
                if let data = service.data {
                    TeamRankingsView(teams: data.allTeams, roster: RosterIndex(service.data))
                } else {
                    loadingOrError
                }
            }
            .navigationTitle("Team Rankings")
            .toolbar { commonToolbar }
            .refreshable { await service.refresh() }
        }
    }

    // MARK: - Helpers

    @ToolbarContentBuilder
    private var commonToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                Task { await service.refresh() }
            } label: {
                if service.isLoading {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(service.isLoading)
        }
        ToolbarItem(placement: .topBarLeading) {
            Button { showSettings = true } label: { Image(systemName: "gearshape") }
        }
    }

    @ViewBuilder
    private var loadingOrError: some View {
        if service.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Fetching standings…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = service.lastError {
            ContentUnavailableView {
                Label("Couldn't load standings", systemImage: "exclamationmark.triangle")
            } description: {
                Text(err)
            } actions: {
                Button("Open Settings") { showSettings = true }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView("Loading…", systemImage: "hockey.puck")
        }
    }

    @ViewBuilder
    private var footerView: some View {
        if let data = service.data {
            VStack(alignment: .leading, spacing: 4) {
                Label("\(data.gamesProcessed) games processed", systemImage: "hockey.puck.fill")
                if let t = service.lastRefreshedAt {
                    Label("Refreshed \(t.formatted(date: .omitted, time: .shortened))",
                          systemImage: "clock")
                }
            }
            .font(.caption)
        }
    }
}

private struct iOSSettingsSheet: View {
    @ObservedObject var service: StandingsService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Refresh Now") {
                        Task {
                            await service.refresh()
                            dismiss()
                        }
                    }
                    Button("Clear cached player metadata", role: .destructive) {
                        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
                        try? FileManager.default.removeItem(at: dir.appendingPathComponent("nhl-player-meta.json"))
                    }
                } footer: {
                    Text("Standings are computed live from the NHL API on each refresh. Player headshots and team info are cached locally to keep refreshes fast.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
#endif
