import SwiftUI
import AppKit

// MARK: - Top-level picker (guide / my teams / leagues)

struct TopPicker: View {
    @Binding var selected: MainTab
    @ObservedObject var model: ScoreModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                chip(.guide, emoji: "📺", label: "Today")
                chip(.mine, emoji: "⭐️", label: "My Teams")
                ForEach(model.visibleLeagues) { league in
                    chip(.league(league), emoji: league.emoji, label: league.label)
                }
            }
            .padding(.horizontal, 12)
        }
        .padding(.top, 8)
    }

    private func chip(_ tab: MainTab, emoji: String, label: String) -> some View {
        Button {
            selected = tab
        } label: {
            VStack(spacing: 1) {
                Text(emoji).font(.system(size: 15))
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .frame(minWidth: 52)
            .padding(.vertical, 5)
            .padding(.horizontal, 4)
            .background(selected == tab ? .white.opacity(0.14) : .white.opacity(0.001),
                        in: RoundedRectangle(cornerRadius: 10))
            .foregroundStyle(selected == tab ? .white : .secondary)
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Cross-sport TV guide ("What to watch today")

struct GuideView: View {
    @ObservedObject var model: ScoreModel

    var body: some View {
        let entries = model.guideEntries
        let live = entries.filter { $0.match.isLive }
        let upcoming = entries.filter { !$0.match.isLive }
        VStack(spacing: 8) {
            if entries.isEmpty {
                Text("Nothing on today")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            }
            if !live.isEmpty {
                SectionLabel(text: "Live now")
                ForEach(live) { GuideRow(entry: $0, model: model) }
            }
            if !upcoming.isEmpty {
                SectionLabel(text: "Coming up today")
                ForEach(upcoming) { GuideRow(entry: $0, model: model) }
            }
        }
        .padding(12)
    }
}

struct GuideRow: View {
    let entry: GuideEntry
    @ObservedObject var model: ScoreModel

    var body: some View {
        let m = entry.match
        HStack(spacing: 8) {
            if m.isLive {
                HStack(spacing: 4) {
                    PulsingDot()
                    Text("LIVE")
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(.red)
                }
                .frame(width: 52, alignment: .leading)
            } else {
                Text(m.kickoff, style: .time)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .frame(width: 62, alignment: .leading)
            }
            Text(entry.league.emoji)
                .font(.system(size: 12))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if model.isFavoriteMatch(m, league: entry.league) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.yellow)
                    }
                    Text(m.isLive && m.home.score != nil
                         ? "\(m.home.abbrev) \(m.home.score ?? 0)–\(m.away.score ?? 0) \(m.away.abbrev)"
                         : "\(m.home.abbrev) v \(m.away.abbrev)")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                }
                if !m.networks.isEmpty {
                    Text("📺 \(m.networks.prefix(3).joined(separator: " · "))")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let url = m.gamecastURL {
                Button {
                    openInBrowser(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.white.opacity(m.isLive ? 0.08 : 0.04),
                    in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - My Teams

struct MyTeamsView: View {
    @ObservedObject var model: ScoreModel

    var body: some View {
        let entries = model.myTeamEntries
        VStack(spacing: 8) {
            if model.favorites.isEmpty {
                VStack(spacing: 6) {
                    Text("⭐️").font(.title)
                    Text("No teams followed yet")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    Text("Tap the ☆ next to any team name to follow it. Their games show up here and get priority in the menu bar.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.vertical, 30)
                .padding(.horizontal, 20)
            } else if entries.isEmpty {
                Text("No upcoming games for your teams")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
            }
            ForEach(entries) { entry in
                if entry.league == .cricket {
                    CricketCard(match: entry.match, model: model)
                } else {
                    MatchCard(match: entry.match, model: model, league: entry.league)
                }
            }
        }
        .padding(12)
    }
}

// MARK: - Golden Boot (World Cup top scorers)

struct ScorersTab: View {
    @ObservedObject var model: ScoreModel

    var body: some View {
        VStack(spacing: 8) {
            Text("Golden Boot Race")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.yellow)
                .padding(.top, 4)
            if model.scorers.isEmpty {
                if model.scorersLoading {
                    ProgressView("Loading scorers…").padding(.vertical, 24)
                } else {
                    Text("No goals yet")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }
            }
            ForEach(Array(model.scorers.enumerated()), id: \.element.id) { index, scorer in
                HStack(spacing: 8) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(index == 0 ? .yellow : .secondary)
                        .frame(width: 18, alignment: .trailing)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(scorer.name)
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                        if !scorer.teamName.isEmpty {
                            Text(scorer.teamName)
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text("⚽️ \(scorer.goals)")
                        .font(.system(.caption, design: .rounded).weight(.heavy))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.white.opacity(index == 0 ? 0.08 : 0.04),
                            in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(12)
        .task { await model.loadScorers() }
    }
}

// MARK: - US league standings

struct USStandingsView: View {
    let league: SportLeague
    @ObservedObject var model: ScoreModel

    var body: some View {
        VStack(spacing: 10) {
            if let tables = model.usStandings[league], !tables.isEmpty {
                ForEach(tables) { table in
                    VStack(spacing: 6) {
                        HStack {
                            Text(table.name)
                                .font(.system(.caption, design: .rounded).weight(.bold))
                            Spacer()
                            Text("W    L    PCT     GB")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        ForEach(table.rows) { row in
                            let isFavorite = model.isFavorite(league, row.id)
                            HStack(spacing: 6) {
                                AsyncImage(url: row.logoURL) { phase in
                                    if let image = phase.image {
                                        image.resizable().scaledToFit()
                                    } else {
                                        Color.clear
                                    }
                                }
                                .frame(width: 16, height: 16)
                                Text(row.name)
                                    .font(.system(.caption2, design: .rounded)
                                        .weight(isFavorite ? .bold : .regular))
                                    .foregroundStyle(isFavorite ? .yellow : .primary)
                                    .lineLimit(1)
                                Spacer()
                                Text(String(format: "%3d  %3d  %@  %@",
                                            row.wins, row.losses,
                                            row.pct.padding(toLength: 5, withPad: " ", startingAt: 0),
                                            row.gamesBehind))
                                    .font(.system(size: 10, design: .monospaced))
                            }
                        }
                    }
                    .padding(10)
                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                }
            } else {
                ProgressView("Loading standings…").padding(.vertical, 24)
            }
        }
    }
}

// MARK: - Box score (line scores + win probability)

struct BoxScoreView: View {
    let match: Match
    let league: SportLeague
    @ObservedObject var model: ScoreModel

    private var periodLabel: String {
        switch league {
        case .mlb: return "Inning"
        case .nba, .nfl, .cfb: return "Quarter"
        case .nhl: return "Period"
        default: return "Period"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if match.home.periods.isEmpty && match.away.periods.isEmpty {
                Text("Box score not available yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                let count = max(match.home.periods.count, match.away.periods.count)
                Grid(horizontalSpacing: 7, verticalSpacing: 3) {
                    GridRow {
                        Text(periodLabel)
                            .gridColumnAlignment(.leading)
                        ForEach(0..<count, id: \.self) { i in
                            Text("\(i + 1)")
                        }
                        Text("T").fontWeight(.bold)
                    }
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    boxRow(match.home)
                    boxRow(match.away)
                }
            }
            if match.isLive, let pct = model.winProb[match.id] {
                let homePct = Int((pct * 100).rounded())
                HStack(spacing: 6) {
                    Text("Win probability")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text("\(match.home.abbrev) \(homePct)% – \(100 - homePct)% \(match.away.abbrev)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                }
                GeometryReader { geo in
                    HStack(spacing: 1) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.green)
                            .frame(width: geo.size.width * pct)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.white.opacity(0.25))
                    }
                }
                .frame(height: 4)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
        .task {
            if match.isLive {
                await model.loadWinProb(league: league, matchId: match.id)
            }
        }
    }

    private func boxRow(_ side: TeamSide) -> some View {
        let count = max(match.home.periods.count, match.away.periods.count)
        return GridRow {
            Text(side.abbrev)
                .fontWeight(.bold)
                .gridColumnAlignment(.leading)
            ForEach(0..<count, id: \.self) { i in
                Text(i < side.periods.count ? "\(side.periods[i])" : "-")
            }
            Text("\(side.score ?? 0)").fontWeight(.bold)
        }
        .font(.system(size: 10, design: .monospaced))
    }
}
