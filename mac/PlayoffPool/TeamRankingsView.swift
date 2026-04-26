import SwiftUI

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
