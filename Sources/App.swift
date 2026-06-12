import SwiftUI
import AppKit
import ServiceManagement

/// Opens a URL in the default browser and brings the browser to the front.
/// A plain `NSWorkspace.open` from a menu-bar-only (LSUIElement) app can load
/// the page without activating the browser, which looks like nothing happened.
func openInBrowser(_ url: URL) {
    let config = NSWorkspace.OpenConfiguration()
    config.activates = true
    NSWorkspace.shared.open(url, configuration: config) { app, _ in
        DispatchQueue.main.async {
            app?.activate(options: [.activateIgnoringOtherApps])
        }
    }
}

@main
struct WorldCupApp: App {
    @StateObject private var model: ScoreModel

    init() {
        if CommandLine.arguments.contains("--test") {
            Self.runSmokeTest()
        }
        _model = StateObject(wrappedValue: ScoreModel())
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardView(model: model)
        } label: {
            Text(model.menuTitle)
        }
        .menuBarExtraStyle(.window)
    }

    private static func runSmokeTest() {
        let sem = DispatchSemaphore(value: 0)
        Task.detached {
            do {
                let matches = try await ScoreModel.fetchDay(nil)
                let groups = try await ScoreModel.fetchStandings()
                let bracket = try await ScoreModel.fetchBracket()
                print("OK: \(matches.count) matches today, \(groups.count) groups, \(bracket.count) knockout rounds")
                let f = DateFormatter()
                f.dateStyle = .medium
                f.timeStyle = .short
                for m in matches {
                    let score = m.state == .pre ? "vs" : "\(m.home.score ?? 0)-\(m.away.score ?? 0)"
                    print("  \(m.home.name) \(score) \(m.away.name) | \(f.string(from: m.kickoff)) local | TV: \(m.networks.joined(separator: ", "))")
                }
                if let g = groups.first {
                    print("  \(g.name): " + g.rows.map { "\($0.rank). \($0.name) \($0.points)pts" }.joined(separator: ", "))
                }
                if let id = matches.first(where: { $0.state != .pre })?.id {
                    let events = try await ScoreModel.fetchSummary(eventId: id)
                    print("  details(\(id)): \(events.count) goal/card events")
                }
                let mlb = try await ScoreModel.fetchScoreboard(league: "baseball/mlb", dates: nil)
                let nfl = try await ScoreModel.fetchScoreboard(league: "football/nfl", dates: nil)
                let nba = try await ScoreModel.fetchScoreboard(league: "basketball/nba", dates: nil)
                let nhl = try await ScoreModel.fetchScoreboard(league: "hockey/nhl", dates: nil)
                let cricket = try await ScoreModel.fetchCricket()
                print("OK: MLB \(mlb.count) · NFL \(nfl.count) · NBA \(nba.count) · NHL \(nhl.count) · cricket sections \(cricket.count)")
                if let g = mlb.first {
                    print("  ⚾️ sample: \(g.home.abbrev) v \(g.away.abbrev) | \(g.statusDetail) | TV: \(g.networks.joined(separator: ", "))")
                }
                for s in cricket {
                    let m = s.matches[0]
                    print("  🏏 \(s.title): \(m.home.name) [\(m.home.scoreText ?? "-")] v \(m.away.name) [\(m.away.scoreText ?? "-")] | \(m.statusDetail)")
                }
                if let g = nba.first ?? nhl.first {
                    print("  🏀/🏒 sample: \(g.home.abbrev) v \(g.away.abbrev) | \(g.statusDetail) | TV: \(g.networks.joined(separator: ", "))")
                }
            } catch {
                print("FAIL: \(error)")
            }
            sem.signal()
        }
        sem.wait()
        exit(0)
    }
}

// MARK: - Dashboard

enum DashboardTab: String, CaseIterable {
    case matches = "Matches"
    case groups = "Groups"
    case bracket = "Bracket"
}

