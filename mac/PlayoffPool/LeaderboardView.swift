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
                    let roster = RosterIndex(data)
                    ForEach(data.standings) { manager in
                        LeaderboardRow(manager: manager, isFinal: roster.isManagerDone(manager))
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
    var isFinal: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            RankBadge(rank: manager.rank)

            VStack(alignment: .leading, spacing: 4) {
                Text(manager.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    ForEach(manager.teams) { t in
                        TeamLogo(team: t, size: 18)
                    }
                    Text(manager.teams.map(\.tricode).joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            VStack(alignment: .trailing, spacing: 1) {
                HStack(spacing: 6) {
                    if isFinal {
                        Text("FINAL")
                            .font(.system(size: 9).weight(.heavy))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Capsule().fill(Color.red.opacity(0.85)))
                    }
                    Text("\(manager.total)")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()
                }
                Text("T \(manager.teamPts) · S \(manager.skaterPts)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 4)
        .opacity(isFinal ? 0.85 : 1)
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
        TeamLogoImage(tricode: team.tricode, fallbackURL: team.logoUrl, size: size)
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
