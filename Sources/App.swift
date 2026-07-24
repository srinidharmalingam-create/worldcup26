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
struct MatchdayApp: App {
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
            let f = DateFormatter()
            f.dateStyle = .medium
            f.timeStyle = .short
            for league in SportLeague.allCases {
                guard let path = league.apiPath else { continue }
                do {
                    let games = try await ScoreModel.fetchScoreboard(league: path, dates: nil)
                    print("OK \(league.emoji) \(league.label): \(games.count) games")
                    if let g = games.first {
                        let score = g.state == .pre ? "vs" : "\(g.home.score ?? 0)-\(g.away.score ?? 0)"
                        print("   \(g.home.name) \(score) \(g.away.name) | \(f.string(from: g.kickoff)) local"
                              + " | \(g.statusDetail) | TV: \(g.networks.joined(separator: ", "))")
                    }
                    if league.hasStandings {
                        let tables = try await ScoreModel.fetchStandings(path: path)
                        let rows = tables.first?.rows.prefix(2).map { "\($0.name) \($0.wins)-\($0.losses)" } ?? []
                        print("   standings: \(tables.count) table(s) — \(rows.joined(separator: ", "))")
                    }
                } catch {
                    print("FAIL \(league.label): \(error)")
                }
            }
            do {
                let cricket = try await ScoreModel.fetchCricket()
                print("OK 🏏 Cricket: \(cricket.count) series")
                for s in cricket.prefix(3) {
                    let m = s.matches[0]
                    print("   \(s.title): \(m.home.name) [\(m.home.scoreText ?? "-")] v \(m.away.name) [\(m.away.scoreText ?? "-")] | \(m.statusDetail)")
                }
            } catch {
                print("FAIL cricket: \(error)")
            }
            sem.signal()
        }
        sem.wait()
        exit(0)
    }
}

// MARK: - Dashboard

struct DashboardView: View {
    @ObservedObject var model: ScoreModel
    @State private var mainTab: MainTab = .guide

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(model: model)
            TopPicker(selected: $mainTab, model: model)
            ScrollView {
                VStack(spacing: 10) {
                    if let error = model.errorMessage {
                        Label(error, systemImage: "wifi.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                    }
                    switch mainTab {
                    case .guide:
                        GuideView(model: model)
                    case .mine:
                        MyTeamsView(model: model)
                    case .league(let league):
                        LeagueView(league: league, model: model)
                    }
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
        .onChange(of: model.hiddenLeagues) { _ in
            // Don't strand the user on a league they just hid.
            if case .league(let l) = mainTab, model.isHidden(l) {
                mainTab = .guide
            }
        }
    }
}

struct LeagueView: View {
    let league: SportLeague
    @ObservedObject var model: ScoreModel
    @State private var showStandings = false

    var body: some View {
        VStack(spacing: 10) {
            if league.hasStandings {
                HStack(spacing: 4) {
                    subTab("Games", active: !showStandings) { showStandings = false }
                    subTab("Standings", active: showStandings) { showStandings = true }
                }
            }
            if showStandings && league.hasStandings {
                StandingsView(league: league, model: model)
            } else if league == .cricket {
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
                let games = model.matches(for: league)
                if games.isEmpty {
                    emptyState("No \(league.label) games scheduled")
                }
                ForEach(games) { match in
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

    private func subTab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(active ? .white.opacity(0.14) : .white.opacity(0.001), in: Capsule())
                .foregroundStyle(active ? .white : .secondary)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct HeaderView: View {
    @ObservedObject var model: ScoreModel
    @State private var showSettings = false

    var body: some View {
        HStack(spacing: 10) {
            Text("🥎")
                .font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text("Matchday")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                Text(Date().formatted(date: .complete, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let path = Bundle.main.path(forResource: "dog", ofType: "jpg"),
               let nsImage = NSImage(contentsOfFile: path) {
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            }
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
            Toggle("Score alerts (flash in menu bar)", isOn: $model.scoreAlertsEnabled)
            Toggle("Start countdown (last 10 min)", isOn: $model.countdownAlertEnabled)
            Divider()
            Text("Leagues")
                .font(.system(.caption, design: .rounded).weight(.bold))
                .foregroundStyle(.secondary)
            ForEach(SportLeague.allCases) { league in
                Toggle("\(league.emoji) \(league.label)", isOn: Binding(
                    get: { !model.isHidden(league) },
                    set: { model.setHidden(league, !$0) }))
            }
            Text("Star a team on any game card to follow it — its games get priority in the menu bar.")
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

// MARK: - Game card

struct MatchCard: View {
    let match: Match
    @ObservedObject var model: ScoreModel
    var league: SportLeague
    @State private var expanded = false

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                TeamColumn(side: match.home,
                           dim: match.state == .post && !match.home.winner && match.away.winner,
                           league: league,
                           model: model)
                Spacer(minLength: 4)
                centerColumn
                Spacer(minLength: 4)
                TeamColumn(side: match.away,
                           dim: match.state == .post && !match.away.winner && match.home.winner,
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
                BoxScoreView(match: match, league: league, model: model)
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

    private var hasBoxScore: Bool {
        !match.home.periods.isEmpty || !match.away.periods.isEmpty
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 10) {
            if match.state == .pre {
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
            if match.state != .pre, hasBoxScore {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    Image(systemName: expanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                }
                .help("Box score")
            }
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func addToCalendar() {
        let ics = CalendarExport.icsString(for: match, league: league)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("matchday-\(match.id).ics")
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
                Text("Start")
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
                Text("LIVE\(detail.isEmpty ? "" : " · \(detail)")")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(.red)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.red.opacity(0.15), in: Capsule())
        case .post:
            Text(match.statusDetail.isEmpty ? "Final" : match.statusDetail)
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

struct TeamColumn: View {
    let side: TeamSide
    let dim: Bool
    var league: SportLeague
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
            .contentShape(Circle())
            .onTapGesture {
                if let url = side.siteURL { openInBrowser(url) }
            }
            .help(side.siteURL == nil ? "" : "Open team page on ESPN")
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
        }
        .frame(width: 104)
        .opacity(dim ? 0.55 : 1)
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

// MARK: - Shared bits

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
            .help("Quit Matchday")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.white.opacity(0.05))
    }
}
