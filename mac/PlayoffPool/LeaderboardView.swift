import SwiftUI

enum NavItem: Hashable {
    case skaterRankings
    case teamRankings
    case manager(Manager)
}

#if os(macOS)
struct LeaderboardView: View {
    @StateObject private var service = StandingsService()
    @State private var showSettings = false
    @State private var selection: NavItem? = .skaterRankings

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationTitle("Playoff Pool")
                .navigationSplitViewColumnWidth(min: 320, ideal: 360)
                .toolbar {
                    ToolbarItem {
                        Button {
                            showSettings.toggle()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .popover(isPresented: $showSettings) {
                            SettingsPopover(service: service)
                        }
                    }
                    ToolbarItem {
                        Button {
                            Task { await service.refresh() }
                        } label: {
                            if service.isLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                        }
                        .disabled(service.isLoading)
                        .keyboardShortcut("r", modifiers: .command)
                    }
                }
        } detail: {
            NavigationStack {
                detail
                    .navigationDestination(for: Skater.self) { SkaterDetailView(skater: $0) }
            }
        }
        .frame(minWidth: 1080, minHeight: 700)
        .task { await service.refresh() }
    }

    @ViewBuilder
    private var detail: some View {
        if let data = service.data {
            switch selection ?? .skaterRankings {
            case .skaterRankings:
                SkaterRankingsView(skaters: data.allSkaters)
            case .teamRankings:
                TeamRankingsView(teams: data.allTeams)
            case .manager(let m):
                ManagerDetailView(manager: m)
            }
        } else {
            ContentUnavailableView("Loading…", systemImage: "hockey.puck")
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        if let data = service.data {
            List(selection: $selection) {
                Section("League") {
                    Label("Skater Rankings", systemImage: "person.2.fill")
                        .tag(NavItem.skaterRankings)
                    Label("Team Rankings", systemImage: "shield.lefthalf.filled")
                        .tag(NavItem.teamRankings)
                }

                Section("Managers") {
                    ForEach(data.standings) { manager in
                        LeaderboardRow(manager: manager)
                            .tag(NavItem.manager(manager))
                            .listRowSeparator(.visible)
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("\(data.gamesProcessed) games processed",
                              systemImage: "hockey.puck.fill")
                        if let t = service.lastRefreshedAt {
                            Label("Refreshed \(t.formatted(date: .omitted, time: .standard))",
                                  systemImage: "clock")
                        }
                        if let err = service.lastError {
                            Text(err).foregroundStyle(.red)
                        }
                    }
                    .font(.caption)
                    .padding(.top, 8)
                }
            }
        } else if service.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Running scorer.py…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let err = service.lastError {
            ContentUnavailableView("Couldn't load standings",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(err))
        } else {
            ProgressView()
        }
    }
}
#endif

struct LeaderboardRow: View {
    let manager: Manager

    var body: some View {
        HStack(spacing: 14) {
            RankBadge(rank: manager.rank)

            VStack(alignment: .leading, spacing: 6) {
                Text(manager.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    ForEach(manager.teams) { t in
                        TeamLogo(team: t, size: 22)
                    }
                    Text(manager.teams.map(\.tricode).joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(manager.total)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("T \(manager.teamPts) · S \(manager.skaterPts)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .padding(.vertical, 6)
    }
}

struct RankBadge: View {
    let rank: Int
    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.15))
            Circle()
                .strokeBorder(color.opacity(0.4), lineWidth: 1)
            Text("\(rank)")
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .foregroundStyle(color)
        }
        .frame(width: 30, height: 30)
    }
    private var color: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return .secondary
        }
    }
}

struct TeamLogo: View {
    let team: TeamScore
    var size: CGFloat = 32

    var body: some View {
        AsyncImage(url: team.logoUrl) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            case .failure, .empty:
                Image(systemName: "shield.fill")
                    .resizable().scaledToFit()
                    .foregroundStyle(.secondary.opacity(0.4))
            @unknown default:
                EmptyView()
            }
        }
        .frame(width: size, height: size)
    }
}

#if os(macOS)
private struct SettingsPopover: View {
    @ObservedObject var service: StandingsService
    var body: some View {
        Form {
            TextField("scorer.py path", text: $service.scorerPath).frame(width: 460)
            TextField("python3 path",  text: $service.pythonPath).frame(width: 460)
        }
        .padding()
    }
}
#endif

extension Manager: Hashable {
    static func == (lhs: Manager, rhs: Manager) -> Bool { lhs.name == rhs.name }
    func hash(into hasher: inout Hasher) { hasher.combine(name) }
}