struct DashboardView: View {
    @ObservedObject var model: ScoreModel
    @State private var tab: DashboardTab = .matches
    @State private var league: SportLeague = .worldCup

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)
            LeaguePicker(selected: $league)
            if league == .worldCup {
                TabBar(selected: $tab)
            }
            ScrollView {
                if league == .worldCup {
                    switch tab {
                    case .matches: MatchesTab(model: model)
                    case .groups: GroupsTab(model: model)
                    case .bracket: BracketTab(model: model)
                    }
                } else {
                    OtherLeagueView(league: league, model: model)
                }
            }
            FooterView(model: model)
        }
        .frame(width: 390, height: 620)
        .background(
            LinearGradient(colors: [Color(red: 0.05, green: 0.16, blue: 0.11),
                                    Color(red: 0.02, green: 0.07, blue: 0.10)],
                           startPoint: .top, endPoint: .bottom)
        )
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
    }
}

struct LeaguePicker: View {
    @Binding var selected: SportLeague

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SportLeague.allCases) { league in
                Button {
                    selected = league
                } label: {
                    VStack(spacing: 1) {
                        Text(league.emoji)
                            .font(.system(size: 15))
                        Text(league.label)
                            .font(.system(size: 8, weight: .bold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(selected == league ? .white.opacity(0.14) : .white.opacity(0.001),
                                in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(selected == league ? .white : .secondary)
                    .contentShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
    }
}

struct OtherLeagueView: View {
    let league: SportLeague
    @ObservedObject var model: ScoreModel

    var body: some View {
        VStack(spacing: 10) {
            if league == .cricket {
                if model.cricketSections.isEmpty {
                    emptyState("No cricket matches right now")
                }
                ForEach(model.cricketSections) { section in
                    SectionLabel(text: section.title)
                    ForEach(section.matches) { match in
                        CricketCard(match: match, model: model)
                    }
                }
            } else {
                let matches = model.matches(for: league)
                if matches.isEmpty {
                    emptyState("No \(league.label) games scheduled")
                }
                ForEach(matches) { match in
                    MatchCard(match: match, model: model, league: league)
                }
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private func emptyState(_ text: String) -> some View {
        if model.lastUpdated == nil {
            ProgressView("Loading…").padding(.vertical, 30)
        } else {
            Text(text).foregroundStyle(.secondary).padding(.vertical, 24)
        }
    }
}

struct CricketCard: View {
    let match: Match
    @ObservedObject var model: ScoreModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach([match.home, match.away], id: \.id) { side in
                let fav = model.isFavorite(.cricket, side.id)
                HStack(spacing: 8) {
                    AsyncImage(url: side.logoURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 22, height: 22)
                    .background(.white.opacity(0.9), in: Circle())
                    .clipShape(Circle())
                    Button {
                        if let url = side.siteURL { openInBrowser(url) }
                    } label: {
                        Text(side.name)
                            .font(.system(.caption, design: .rounded)
                                .weight(side.winner ? .bold : .semibold))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .disabled(side.siteURL == nil)
                    .help(side.siteURL == nil ? "" : "Open team page on ESPN")
                    Button {
                        model.toggleFavorite(.cricket, side.id)
                    } label: {
                        Image(systemName: fav ? "star.fill" : "star")
                            .font(.system(size: 8))
                            .foregroundStyle(fav ? .yellow : .secondary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Text(side.scoreText ?? "—")
                        .font(.system(size: 11, weight: side.winner ? .bold : .regular,
                                      design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            Divider().overlay(.white.opacity(0.08))
            HStack(spacing: 6) {
                if match.isLive {
                    let detail = match.statusDetail.lowercased() == "live" ? "" : match.statusDetail
                    HStack(spacing: 4) {
                        PulsingDot()
                        Text("LIVE\(detail.isEmpty ? "" : " · \(detail)")")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.red)
                    }
                } else if match.state == .post {
                    Text(match.statusDetail.isEmpty ? "Result" : match.statusDetail)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text(match.kickoff, format: .dateTime.weekday(.abbreviated).hour().minute())
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.yellow)
                }
                if !match.venue.isEmpty {
                    Text(match.venue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if let url = match.gamecastURL {
                    Button {
                        openInBrowser(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square")
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Open scorecard")
                }
            }
        }
        .padding(12)
        .background(.white.opacity(match.isLive ? 0.1 : 0.06),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(match.isLive ? Color.red.opacity(0.5) : .white.opacity(0.08),
                              lineWidth: 1)
        )
    }
}

struct TabBar: View {
    @Binding var selected: DashboardTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(DashboardTab.allCases, id: \.self) { tab in
                Button {
                    selected = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(selected == tab ? .white.opacity(0.14) : .white.opacity(0.001),
                                    in: Capsule())
                        .foregroundStyle(selected == tab ? .white : .secondary)
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

struct HeaderView: View {
    @ObservedObject var model: ScoreModel
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 10) {
            Text("🏆")
                .font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text("World Cup 2026")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Text(Date().formatted(date: .complete, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                showSettings.toggle()
            } label: {
                Image(systemName: "gearshape.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Settings")
            .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                SettingsView(model: model)
            }
            Button {
                Task { await model.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Refresh now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.05))
    }
}

struct SettingsView: View {
    @ObservedObject var model: ScoreModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Menu Bar Alerts")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
            Toggle("Goal alerts (flash in menu bar)", isOn: $model.goalAlertsEnabled)
            Toggle("Kickoff countdown (last 10 min)", isOn: $model.countdownAlertEnabled)
            Divider()
            Toggle("Show recent form on upcoming matches", isOn: $model.showFormGuide)
            Text("Star a team on any match card to follow it — its games get priority in the menu bar.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .toggleStyle(.checkbox)
        .font(.caption)
        .padding(14)
        .frame(width: 280)
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
        .modifier(DarkPopoverBackground())
    }
}

private struct DarkPopoverBackground: ViewModifier {
    private let color = Color(red: 0.05, green: 0.13, blue: 0.10)

    func body(content: Content) -> some View {
        if #available(macOS 13.3, *) {
            // Tints the whole popover, arrow included
            content.presentationBackground(color)
        } else {
            content.background(color)
        }
    }
}

// MARK: - Matches tab

struct MatchesTab: View {
    @ObservedObject var model: ScoreModel

    var body: some View {
        VStack(spacing: 10) {
            if !model.liveMatches.isEmpty {
                OnAirBanner(matches: model.liveMatches)
            } else if let next = model.nextMatch {
                CountdownBanner(match: next)
            }
            if let error = model.errorMessage {
                Label(error, systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            if model.todayMatches.isEmpty && model.errorMessage == nil {
                if model.lastUpdated == nil {
                    ProgressView("Loading matches…")
                        .padding(.vertical, 30)
                } else {
                    Text("No matches today")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 20)
                }
            }
            ForEach(model.todayMatches) { match in
                MatchCard(match: match, model: model)
            }
            if !model.tomorrowMatches.isEmpty {
                SectionLabel(text: "Tomorrow")
                ForEach(model.tomorrowMatches) { match in
                    CompactRow(match: match, model: model)
                }
            }
        }
        .padding(12)
    }
}

struct OnAirBanner: View {
    let matches: [Match]

    private var networks: [String] {
        var seen = Set<String>()
        return matches.flatMap(\.networks).filter { seen.insert($0).inserted }
    }

    var body: some View {
        HStack(spacing: 8) {
            PulsingDot()
            Text(matches.count == 1 ? "LIVE NOW" : "\(matches.count) MATCHES LIVE")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundStyle(.red)
            if !networks.isEmpty {
                Image(systemName: "tv.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(networks.joined(separator: " · "))
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.red.opacity(0.35), lineWidth: 1))
    }
}

struct CountdownBanner: View {
    let match: Match

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = match.kickoff.timeIntervalSince(context.date)
            let soon = remaining <= 600
            HStack(spacing: 8) {
                Image(systemName: soon ? "bell.badge.fill" : "clock.fill")
                    .foregroundStyle(soon ? .red : .yellow)
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(match.home.name) vs \(match.away.name)")
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    Text(soon ? "Starting soon — get to a screen!" : "Next kickoff")
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

// MARK: - Match card

struct MatchCard: View {
    let match: Match
    @ObservedObject var model: ScoreModel
    var league: SportLeague = .worldCup
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                TeamColumn(side: match.home,
                           dim: match.state == .post && !match.home.winner && match.away.winner,
                           showForm: model.showFormGuide && match.state == .pre,
                           league: league,
                           model: model)
                Spacer(minLength: 4)
                centerColumn
                Spacer(minLength: 4)
                TeamColumn(side: match.away,
                           dim: match.state == .post && !match.away.winner && match.home.winner,
                           showForm: model.showFormGuide && match.state == .pre,
                           league: league,
                           model: model)
            }
            Divider().overlay(.white.opacity(0.08))
            HStack(spacing: 6) {
                statusChip
                if !match.venue.isEmpty {
                    Text("\(match.venue)\(match.city.isEmpty ? "" : " · \(match.city)")")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                actionButtons
            }
            if !match.networks.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "tv.fill")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(match.networks, id: \.self) { network in
                        Text(network)
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.1), in: Capsule())
                    }
                    Spacer()
                }
            }
            if expanded {
                DetailsList(match: match, model: model)
            }
        }
        .padding(12)
        .background(.white.opacity(match.isLive ? 0.1 : 0.06),
                    in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: 1)
        )
    }

    private var borderColor: Color {
        if match.isLive { return .red.opacity(0.5) }
        if model.isFavoriteMatch(match, league: league) { return .yellow.opacity(0.4) }
        return .white.opacity(0.08)
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 10) {
            if match.state == .pre, league == .worldCup {
                Button {
                    addToCalendar()
                } label: {
                    Image(systemName: "calendar.badge.plus")
                }
                .help("Add to Calendar")
            }
            if let url = match.gamecastURL {
                Button {
                    openInBrowser(url)
                } label: {
                    Image(systemName: "arrow.up.right.square")
                }
                .help("Open ESPN Gamecast")
            }
            if match.state != .pre, league == .worldCup {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                    if expanded {
                        Task { await model.loadDetails(for: match.id) }
                    }
                } label: {
                    Image(systemName: expanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                }
                .help("Goals & cards")
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func addToCalendar() {
        let ics = CalendarExport.icsString(for: match)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wc26-\(match.id).ics")
        do {
            try ics.write(to: url, atomically: true, encoding: .utf8)
            openInBrowser(url)
        } catch {
            NSSound.beep()
        }
    }

    @ViewBuilder
    private var centerColumn: some View {
        VStack(spacing: 2) {
            switch match.state {
            case .pre:
                if !Calendar.current.isDateInToday(match.kickoff) {
                    Text(match.kickoff, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Text(match.kickoff, style: .time)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                Text(league == .worldCup ? "Kickoff" : "Start")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .live, .post:
                Text("\(match.home.score ?? 0) – \(match.away.score ?? 0)")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .monospacedDigit()
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var statusChip: some View {
        switch match.state {
        case .live:
            let detail = match.statusDetail.lowercased() == "live" ? "" : match.statusDetail
            HStack(spacing: 4) {
                PulsingDot()
                Text(league == .worldCup ? "LIVE \(match.clock)"
                     : "LIVE\(detail.isEmpty ? "" : " · \(detail)")")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.red.opacity(0.15), in: Capsule())
        case .post:
            Text(league == .worldCup ? "FT"
                 : (match.statusDetail.isEmpty ? "Final" : match.statusDetail))
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.white.opacity(0.1), in: Capsule())
        case .pre:
            Text("UPCOMING")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.yellow)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.yellow.opacity(0.12), in: Capsule())
        }
    }
}

struct DetailsList: View {
    let match: Match
    @ObservedObject var model: ScoreModel

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let events = model.matchDetails[match.id] {
                if events.isEmpty {
                    Text("No goals or cards yet")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(events) { event in
                        HStack(spacing: 6) {
                            Text(event.minute)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 38, alignment: .trailing)
                            Text(event.kind.emoji)
                                .font(.caption2)
                            Text(event.player)
                                .font(.system(.caption2, design: .rounded).weight(
                                    event.kind == .goal || event.kind == .penalty || event.kind == .ownGoal
                                        ? .bold : .regular))
                            if !event.kind.label.isEmpty {
                                Text(event.kind.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(event.teamId == match.home.id ? match.home.abbrev : match.away.abbrev)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct TeamColumn: View {
    let side: TeamSide
    let dim: Bool
    var showForm: Bool = false
    var league: SportLeague = .worldCup
    @ObservedObject var model: ScoreModel

    private var isFavorite: Bool { model.isFavorite(league, side.id) }

    var body: some View {
        VStack(spacing: 5) {
            AsyncImage(url: side.logoURL) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFit()
                } else {
                    Text(side.abbrev)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.black.opacity(0.6))
                }
            }
            .frame(width: 40, height: 40)
            .background(.white.opacity(0.9), in: Circle())
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(
                isFavorite ? .yellow.opacity(0.8) : .white.opacity(0.25),
                lineWidth: isFavorite ? 1.5 : 1))
            HStack(spacing: 3) {
                Button {
                    if let url = side.siteURL { openInBrowser(url) }
                } label: {
                    Text(side.name)
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .buttonStyle(.plain)
                .disabled(side.siteURL == nil)
                .help(side.siteURL == nil ? "" : "Open team page on ESPN")
                Button {
                    model.toggleFavorite(league, side.id)
                } label: {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 8))
                        .foregroundStyle(isFavorite ? .yellow : .secondary.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help(isFavorite ? "Unfollow" : "Follow team")
            }
            if showForm, let form = side.form, !form.isEmpty {
                FormDots(form: form)
            }
        }
        .frame(width: 104)
        .opacity(dim ? 0.55 : 1)
    }
}

struct FormDots: View {
    let form: String   // e.g. "WWDLD", most recent first

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(form.prefix(5).enumerated()), id: \.offset) { _, ch in
                Circle()
                    .fill(color(for: ch))
                    .frame(width: 5, height: 5)
            }
        }
        .help("Recent form (latest first): \(form)")
    }

    private func color(for ch: Character) -> Color {
        switch ch {
        case "W": return .green
        case "L": return .red
        default: return .gray
        }
    }
}

struct PulsingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(.red)
            .frame(width: 6, height: 6)
            .opacity(pulsing ? 0.3 : 1)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulsing)
            .onAppear { pulsing = true }
    }
}

struct SectionLabel: View {
    let text: String

    var body: some View {
        HStack {
            Text(text.uppercased())
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
                .tracking(1.2)
            VStack { Divider().overlay(.white.opacity(0.1)) }
        }
        .padding(.top, 6)
    }
}

struct CompactRow: View {
    let match: Match
    @ObservedObject var model: ScoreModel

    var body: some View {
        HStack(spacing: 8) {
            if model.isFavoriteMatch(match) {
                Image(systemName: "star.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(.yellow)
            }
            Text("\(match.home.abbrev) v \(match.away.abbrev)")
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .frame(width: 90, alignment: .leading)
            if match.state == .pre {
                Text(match.kickoff, format: .dateTime.weekday(.abbreviated).hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("\(match.home.score ?? 0)–\(match.away.score ?? 0)\(match.isLive ? " · \(match.clock)" : "")")
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundStyle(match.isLive ? .red : .primary)
            }
            Spacer()
            if !match.networks.isEmpty {
                Text(match.networks.prefix(2).joined(separator: " · "))
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Groups tab

struct GroupsTab: View {
    @ObservedObject var model: ScoreModel

    var body: some View {
        VStack(spacing: 10) {
            if model.groups.isEmpty {
                ProgressView("Loading standings…")
                    .padding(.vertical, 30)
            }
            ForEach(model.groups) { group in
                GroupCard(group: group, model: model)
            }
        }
        .padding(12)
    }
}

struct GroupCard: View {
    let group: GroupTable
    @ObservedObject var model: ScoreModel

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(group.name)
                    .font(.system(.caption, design: .rounded).weight(.bold))
                Spacer()
                Text("P    W   D   L    GD   Pts")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            ForEach(group.rows) { row in
                let isFavorite = model.isFavorite(.worldCup, row.id)
                HStack(spacing: 6) {
                    Text("\(row.rank)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(row.rank <= 2 ? .green : .secondary)
                        .frame(width: 10)
                    AsyncImage(url: row.logoURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Color.clear
                        }
                    }
                    .frame(width: 16, height: 16)
                    .background(.white.opacity(0.85), in: Circle())
                    .clipShape(Circle())
                    Text(row.name)
                        .font(.system(.caption2, design: .rounded)
                            .weight(isFavorite ? .bold : .regular))
                        .foregroundStyle(isFavorite ? .yellow : .primary)
                        .lineLimit(1)
                    Spacer()
                    Text(String(format: "%2d  %2d  %2d  %2d  %4@  %3d",
                                row.played, row.wins, row.draws, row.losses,
                                row.goalDiff as NSString, row.points))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(10)
        .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Bracket tab

struct BracketTab: View {
    @ObservedObject var model: ScoreModel

    var body: some View {
        VStack(spacing: 8) {
            if model.bracket.isEmpty {
                ProgressView("Loading bracket…")
                    .padding(.vertical, 30)
            } else {
                Text("Road to the Final · July 19")
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                ForEach(model.bracket) { round in
                    SectionLabel(text: round.title)
                    ForEach(round.matches) { match in
                        BracketRow(match: match)
                    }
                }
            }
        }
        .padding(12)
    }
}

struct BracketRow: View {
    let match: Match

    var body: some View {
        HStack(spacing: 8) {
            Text(teamLabel(match.home))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .frame(width: 105, alignment: .trailing)
                .lineLimit(1)
            Group {
                if match.state == .pre {
                    Text(match.kickoff, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.system(size: 9, design: .rounded))
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(match.home.score ?? 0)–\(match.away.score ?? 0)")
                        .font(.system(.caption2, design: .rounded).weight(.bold))
                        .foregroundStyle(match.isLive ? .red : .primary)
                }
            }
            .frame(width: 92)
            Text(teamLabel(match.away))
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .frame(width: 105, alignment: .leading)
                .lineLimit(1)
        }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
    }

    private func teamLabel(_ side: TeamSide) -> String {
        // Placeholder names like "2A" mean the slot isn't decided yet
        side.name.count <= 3 ? "TBD (\(side.name))" : side.name
    }
}

// MARK: - Footer

struct FooterView: View {
    @ObservedObject var model: ScoreModel
    @State private var launchAtLogin = (SMAppService.mainApp.status == .enabled)

    var body: some View {
        HStack(spacing: 10) {
            if let updated = model.lastUpdated {
                Text("Updated \(updated.formatted(date: .omitted, time: .shortened)) · ESPN")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("Start at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption2)
                .onChange(of: launchAtLogin) { enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                    } catch {
                        launchAtLogin = (SMAppService.mainApp.status == .enabled)
                    }
                }
            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Quit WorldCup26")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.white.opacity(0.05))
    }
}
