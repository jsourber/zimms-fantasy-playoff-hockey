import SwiftUI

struct SkaterDetailView: View {
    let skater: Skater

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                hero
                statsBar
                gameLog
            }
            .padding(24)
        }
        .background(Color.platformBackground)
        .navigationTitle(skater.name)
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            SkaterHeroImage(playerId: skater.playerId, fallbackURL: skater.heroUrl)
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .clipped()

            // dark gradient for text legibility
            LinearGradient(
                colors: [.black.opacity(0.0), .black.opacity(0.7)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 240)

            HStack(alignment: .bottom, spacing: 16) {
                SkaterHeadshotImage(playerId: skater.playerId, fallbackURL: skater.headshotUrl)
                    .frame(width: 100, height: 100)
                    .background(Color.gray.opacity(0.2))
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 3))

                VStack(alignment: .leading, spacing: 4) {
                    Text(skater.name)
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                    HStack(spacing: 8) {
                        if let n = skater.sweaterNumber {
                            Text("#\(n)")
                                .font(.headline.weight(.bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 8).padding(.vertical, 2)
                                .background(Capsule().fill(.white.opacity(0.25)))
                        }
                        if let t = skater.teamTricode {
                            Text(t)
                                .font(.headline)
                                .foregroundStyle(.white.opacity(0.95))
                        }
                    }
                }
                Spacer()
            }
            .padding(20)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Stat bar

    private var statsBar: some View {
        HStack(spacing: 12) {
            StatPill(label: "Goals",   value: skater.goals,    system: "circle.fill")
            StatPill(label: "Assists", value: skater.assists,  system: "hand.raised.fill")
            StatPill(label: "GP",      value: skater.gamesPlayed, system: "calendar")
            StatPill(label: "Points",  value: skater.points,   system: "trophy.fill", emphasized: true)
        }
    }

    // MARK: - Game log

    @ViewBuilder
    private var gameLog: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Game-by-game", systemImage: "list.bullet.rectangle")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)

            if skater.games.isEmpty {
                Text("No games played yet in this playoffs.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 12)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Date").frame(width: 90, alignment: .leading)
                        Text("Matchup").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Score").frame(width: 70, alignment: .trailing)
                        Text("G").frame(width: 28, alignment: .trailing)
                        Text("A").frame(width: 28, alignment: .trailing)
                        Text("Pts").frame(width: 40, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14).padding(.vertical, 8)

                    Divider()

                    ForEach(Array(skater.games.enumerated()), id: \.element.id) { idx, g in
                        SkaterGameRow(game: g, zebra: idx.isMultiple(of: 2))
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.thinMaterial)
                )
            }
        }
    }
}

private struct SkaterGameRow: View {
    let game: SkaterGame
    let zebra: Bool

    var body: some View {
        HStack {
            Text(formattedDate)
                .frame(width: 90, alignment: .leading)
                .font(.subheadline)
                .monospacedDigit()
            HStack(spacing: 4) {
                Text(game.homeOrAway == "home" ? "vs" : "@")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text(game.opp).font(.subheadline.weight(.semibold))
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(game.teamScore)–\(game.oppScore)")
                .font(.subheadline)
                .monospacedDigit()
                .frame(width: 70, alignment: .trailing)

            Text(game.goals == 0 ? "—" : "\(game.goals)")
                .font(.subheadline.weight(game.goals > 0 ? .bold : .regular))
                .foregroundStyle(game.goals > 0 ? .green : .secondary)
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)

            Text(game.assists == 0 ? "—" : "\(game.assists)")
                .font(.subheadline.weight(game.assists > 0 ? .bold : .regular))
                .foregroundStyle(game.assists > 0 ? .blue : .secondary)
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)

            Text("\(game.points)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(zebra ? Color.gray.opacity(0.06) : Color.clear)
    }

    private var formattedDate: String {
        // game.date is "yyyy-MM-dd"
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        guard let d = f.date(from: game.date) else { return game.date }
        let out = DateFormatter()
        out.dateFormat = "EEE MMM d"
        return out.string(from: d)
    }
}
