import SwiftUI

struct SkaterRankingsView: View {
    let skaters: [OwnedSkater]

    @State private var sortOrder: [KeyPathComparator<OwnedSkater>] = [
        KeyPathComparator(\.skater.points, order: .reverse),
        KeyPathComparator(\.skater.goals,  order: .reverse),
    ]

    private var sorted: [OwnedSkater] { skaters.sorted(using: sortOrder) }

    var body: some View {
        Table(sorted, sortOrder: $sortOrder) {
            TableColumn("#") { s in
                Text("\(rank(of: s))")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(36)

            TableColumn("Player") { s in
                HStack(spacing: 10) {
                    AsyncImage(url: s.skater.headshotUrl) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFill()
                        case .failure, .empty:
                            Image(systemName: "person.fill").resizable().scaledToFit()
                                .padding(8).foregroundStyle(.secondary.opacity(0.5))
                        @unknown default: EmptyView()
                        }
                    }
                    .frame(width: 32, height: 32)
                    .background(Color.gray.opacity(0.15))
                    .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 1) {
                        Text(s.skater.name).font(.subheadline.weight(.semibold))
                        if let n = s.skater.sweaterNumber, let t = s.skater.teamTricode {
                            Text("#\(n) · \(t)").font(.caption).foregroundStyle(.secondary)
                        } else if let t = s.skater.teamTricode {
                            Text(t).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }

            TableColumn("Owner", value: \.owner) { s in
                Text(s.owner).font(.subheadline)
            }
            .width(min: 70, ideal: 90)

            TableColumn("GP", value: \.skater.gamesPlayed) { s in
                Text("\(s.skater.gamesPlayed)").monospacedDigit()
            }
            .width(40)

            TableColumn("G", value: \.skater.goals) { s in
                Text("\(s.skater.goals)").monospacedDigit()
                    .foregroundStyle(s.skater.goals > 0 ? .green : .secondary)
                    .font(s.skater.goals > 0 ? .body.weight(.semibold) : .body)
            }
            .width(40)

            TableColumn("A", value: \.skater.assists) { s in
                Text("\(s.skater.assists)").monospacedDigit()
                    .foregroundStyle(s.skater.assists > 0 ? .blue : .secondary)
                    .font(s.skater.assists > 0 ? .body.weight(.semibold) : .body)
            }
            .width(40)

            TableColumn("Pts", value: \.skater.points) { s in
                Text("\(s.skater.points)")
                    .monospacedDigit()
                    .font(.body.weight(.bold))
            }
            .width(50)
        }
        .navigationTitle("Skater Rankings")
    }

    private func rank(of s: OwnedSkater) -> Int {
        (sorted.firstIndex(of: s) ?? 0) + 1
    }
}
