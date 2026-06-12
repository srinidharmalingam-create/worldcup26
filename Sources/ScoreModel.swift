import Foundation

@MainActor
final class ScoreModel: ObservableObject {
    @Published var todayMatches: [Match] = []
    @Published var tomorrowMatches: [Match] = []
    @Published var groups: [GroupTable] = []
    @Published var bracket: [BracketRound] = []
    @Published var matchDetails: [String: [MatchEvent]] = [:]
    @Published var lastUpdated: Date?
    @Published var errorMessage: String?
    @Published var goalAlert: GoalAlert?

    @Published var favorites: Set<String> {
        didSet { UserDefaults.standard.set(Array(favorites), forKey: "favoriteTeamIDs") }
    }
    @Published var goalAlertsEnabled: Bool {
        didSet { UserDefaults.standard.set(goalAlertsEnabled, forKey: "goalAlertsEnabled") }
    }
    @Published var countdownAlertEnabled: Bool {
        didSet { UserDefaults.standard.set(countdownAlertEnabled, forKey: "countdownAlertEnabled") }
    }
    @Published var showFormGuide: Bool {
        didSet { UserDefaults.standard.set(showFormGuide, forKey: "showFormGuide") }
    }

    private var pollTask: Task<Void, Never>?
    private var tickTask: Task<Void, Never>?
    private var previousScores: [String: (Int, Int)] = [:]

