import SwiftUI
import AppKit

// MARK: - Top-level picker (Today / My Teams / leagues)

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

// MARK: - Cross-sport TV guide ("What's on today")

struct GuideView: View {
    @ObservedObject var model: ScoreModel

    var body: some View {
        let entries = model.guideEntries
        let live = entries.filter { $0.match.isLive }
        let upcoming = entries.filter { !$0.match.isLive }
        VStack(spacing: 8) {
            if entries.isEmpty {
                if model.lastUpdated == nil {
                    ProgressView("Loading today's games…").padding(.vertical, 30)
                } else {
                    Text("Nothing on today")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }
            }
            if live.isEmpty, let next = upcoming.first {
                CountdownBanner(entry: next)
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

struct CountdownBanner: View {
    let entry: GuideEntry

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = entry.match.kickoff.timeIntervalSince(context.date)
            let soon = remaining <= 600
            HStack(spacing: 8) {
                Image(systemName: soon ? "bell.badge.fill" : "clock.fill")
                    .foregroundStyle(soon ? .red : .yellow)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(entry.league.emoji) \(entry.match.home.abbrev) v \(entry.match.away.abbrev)")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    Text(soon ? "Starting soon — get to a screen!" : "Next up")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(countdown(remaining))
                    .font(.system(.title3, design: .monospaced).weight(.bold))
                    .foregroundStyle(soon ? .red : .yellow)
            }
            .padding(12)
            .background((soon ? Color.red : Color.yellow).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func countdown(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval))
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return h > 0 ? String(format: "%dh %02dm", h, m)
                     : String(format: "%dm %02ds", m, sec)
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
                    Text(scoreLine(m))
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

    private func scoreLine(_ m: Match) -> String {
        guard m.isLive else { return "\(m.home.abbrev) v \(m.away.abbrev)" }
        if entry.league == .cricket { return "\(m.home.abbrev) v \(m.away.abbrev)" }
        guard let h = m.home.score, let a = m.away.score else {
            return "\(m.home.abbrev) v \(m.away.abbrev)"
        }
        return "\(m.home.abbrev) \(h)–\(a) \(m.away.abbrev)"
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
                Text("No games right now for your teams")
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

// MARK: - Standings

struct StandingsView: View {
    let league: SportLeague
    @ObservedObject var model: ScoreModel

    var body: some View {
        VStack(spacing: 10) {
            if let tables = model.usStandings[league] {
                if tables.isEmpty {
                    Text("Standings unavailable")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }
                ForEach(tables) { table in
                    VStack(spacing: 6) {
                        HStack {
                            Text(table.name)
                                .font(.system(.caption, design: .rounded).weight(.bold))
                                .lineLimit(1)
                            Spacer()
                            Text("W    L    PCT")
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
                                Text(String(format: "%3d  %3d  %@", row.wins, row.losses, row.pct))
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
        .task(id: league) { await model.loadStandings(for: league) }
    }
}

// MARK: - Box score (line scores + win probability)

struct BoxScoreView: View {
    let match: Match
    let league: SportLeague
    @ObservedObject var model: ScoreModel

    private var periodLabel: String {
        switch league {
        case .softball, .ausl, .mlb: return "Inning"
        case .nba, .nfl, .cfb: return "Quarter"
        case .nhl: return "Period"
        case .cricket: return "Innings"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let count = max(match.home.periods.count, match.away.periods.count)
            if count == 0 {
                Text("Box score not available yet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
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
                    boxRow(match.home, count: count)
                    boxRow(match.away, count: count)
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

    private func boxRow(_ side: TeamSide, count: Int) -> some View {
        GridRow {
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
