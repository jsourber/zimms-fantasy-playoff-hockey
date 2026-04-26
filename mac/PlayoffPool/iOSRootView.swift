#if os(iOS)
import SwiftUI

struct iOSRootView: View {
    @StateObject private var service = StandingsService()
    @State private var showSettings = false

    var body: some View {
        TabView {
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
            .navigationDestination(for: Manager.self) { ManagerDetailView(manager: $0) }
            .navigationDestination(for: Skater.self) { SkaterDetailView(skater: $0) }
            .toolbar { commonToolbar }
            .refreshable { await service.refresh() }
        }
    }

    private var skaterRankingsTab: some View {
        NavigationStack {
            Group {
                if let data = service.data {
                    SkaterRankingsView(skaters: data.allSkaters)
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
                    TeamRankingsView(teams: data.allTeams)
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
                Label("Data from \(relativeUpdated(data.updatedAt))",
                      systemImage: "icloud.and.arrow.down")
                if let t = service.lastRefreshedAt {
                    Label("Fetched \(t.formatted(date: .omitted, time: .shortened))",
                          systemImage: "clock")
                }
            }
            .font(.caption)
        }
    }

    private func relativeUpdated(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        let rel = f.localizedString(for: date, relativeTo: Date())
        let abs = date.formatted(date: .omitted, time: .shortened)
        return "\(rel) (\(abs))"
    }
}

private struct iOSSettingsSheet: View {
    @ObservedObject var service: StandingsService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("standings.json URL",
                              text: $service.standingsUrl, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .lineLimit(3, reservesSpace: true)
                        .font(.footnote.monospaced())
                    Button("Reset to default") {
                        service.standingsUrl = StandingsService.defaultStandingsUrl
                    }
                    .font(.footnote)
                } header: {
                    Text("Standings JSON URL")
                } footer: {
                    Text("Defaults to Zimm's league feed on GitHub, which auto-refreshes every 10 minutes. Only change this if you know what you're doing.")
                }

                Section {
                    Button("Refresh Now") {
                        Task {
                            await service.refresh()
                            dismiss()
                        }
                    }
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
