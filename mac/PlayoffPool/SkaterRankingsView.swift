import SwiftUI

#if os(macOS)
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
                    SkaterHeadshotImage(playerId: s.skater.playerId, fallbackURL: s.skater.headshotUrl)
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
#else
// iOS: SwiftUI Table collapses to first column on phones, so use a List.

enum SkaterSort: String, CaseIterable, Identifiable {
    case points = "Points"
    case goals  = "Goals"
    case assists = "Assists"
    var id: String { rawValue }
}

struct SkaterRankingsView: View {
    let skaters: [OwnedSkater]
    var roster: RosterIndex = .empty
    @State private var sort: SkaterSort = .points

    private var sorted: [OwnedSkater] {
        skaters.sorted { a, b in
            switch sort {
            case .points:  return a.skater.points  > b.skater.points
            case .goals:   return a.skater.goals   > b.skater.goals
            case .assists: return a.skater.assists > b.skater.assists
            }
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Sort by", selection: $sort) {
                    ForEach(SkaterSort.allCases) { s in Text(s.rawValue).tag(s) }
                }
                .pickerStyle(.segmented)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
            Section {
                ForEach(Array(sorted.enumerated()), id: \.element.id) { idx, s in
                    NavigationLink(value: s.skater) {
                        SkaterRowIOS(rank: idx + 1, owned: s, isEliminated: roster.isEliminated(skater: s.skater))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct SkaterRowIOS: View {
    let rank: Int
    let owned: OwnedSkater
    var isEliminated: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)

            SkaterHeadshotImage(playerId: owned.skater.playerId, fallbackURL: owned.skater.headshotUrl)
                .frame(width: 36, height: 36)
                .background(Color.gray.opacity(0.15))
                .clipShape(Circle())
                .opacity(isEliminated ? 0.55 : 1)
                .grayscale(isEliminated ? 0.6 : 0)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(owned.skater.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if isEliminated { EliminatedBadge(compact: true) }
                }
                HStack(spacing: 4) {
                    if let t = owned.skater.teamTricode {
                        Text(t)
                    }
                    Text("·")
                    Text(owned.owner)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }

            Spacer(minLength: 4)

            HStack(spacing: 8) {
                statCell(label: "G", value: owned.skater.goals,   color: .green)
                statCell(label: "A", value: owned.skater.assists, color: .blue)
                statCell(label: "Pts", value: owned.skater.points, color: .primary, bold: true)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func statCell(label: String, value: Int, color: Color, bold: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text("\(value)")
                .font(bold ? .subheadline.weight(.bold).monospacedDigit()
                            : .subheadline.weight(value > 0 ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(value > 0 || bold ? color : .secondary)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 32)
    }
}
#endif
