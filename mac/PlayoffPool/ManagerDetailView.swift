import SwiftUI

struct ManagerDetailView: View {
    let manager: Manager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                statsBar
                teamsSection
                skatersSection
            }
            .padding(24)
        }
        .navigationTitle(manager.name)
        .background(Color.platformBackground)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 18) {
            RankBadge(rank: manager.rank).scaleEffect(1.4)
            VStack(alignment: .leading, spacing: 4) {
                Text(manager.name)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                HStack(spacing: 8) {
                    ForEach(manager.teams) { TeamLogo(team: $0, size: 28) }
                    Text(manager.teams.map(\.tricode).joined(separator: " · "))
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(manager.total)")
                .font(.system(size: 64, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(LinearGradient(
                    colors: [.accentColor, .accentColor.opacity(0.6)],
                    startPoint: .top, endPoint: .bottom))
        }
    }

    private var statsBar: some View {
        HStack(spacing: 12) {
            StatPill(label: "Team", value: manager.teamPts, system: "shield.lefthalf.filled")
            StatPill(label: "Skater", value: manager.skaterPts, system: "person.2.fill")
            StatPill(label: "Total", value: manager.total, system: "trophy.fill", emphasized: true)
        }
    }

    // MARK: - Teams

    private var teamsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Teams", system: "shield.lefthalf.filled")
            HStack(alignment: .top, spacing: 16) {
                ForEach(manager.teams) { TeamCard(team: $0) }
            }
        }
    }

    // MARK: - Skaters

    private var skatersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Skaters", system: "person.2.fill")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                ForEach(manager.skaters) { s in
                    NavigationLink(value: s) {
                        SkaterCard(skater: s)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sectionTitle(_ text: String, system: String) -> some View {
        Label(text, systemImage: system)
            .font(.title3.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Stat pill

struct StatPill: View {
    let label: String
    let value: Int
    let system: String
    var emphasized: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: system)
                .font(.title3)
                .foregroundStyle(emphasized ? .yellow : .accentColor)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption).foregroundStyle(.secondary)
                Text("\(value)")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

// MARK: - Team card

struct TeamCard: View {
    let team: TeamScore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TeamLogo(team: team, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(team.tricode)
                        .font(.title2.weight(.bold))
                    Text("\(team.points) pts")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()
            if team.games.isEmpty {
                Text("No games yet")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 6) {
                    ForEach(team.games) { GameRow(game: $0) }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

struct GameRow: View {
    let game: Game
    var body: some View {
        HStack(spacing: 8) {
            Text("vs")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(game.opp)
                .font(.subheadline.weight(.semibold))
                .frame(width: 36, alignment: .leading)
            Text("\(game.goalsFor)–\(game.goalsAgainst)")
                .font(.subheadline)
                .monospacedDigit()
            Spacer()
            TagsView(tags: game.tags)
            Text(game.points > 0 ? "+\(game.points)" : "0")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)
                .foregroundStyle(game.points > 0 ? .primary : .secondary)
        }
    }
}

// MARK: - Skater card

struct SkaterCard: View {
    let skater: Skater

    var body: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                AsyncImage(url: skater.headshotUrl) { phase in
                    switch phase {
                    case .success(let img):
                        img.resizable().scaledToFill()
                    case .failure, .empty:
                        Image(systemName: "person.fill")
                            .resizable().scaledToFit()
                            .padding(14)
                            .foregroundStyle(.secondary.opacity(0.5))
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 64, height: 64)
                .background(Color.gray.opacity(0.15))
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.quaternary, lineWidth: 1))

                if let n = skater.sweaterNumber {
                    Text("#\(n)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 5).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                        .foregroundStyle(.white)
                        .offset(x: 4, y: 2)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(skater.name)
                    .font(.headline)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if let tri = skater.teamTricode {
                        Text(tri)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.secondary.opacity(0.15)))
                    }
                    Text("\(skater.gamesPlayed) GP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    StatChip(value: skater.goals, label: "G", color: .green)
                    StatChip(value: skater.assists, label: "A", color: .blue)
                }
            }

            Spacer()

            VStack(spacing: 0) {
                Text("\(skater.points)")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text("pts")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

struct StatChip: View {
    let value: Int
    let label: String
    let color: Color
    var body: some View {
        HStack(spacing: 3) {
            Text("\(value)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 7).padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

// MARK: - Tags

private struct TagsView: View {
    let tags: [String]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(tags, id: \.self) { t in
                Text(t)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(color(for: t).opacity(0.18), in: Capsule())
                    .foregroundStyle(color(for: t))
            }
        }
    }
    private func color(for tag: String) -> Color {
        switch tag {
        case "W":   return .green
        case "OTL": return .orange
        case "SO":  return .blue
        case "5+G": return .purple
        case "L":   return .secondary
        default:    return .secondary
        }
    }
}
