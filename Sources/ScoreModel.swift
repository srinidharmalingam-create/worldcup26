import Foundation

@MainActor
final class ScoreModel: ObservableObject {
    @Published var leagueMatches: [SportLeague: [Match]] = [:]
    @Published var cricketSections: [LeagueSection] = []
    @Published var usStandings: [SportLeague: [USTable]] = [:]
    @Published var winProb: [String: Double] = [:]
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var scoreAlert: ScoreAlert?

    // Keys are "<league>:<teamId>" so ids can't collide across sports.
    @Published var favorites: Set<String> {
        didSet { UserDefaults.standard.set(Array(favorites), forKey: "favoriteTeamIDs") }
    }
    @Published var scoreAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(scoreAlertsEnabled, forKey: "goalAlertsEnabled") }
    }
    @Published var countdownAlertEnabled: Bool {
        didSet { UserDefaults.standard.set(countdownAlertEnabled, forKey: "countdownAlertEnabled") }
    }
    @Published var hiddenLeagues: Set<String> {
        didSet { UserDefaults.standard.set(Array(hiddenLeagues), forKey: "hiddenLeagues") }
    }

    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var standingsLoading: Set<SportLeague> = []
    private var previousScores: [String: (Int, Int)] = [:]

    init(startPolling: Bool = true) {
        let defaults = UserDefaults.standard
        // Drop stale World Cup favorites — that league is no longer carried.
        favorites = Set((defaults.stringArray(forKey: "favoriteTeamIDs") ?? [])
            .filter { $0.contains(":") && !$0.hasPrefix("worldCup:") })
        scoreAlertsEnabled = defaults.object(forKey: "goalAlertsEnabled") as? Bool ?? true
        countdownAlertEnabled = defaults.object(forKey: "countdownAlertEnabled") as? Bool ?? true
        hiddenLeagues = Set(defaults.stringArray(forKey: "hiddenLeagues") ?? [])

        guard startPolling else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let live = await MainActor.run { self?.anyLive ?? false }
                let seconds: UInt64 = live ? 45 : 120
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }
        }
        // Re-render the menu bar label every 30s so the countdown and
        // score-alert expiry stay current between polls.
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                await MainActor.run { self?.objectWillChange.send() }
            }
        }
    }

    // MARK: - Refresh

    func refresh() async {
        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.dateFormat = "yyyyMMdd"
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let tomorrowStr = dayFormatter.string(from: tomorrow)

        async let cricketFetch = Self.fetchCricket()

        var fetched: [SportLeague: [Match]] = [:]
        var failures = 0
        await withTaskGroup(of: (SportLeague, [Match])?.self) { group in
            for league in SportLeague.allCases {
                guard let path = league.apiPath else { continue }
                let alsoTomorrow = league.fetchesTomorrow
                group.addTask {
                    do {
                        let matches = alsoTomorrow
                            ? try await Self.fetchDayPlusTomorrow(league: path, tomorrow: tomorrowStr)
                            : try await Self.fetchScoreboard(league: path, dates: nil)
                        return (league, matches)
                    } catch {
                        return nil
                    }
                }
            }
            for await result in group {
                if let (league, matches) = result {
                    fetched[league] = matches
                } else {
                    failures += 1
                }
            }
        }

        // Keep the previous slate for any league that failed this cycle.
        for (league, matches) in fetched {
            detectScoreChanges(league, matches)
            leagueMatches[league] = matches
        }
        if let cricket = try? await cricketFetch {
            cricketSections = cricket
        }

        lastUpdated = Date()
        errorMessage = fetched.isEmpty && failures > 0
            ? "Couldn't reach ESPN — retrying shortly."
            : nil
    }

    /// Standings are only fetched when a Standings tab is actually opened.
    func loadStandings(for league: SportLeague) async {
        guard league.hasStandings, usStandings[league] == nil,
              !standingsLoading.contains(league), let path = league.apiPath else { return }
        standingsLoading.insert(league)
        defer { standingsLoading.remove(league) }
        if let tables = try? await Self.fetchStandings(path: path) {
            usStandings[league] = tables
        } else {
            usStandings[league] = []
        }
    }

    func loadWinProb(league: SportLeague, matchId: String) async {
        guard let path = league.apiPath, winProb[matchId] == nil else { return }
        let url = "https://site.api.espn.com/apis/site/v2/sports/\(path)/summary?event=\(matchId)"
        guard let pct = try? await Self.getWinProb(url) else { return }
        winProb[matchId] = pct
    }

    // MARK: - Favorites & visibility

    static func favKey(_ league: SportLeague, _ teamId: String) -> String {
        "\(league.rawValue):\(teamId)"
    }

    func isFavorite(_ league: SportLeague, _ teamId: String) -> Bool {
        favorites.contains(Self.favKey(league, teamId))
    }

    func toggleFavorite(_ league: SportLeague, _ teamId: String) {
        let key = Self.favKey(league, teamId)
        if favorites.contains(key) {
            favorites.remove(key)
        } else {
            favorites.insert(key)
        }
    }

    func isFavoriteMatch(_ match: Match, league: SportLeague) -> Bool {
        isFavorite(league, match.home.id) || isFavorite(league, match.away.id)
    }

    var visibleLeagues: [SportLeague] {
        let shown = SportLeague.allCases.filter { !hiddenLeagues.contains($0.rawValue) }
        // Never leave the picker empty.
        return shown.isEmpty ? SportLeague.allCases : shown
    }

    func isHidden(_ league: SportLeague) -> Bool {
        hiddenLeagues.contains(league.rawValue)
    }

    func setHidden(_ league: SportLeague, _ hidden: Bool) {
        if hidden { hiddenLeagues.insert(league.rawValue) }
        else { hiddenLeagues.remove(league.rawValue) }
    }

    // MARK: - Score alerts (menu bar)

    private func detectScoreChanges(_ league: SportLeague, _ matches: [Match]) {
        for match in matches where match.state != .pre {
            guard let h = match.home.score, let a = match.away.score else { continue }
            if let (prevH, prevA) = previousScores[match.id], h + a > prevH + prevA,
               !isHidden(league) {
                let scorer = h > prevH ? match.home : match.away
                let detail = match.statusDetail.isEmpty ? match.clock : match.statusDetail
                scoreAlert = ScoreAlert(
                    text: "\(league.emoji) \(scorer.abbrev) scores! \(match.home.abbrev) \(h)–\(a) \(match.away.abbrev)"
                        + (detail.isEmpty ? "" : " · \(detail)"),
                    at: Date())
            }
            previousScores[match.id] = (h, a)
        }
    }

    // MARK: - Derived state

    func matches(for league: SportLeague) -> [Match] {
        league == .cricket ? cricketSections.flatMap(\.matches) : (leagueMatches[league] ?? [])
    }

    private var visibleGames: [(SportLeague, Match)] {
        visibleLeagues.flatMap { league in matches(for: league).map { (league, $0) } }
    }

    var anyLive: Bool {
        visibleGames.contains { $0.1.isLive }
    }

    /// Live game to headline the menu bar — a starred team wins the slot.
    private var headlineLive: (SportLeague, Match)? {
        let live = visibleGames.filter { $0.1.isLive }
        return live.first { isFavoriteMatch($0.1, league: $0.0) } ?? live.first
    }

    private var nextGame: (SportLeague, Match)? {
        let now = Date()
        let upcoming = visibleGames.filter { $0.1.state == .pre && $0.1.kickoff > now }
        return upcoming.first { isFavoriteMatch($0.1, league: $0.0) && $0.1.kickoff.timeIntervalSince(now) < 3600 }
            ?? upcoming.min { $0.1.kickoff < $1.1.kickoff }
    }

    var liveCount: Int {
        visibleGames.filter { $0.1.isLive }.count
    }

    var menuTitle: String {
        if scoreAlertsEnabled, let alert = scoreAlert,
           Date().timeIntervalSince(alert.at) < 180 {
            return alert.text
        }
        if let (league, m) = headlineLive {
            if league == .cricket {
                return "🏏 \(m.home.abbrev) v \(m.away.abbrev) · \(m.statusDetail.isEmpty ? "Live" : m.statusDetail)"
            }
            var title = "\(league.emoji) \(m.home.abbrev) \(m.home.score ?? 0)–\(m.away.score ?? 0) \(m.away.abbrev)"
            if !m.statusDetail.isEmpty { title += " \(m.statusDetail)" }
            let extra = liveCount - 1
            if extra > 0 { title += " +\(extra)" }
            return title
        }
        if let (league, m) = nextGame {
            let remaining = m.kickoff.timeIntervalSince(Date())
            if countdownAlertEnabled, remaining <= 600 {
                let minutes = max(1, Int(remaining / 60))
                return "🔔 \(m.home.abbrev)–\(m.away.abbrev) in \(minutes)m"
            }
            let f = DateFormatter()
            f.timeStyle = .short
            return "\(league.emoji) \(m.home.abbrev)–\(m.away.abbrev) \(f.string(from: m.kickoff))"
        }
        return "🥎 Matchday"
    }

    /// Cross-sport TV guide: live games plus everything else starting today.
    var guideEntries: [GuideEntry] {
        let cal = Calendar.current
        return visibleGames
            .filter { $0.1.state != .post && ($0.1.isLive || cal.isDateInToday($0.1.kickoff)) }
            .map { GuideEntry(league: $0.0, match: $0.1) }
            .sorted { ($0.match.isLive ? 0 : 1, $0.match.kickoff) < ($1.match.isLive ? 0 : 1, $1.match.kickoff) }
    }

    /// Every live/upcoming game involving a starred team, across all leagues.
    var myTeamEntries: [GuideEntry] {
        visibleGames
            .filter { isFavoriteMatch($0.1, league: $0.0) }
            .map { GuideEntry(league: $0.0, match: $0.1) }
            .sorted { ($0.match.isLive ? 0 : 1, $0.match.kickoff) < ($1.match.isLive ? 0 : 1, $1.match.kickoff) }
    }

    // MARK: - Fetching

    nonisolated private static func getJSON<T: Decodable>(_ urlString: String, as type: T.Type) async throws -> T {
        let (data, _) = try await URLSession.shared.data(from: URL(string: urlString)!)
        return try JSONDecoder().decode(T.self, from: data)
    }

    nonisolated static func fetchScoreboard(league: String, dates: String?) async throws -> [Match] {
        var urlString = "https://site.api.espn.com/apis/site/v2/sports/\(league)/scoreboard"
        if let dates { urlString += "?dates=\(dates)" }
        let board = try await getJSON(urlString, as: Scoreboard.self)
        return board.events.compactMap(Self.match(from:))
            .sorted { ($0.isLive ? 0 : 1, $0.kickoff) < ($1.isLive ? 0 : 1, $1.kickoff) }
    }

    nonisolated static func fetchDayPlusTomorrow(league: String, tomorrow: String) async throws -> [Match] {
        async let today = fetchScoreboard(league: league, dates: nil)
        async let next = fetchScoreboard(league: league, dates: tomorrow)
        let (t, n) = try await (today, next)
        let ids = Set(t.map(\.id))
        return (t + n.filter { !ids.contains($0.id) })
            .sorted { ($0.isLive ? 0 : 1, $0.kickoff) < ($1.isLive ? 0 : 1, $1.kickoff) }
    }

    nonisolated static func fetchCricket() async throws -> [LeagueSection] {
        let header = try await getJSON(
            "https://site.web.api.espn.com/apis/personalized/v2/scoreboard/header?sport=cricket",
            as: CricketHeader.self)
        let leagues = (header.sports ?? []).flatMap { $0.leagues ?? [] }
            .filter { !($0.events ?? []).isEmpty && $0.id != nil }

        func priority(_ name: String) -> Int {
            let n = name.lowercased()
            if n.contains("icc") || n.contains("world cup") || n.contains("world test") { return 0 }
            if n.contains("test") || n.contains("odi") || n.contains("t20i")
                || n.contains("tour") || n.contains("tri-series") || n.contains("trophy") { return 1 }
            if n.contains("county") || n.contains("big bash") || n.contains("hundred")
                || n.contains("ipl") || n.contains("super smash") { return 2 }
            return 3
        }

        let picked = leagues
            .sorted { priority($0.name ?? "") < priority($1.name ?? "") }
            .prefix(5)

        var sections: [LeagueSection] = []
        for league in picked {
            guard let id = league.id else { continue }
            let url = "https://site.api.espn.com/apis/site/v2/sports/cricket/\(id)/scoreboard"
            let board: Scoreboard
            do {
                board = try await getJSON(url, as: Scoreboard.self)
            } catch {
                continue
            }
            let matches = board.events.compactMap(Self.match(from:))
                .sorted { ($0.isLive ? 0 : 1, $0.kickoff) < ($1.isLive ? 0 : 1, $1.kickoff) }
            if !matches.isEmpty {
                sections.append(LeagueSection(
                    title: board.leagues?.first?.name ?? league.name ?? "Cricket",
                    matches: matches))
            }
        }
        return sections
    }

    nonisolated static func fetchStandings(path: String) async throws -> [USTable] {
        let url = "https://site.api.espn.com/apis/v2/sports/\(path)/standings"
        let response = try await getJSON(url, as: StandingsResponse.self)
        return (response.children ?? []).compactMap { group -> USTable? in
            guard let name = group.name, let entries = group.standings?.entries else { return nil }
            let rows = entries.map { entry -> USRow in
                func stat(_ key: String) -> SBStat? {
                    entry.stats.first { $0.name == key }
                }
                return USRow(id: entry.team.id ?? UUID().uuidString,
                             name: entry.team.displayName ?? "—",
                             logoURL: entry.team.logos?.first?.href.flatMap(URL.init(string:)),
                             wins: Int(stat("wins")?.value ?? 0),
                             losses: Int(stat("losses")?.value ?? 0),
                             pct: stat("winPercent")?.displayValue ?? "—",
                             gamesBehind: stat("gamesBehind")?.displayValue ?? "—")
            }
            .sorted { (Double($0.pct) ?? 0, $0.wins) > (Double($1.pct) ?? 0, $1.wins) }
            return USTable(name: name, rows: rows)
        }
    }

    nonisolated private static func getWinProb(_ url: String) async throws -> Double? {
        let response = try await getJSON(url, as: WinProbResponse.self)
        return response.winprobability?.last?.homeWinPercentage
    }

    nonisolated static func match(from event: SBEvent) -> Match? {
        guard let comp = event.competitions.first,
              let kickoff = ESPNDate.parse(event.date),
              comp.competitors.count >= 2
        else { return nil }

        let homeC = comp.competitors.first { $0.homeAway == "home" } ?? comp.competitors[0]
        let awayC = comp.competitors.first { $0.homeAway == "away" } ?? comp.competitors[1]

        func side(_ c: SBCompetitor) -> TeamSide {
            let site = (c.team.links?.first { $0.rel?.contains("clubhouse") == true }
                        ?? c.team.links?.first)?.href.flatMap(URL.init(string:))
            // Some leagues (NCAA softball) return a generic placeholder crest;
            // fall back to the abbreviation rather than showing a blank disc.
            let logo = c.team.logo.flatMap { $0.hasSuffix("/logos/default.png") ? nil : $0 }
            return TeamSide(id: c.team.id ?? c.team.displayName,
                            name: c.team.displayName,
                            abbrev: c.team.abbreviation ?? String(c.team.displayName.prefix(3)).uppercased(),
                            score: c.score.flatMap(Int.init),
                            scoreText: c.score?.isEmpty == false ? c.score : nil,
                            logoURL: logo.flatMap(URL.init(string:)),
                            winner: c.winner ?? false,
                            form: c.form,
                            siteURL: site,
                            periods: (c.linescores ?? []).compactMap { $0.value }.map { Int($0) })
        }

        let state: MatchState
        switch comp.status.type.state {
        case "in": state = .live
        case "post": state = .post
        default: state = .pre
        }

        let networks = NetworkNames.clean(comp.broadcasts?.flatMap { $0.names ?? [] } ?? [])
        let gamecast = event.links?.first { $0.rel?.contains("summary") == true }?.href
            .flatMap(URL.init(string:))

        return Match(id: event.id,
                     kickoff: kickoff,
                     home: side(homeC),
                     away: side(awayC),
                     state: state,
                     clock: comp.status.displayClock ?? "",
                     statusDetail: comp.status.type.shortDetail ?? "",
                     venue: comp.venue?.fullName ?? "",
                     city: comp.venue?.address?.city ?? "",
                     networks: networks,
                     gamecastURL: gamecast)
    }
}

// MARK: - Calendar export

enum CalendarExport {
    static func icsString(for match: Match, league: SportLeague) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let start = f.string(from: match.kickoff)
        let end = f.string(from: match.kickoff.addingTimeInterval(3 * 3600))
        let tv = match.networks.isEmpty ? "" : "TV: \(match.networks.joined(separator: "\\, "))"
        let location = [match.venue, match.city].filter { !$0.isEmpty }
            .joined(separator: "\\, ")
        return """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Matchday//EN
        BEGIN:VEVENT
        UID:matchday-\(match.id)@matchday.local
        DTSTAMP:\(start)
        DTSTART:\(start)
        DTEND:\(end)
        SUMMARY:\(league.emoji) \(match.home.name) vs \(match.away.name)
        LOCATION:\(location)
        DESCRIPTION:\(tv)
        BEGIN:VALARM
        TRIGGER:-PT10M
        ACTION:DISPLAY
        DESCRIPTION:Starts in 10 minutes
        END:VALARM
        END:VEVENT
        END:VCALENDAR
        """
    }
}
