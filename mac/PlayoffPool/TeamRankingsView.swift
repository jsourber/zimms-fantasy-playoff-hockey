import SwiftUI

#if os(macOS)
struct TeamRankingsView: View {
    let teams: [OwnedTeam]

    @State private var sortOrder: [KeyPathComparator<OwnedTeam>] = [
        KeyPathComparator(\.team.points, order: .reverse),
        KeyPathComparator(\.team.wins,   order: .reverse),
    ]

    private var sorted: [OwnedTeam] { teams.sorted(using: sortOrder) }

    var body: some View {
        Table(sorted, sortOrder: $sortOrder) {
            TableColumn("#") { t in
                Text("\(rank(of: t))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(36)

            TableColumn("Team") { t in
                HStack(spacing: 10) {
                    TeamLogo(team: t.team, size: 30)
                    Text(t.team.tricode)
                        .font(.subheadline.weight(.semibold))
                }
                .padding(.vertical, 2)
            }
            .width(min: 90, ideal: 110)

            TableColumn("Owner", value: \.owner) { t in
                Text(t.owner).font(.subheadline)
            }
            .width(min: 70, ideal: 90)

            TableColumn("Record") { t in
                Text(t.team.record).monospacedDigit()
            }
            .width(80)

            TableColumn("W", value: \.team.wins) { t in
                Text("\(t.team.wins)").monospacedDigit()
                    .foregroundStyle(t.team.wins > 0 ? .green : .secondary)
                    .font(t.team.wins > 0 ? .body.weight(.semibold) : .body)
            }
            .width(40)

            TableColumn("OTL", value: \.team.otls) { t in
                Text("\(t.team.otls)").monospacedDigit()
                    .foregroundStyle(t.team.otls > 0 ? .orange : .secondary)
            }
            .width(46)

            TableColumn("SO", value: \.team.shutouts) { t in
                Text("\(t.team.shutouts)").monospacedDigit()
                    .foregroundStyle(t.team.shutouts > 0 ? .blue : .secondary)
            }
            .width(40)

            TableColumn("5+G", value: \.team.fivePlus) { t in
                Text("\(t.team.fivePlus)").monospacedDigit()
                    .foregroundStyle(t.team.fivePlus > 0 ? .purple : .secondary)
            }
            .width(46)

            TableColumn("Pts", value: \.team.points) { t in
                Text("\(t.team.points)")
                    .monospacedDigit()
                    .font(.body.weight(.bold))
            }
            .width(50)
        }
        .navigationTitle("Team Rankings")
    }

    private func rank(of t: OwnedTeam) -> Int {
        (sorted.firstIndex(of: t) ?? 0) + 1
    }
}
#else
enum TeamSort: String, CaseIterable, Identifiable {
    case points = "Points"
    case wins   = "Wins"
    case record = "Record"
    var id: String { rawValue }
}

struct TeamRankingsView: View {
    let teams: [OwnedTeam]
    @State private var sort: TeamSort = .points

    private var sorted: [OwnedTeam] {
        teams.sorted { a, b in
            switch sort {
            case .points: return a.team.points > b.team.points
            case .wins:   return a.team.wins   > b.team.wins
            case .record:
                if a.team.wins != b.team.wins { return a.team.wins > b.team.wins }
                return a.team.losses < b.team.losses
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Sort by", selection: $sort) {
                    ForEach(TeamSort.allCases) { s in Text(s.rawValue).tag(s) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            Section {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, t in
                    TeamRowIOS(rank: idx + 1, owned: t)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct TeamRowIOS: View {
    let rank: Int
    let owned: OwnedTeam

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            TeamLogo(team: owned.team, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(owned.team.tricode)
                        .font(.subheadline.weight(.bold))
                    Text(owned.team.record)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Text(owned.owner)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                tag("SO", count: owned.team.shutouts, color: .blue)
                tag("5+G", count: owned.team.fivePlus, color: .purple)
                Text("\(owned.team.points)")
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .frame(minWidth: 24)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func tag(_ label: String, count: Int, color: Color) -> some View {
        if count > 0 {
            HStack(spacing: 2) {
                Text("\(count)").font(.caption2.weight(.bold).monospacedDigit())
                Text(label).font(.caption2)
            }
            .foregroundStyle(color)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.12)))
        }
    }
}
#endif