    init(startPolling: Bool = true) {
        let defaults = UserDefaults.standard
        favorites = Set(defaults.stringArray(forKey: "favoriteTeamIDs") ?? [])
        goalAlertsEnabled = defaults.object(forKey: "goalAlertsEnabled") as? Bool ?? true
        countdownAlertEnabled = defaults.object(forKey: "countdownAlertEnabled") as? Bool ?? true
        showFormGuide = defaults.object(forKey: "showFormGuide") as? Bool ?? true

        guard startPolling else { return }
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let live = await MainActor.run { self?.todayMatches.contains { $0.isLive } ?? false }
                let seconds: UInt64 = live ? 45 : 120
                try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            }
        }
        // Re-render the menu bar label every 30s so the kickoff countdown
        // and goal-alert expiry stay current between polls.
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30 * 1_000_000_000)
                await MainActor.run { self?.objectWillChange.send() }
            }
        }
    }

    func refresh() async {
        do {
            let dayFormatter = DateFormatter()
            dayFormatter.locale = Locale(identifier: "en_US_POSIX")
            dayFormatter.dateFormat = "yyyyMMdd"
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!

            async let todayFetch = Self.fetchDay(nil)
            async let tomorrowFetch = Self.fetchDay(dayFormatter.string(from: tomorrow))
            async let standingsFetch = Self.fetchStandings()
            async let bracketFetch = Self.fetchBracket()
            let (today, next, standings, rounds) = try await (todayFetch, tomorrowFetch, standingsFetch, bracketFetch)

            detectGoals(in: today)

            let todayIDs = Set(today.map(\.id))
            todayMatches = today.sorted { $0.kickoff < $1.kickoff }
            tomorrowMatches = next.filter { !todayIDs.contains($0.id) }
                .sorted { $0.kickoff < $1.kickoff }
            groups = standings
            bracket = rounds
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't reach ESPN: \(error.localizedDescription)"
        }
    }

    func loadDetails(for matchId: String) async {
        do {
            let events = try await Self.fetchSummary(eventId: matchId)
            matchDetails[matchId] = events
        } catch {
            matchDetails[matchId] = []
        }
    }

    func toggleFavorite(_ teamId: String) {
        if favorites.contains(teamId) {
            favorites.remove(teamId)
        } else {
            favorites.insert(teamId)
        }
    }

    func isFavoriteMatch(_ match: Match) -> Bool {
        favorites.contains(match.home.id) || favorites.contains(match.away.id)
    }

    // MARK: - Goal detection (menu bar alerts)

    private func detectGoals(in matches: [Match]) {
        for match in matches where match.state != .pre {
            guard let h = match.home.score, let a = match.away.score else { continue }
            if let (prevH, prevA) = previousScores[match.id], h + a > prevH + prevA {
                let scorer = h > prevH ? match.home : match.away
                goalAlert = GoalAlert(
                    text: "🥅 GOAL \(scorer.abbrev)! \(match.home.abbrev) \(h)–\(a) \(match.away.abbrev) \(match.clock)",
                    at: Date())
            }
            previousScores[match.id] = (h, a)
        }
    }

    // MARK: - Derived state

    var liveMatches: [Match] {
        todayMatches.filter { $0.isLive }
    }

    var liveMatch: Match? {
        liveMatches.first { isFavoriteMatch($0) } ?? liveMatches.first
    }

    var nextMatch: Match? {
        (todayMatches + tomorrowMatches)
            .filter { $0.state == .pre && $0.kickoff > Date() }
            .min { $0.kickoff < $1.kickoff }
    }

    var menuTitle: String {
        if goalAlertsEnabled, let alert = goalAlert,
           Date().timeIntervalSince(alert.at) < 180 {
            return alert.text
        }
        if let live = liveMatch {
            let extra = liveMatches.count - 1
            var title = "⚽️ \(live.home.abbrev) \(live.home.score ?? 0)–\(live.away.score ?? 0) \(live.away.abbrev) \(live.clock)"
            if extra > 0 { title += " +\(extra)" }
            return title
        }
        if let next = nextMatch {
            let remaining = next.kickoff.timeIntervalSince(Date())
            if countdownAlertEnabled, remaining <= 600 {
                let minutes = max(1, Int(remaining / 60))
                return "🔔 \(next.home.abbrev)–\(next.away.abbrev) in \(minutes)m"
            }
            let f = DateFormatter()
            f.timeStyle = .short
            return "⚽️ \(next.home.abbrev)–\(next.away.abbrev) \(f.string(from: next.kickoff))"
        }
        return "⚽️ WC26"
    }

    // MARK: - Fetching

    nonisolated private static func getJSON<T: Decodable>(_ urlString: String, as type: T.Type) async throws -> T {
        let (data, _) = try await URLSession.shared.data(from: URL(string: urlString)!)
        return try JSONDecoder().decode(T.self, from: data)
    }

    nonisolated static func fetchDay(_ yyyymmdd: String?) async throws -> [Match] {
        var urlString = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard"
        if let day = yyyymmdd { urlString += "?dates=\(day)" }
        let board = try await getJSON(urlString, as: Scoreboard.self)
        return board.events.compactMap(Self.match(from:))
    }

    nonisolated static func fetchBracket() async throws -> [BracketRound] {
        let urlString = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/scoreboard?dates=20260628-20260720"
        let board = try await getJSON(urlString, as: Scoreboard.self)
        let matches = board.events.compactMap(Self.match(from:))
        let grouped = Dictionary(grouping: matches, by: \.roundSlug)
        return grouped
            .map { slug, list in
                BracketRound(slug: slug,
                             title: RoundNames.title(for: slug),
                             matches: list.sorted { $0.kickoff < $1.kickoff })
            }
            .sorted { ($0.matches.first?.kickoff ?? .distantFuture) < ($1.matches.first?.kickoff ?? .distantFuture) }
    }

    nonisolated static func fetchStandings() async throws -> [GroupTable] {
        let urlString = "https://site.api.espn.com/apis/v2/sports/soccer/fifa.world/standings?season=2026"
        let response = try await getJSON(urlString, as: StandingsResponse.self)
        return (response.children ?? []).compactMap { group -> GroupTable? in
            guard let name = group.name, let entries = group.standings?.entries else { return nil }
            let rows = entries.map { entry -> GroupRow in
                func stat(_ key: String) -> Int {
                    Int(entry.stats.first { $0.name == key }?.value ?? 0)
                }
                let gd = entry.stats.first { $0.name == "pointDifferential" }?.displayValue ?? "0"
                return GroupRow(id: entry.team.id ?? UUID().uuidString,
                                name: entry.team.displayName ?? "—",
                                logoURL: entry.team.logos?.first?.href.flatMap(URL.init(string:)),
                                rank: stat("rank"),
                                played: stat("gamesPlayed"),
                                wins: stat("wins"),
                                draws: stat("ties"),
                                losses: stat("losses"),
                                goalDiff: gd,
                                points: stat("points"))
            }
            return GroupTable(name: name, rows: rows.sorted { $0.rank < $1.rank })
        }
        .sorted { $0.name < $1.name }
    }

    nonisolated static func fetchSummary(eventId: String) async throws -> [MatchEvent] {
        let urlString = "https://site.api.espn.com/apis/site/v2/sports/soccer/fifa.world/summary?event=\(eventId)"
        let response = try await getJSON(urlString, as: SummaryResponse.self)
        return (response.keyEvents ?? []).compactMap { event -> MatchEvent? in
            let typeSlug = event.type?.type ?? ""
            let kind: MatchEventKind
            if event.scoringPlay == true {
                if typeSlug.contains("own") { kind = .ownGoal }
                else if typeSlug.contains("penalty") { kind = .penalty }
                else { kind = .goal }
            } else if typeSlug == "yellow-card" {
                kind = .yellow
            } else if typeSlug == "red-card" {
                kind = .red
            } else {
                return nil
            }
            let player = event.participants?.first?.athlete?.displayName
                ?? event.shortText ?? event.type?.text ?? "—"
            return MatchEvent(id: event.id ?? UUID().uuidString,
                              kind: kind,
                              minute: event.clock?.displayValue ?? "",
                              player: player,
                              teamId: event.team?.id ?? "")
        }
    }

    nonisolated static func match(from event: SBEvent) -> Match? {
        guard let comp = event.competitions.first,
              let kickoff = ESPNDate.parse(event.date),
              let homeC = comp.competitors.first(where: { $0.homeAway == "home" }),
              let awayC = comp.competitors.first(where: { $0.homeAway == "away" })
        else { return nil }

        func side(_ c: SBCompetitor) -> TeamSide {
            TeamSide(id: c.team.id ?? c.team.displayName,
                     name: c.team.displayName,
                     abbrev: c.team.abbreviation ?? String(c.team.displayName.prefix(3)).uppercased(),
                     score: c.score.flatMap(Int.init),
                     logoURL: c.team.logo.flatMap(URL.init(string:)),
                     winner: c.winner ?? false,
                     form: c.form)
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
            ?? URL(string: "https://www.espn.com/soccer/match/_/gameId/\(event.id)")

        return Match(id: event.id,
                     kickoff: kickoff,
                     home: side(homeC),
                     away: side(awayC),
                     state: state,
                     clock: comp.status.displayClock ?? "",
                     venue: comp.venue?.fullName ?? "",
                     city: comp.venue?.address?.city ?? "",
                     networks: networks,
                     roundSlug: event.season?.slug ?? "group-stage",
                     gamecastURL: gamecast)
    }
}

// MARK: - Calendar export

enum CalendarExport {
    static func icsString(for match: Match) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        let start = f.string(from: match.kickoff)
        let end = f.string(from: match.kickoff.addingTimeInterval(2 * 3600))
        let tv = match.networks.isEmpty ? "" : "TV: \(match.networks.joined(separator: "\\, "))"
        let location = [match.venue, match.city].filter { !$0.isEmpty }
            .joined(separator: "\\, ")
        return """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//WorldCup26//EN
        BEGIN:VEVENT
        UID:wc26-\(match.id)@worldcup26.local
        DTSTAMP:\(start)
        DTSTART:\(start)
        DTEND:\(end)
        SUMMARY:⚽️ \(match.home.name) vs \(match.away.name)
        LOCATION:\(location)
        DESCRIPTION:\(tv)
        BEGIN:VALARM
        TRIGGER:-PT10M
        ACTION:DISPLAY
        DESCRIPTION:Kickoff in 10 minutes
        END:VALARM
        END:VEVENT
        END:VCALENDAR
        """
    }
}
