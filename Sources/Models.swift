import Foundation

// MARK: - Leagues

enum SportLeague: String, CaseIterable, Identifiable {
    case worldCup, cricket, nfl, nba, nhl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .worldCup: return "World Cup"
        case .cricket: return "Cricket"
        case .nfl: return "NFL"
        case .nba: return "NBA"
        case .nhl: return "NHL"
        }
    }

    var emoji: String {
        switch self {
        case .worldCup: return "⚽️"
        case .cricket: return "🏏"
        case .nfl: return "🏈"
        case .nba: return "🏀"
        case .nhl: return "🏒"
        }
    }

    /// ESPN API path for the standard scoreboard leagues. Cricket is
    /// discovered dynamically; the World Cup has its own fetchers.
    var apiPath: String? {
        switch self {
        case .nfl: return "football/nfl"
        case .nba: return "basketball/nba"
        case .nhl: return "hockey/nhl"
        default: return nil
        }
    }
}

struct LeagueSection: Identifiable {
    var id: String { title }
    let title: String
    let matches: [Match]
}

// MARK: - ESPN API response types

struct Scoreboard: Decodable {
    let leagues: [SBLeagueInfo]?
    let events: [SBEvent]
}

struct SBLeagueInfo: Decodable {
    let name: String?
}

struct SBEvent: Decodable {
    let id: String
    let date: String
    let name: String
    let shortName: String
    let season: SBSeasonRef?
    let links: [SBLink]?
    let competitions: [SBCompetition]
}

struct SBSeasonRef: Decodable {
    let slug: String?
}

struct SBLink: Decodable {
    let rel: [String]?
    let href: String?
}

struct SBCompetition: Decodable {
    let competitors: [SBCompetitor]
    let status: SBStatus
    let venue: SBVenue?
    let broadcasts: [SBBroadcast]?
}

struct SBCompetitor: Decodable {
    let homeAway: String?
    let score: String?
    let winner: Bool?
    let form: String?
    let team: SBTeam

    enum CodingKeys: String, CodingKey { case homeAway, score, winner, form, team }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        homeAway = try? c.decode(String.self, forKey: .homeAway)
        form = try? c.decode(String.self, forKey: .form)
        team = try c.decode(SBTeam.self, forKey: .team)
        // score is a string in most sports but occasionally numeric
        if let s = try? c.decode(String.self, forKey: .score) { score = s }
        else if let d = try? c.decode(Double.self, forKey: .score) {
            score = d == d.rounded() ? String(Int(d)) : String(d)
        } else { score = nil }
        // winner is a Bool in most sports but a string ("true") in cricket
        if let b = try? c.decode(Bool.self, forKey: .winner) { winner = b }
        else if let s = try? c.decode(String.self, forKey: .winner) { winner = s == "true" }
        else { winner = nil }
    }
}

struct SBTeam: Decodable {
    let id: String?
    let abbreviation: String?
    let displayName: String
    let logo: String?
    let color: String?
}

struct SBStatus: Decodable {
    let displayClock: String?
    let type: SBStatusType
}

struct SBStatusType: Decodable {
    let state: String        // "pre" | "in" | "post"
    let completed: Bool?
    let detail: String?
    let shortDetail: String?
}

struct SBVenue: Decodable {
    let fullName: String?
    let address: SBAddress?
}

struct SBAddress: Decodable {
    let city: String?
    let country: String?
}

struct SBBroadcast: Decodable {
    let market: String?
    let names: [String]?
}

// MARK: - Cricket series discovery (scoreboard/header endpoint)

struct CricketHeader: Decodable {
    let sports: [CHSport]?
}

struct CHSport: Decodable {
    let leagues: [CHLeague]?
}

struct CHLeague: Decodable {
    let id: String?
    let name: String?
    let events: [CHEvent]?
}

struct CHEvent: Decodable {
    let status: String?
}

// MARK: - ESPN standings types

struct StandingsResponse: Decodable {
    let children: [SBGroup]?
}

struct SBGroup: Decodable {
    let name: String?
    let standings: SBGroupStandings?
}

struct SBGroupStandings: Decodable {
    let entries: [SBGroupEntry]?
}

struct SBGroupEntry: Decodable {
    let team: SBStandingsTeam
    let stats: [SBStat]
}

struct SBStandingsTeam: Decodable {
    let id: String?
    let displayName: String?
    let logos: [SBLogo]?
}

struct SBLogo: Decodable {
    let href: String?
}

struct SBStat: Decodable {
    let name: String?
    let displayValue: String?
    let value: Double?
}

// MARK: - ESPN match summary types

struct SummaryResponse: Decodable {
    let keyEvents: [SBKeyEvent]?
}

struct SBKeyEvent: Decodable {
    let id: String?
    let type: SBKeyEventType?
    let shortText: String?
    let text: String?
    let clock: SBKeyEventClock?
    let scoringPlay: Bool?
    let team: SBKeyEventTeam?
    let participants: [SBParticipant]?
}

struct SBKeyEventType: Decodable {
    let text: String?
    let type: String?
}

struct SBKeyEventClock: Decodable {
    let displayValue: String?
}

struct SBKeyEventTeam: Decodable {
    let id: String?
    let displayName: String?
}

struct SBParticipant: Decodable {
    let athlete: SBAthlete?
}

struct SBAthlete: Decodable {
    let displayName: String?
}

// MARK: - App-facing models

enum MatchState {
    case pre, live, post
}

struct TeamSide {
    let id: String
    let name: String
    let abbrev: String
    let score: Int?
    let scoreText: String?   // cricket innings lines like "278/8 (50 ov)"
    let logoURL: URL?
    let winner: Bool
    let form: String?
}

struct Match: Identifiable {
    let id: String
    let kickoff: Date
    let home: TeamSide
    let away: TeamSide
    let state: MatchState
    let clock: String
    let statusDetail: String   // "Q4 2:31", "Stumps", "Day 2", "Final/OT"
    let venue: String
    let city: String
    let networks: [String]
    let roundSlug: String
    let gamecastURL: URL?

    var isLive: Bool { state == .live }
}

struct GroupRow: Identifiable {
    let id: String
    let name: String
    let logoURL: URL?
    let rank: Int
    let played: Int
    let wins: Int
    let draws: Int
    let losses: Int
    let goalDiff: String
    let points: Int
}

struct GroupTable: Identifiable {
    var id: String { name }
    let name: String
    let rows: [GroupRow]
}

struct BracketRound: Identifiable {
    var id: String { slug }
    let slug: String
    let title: String
    let matches: [Match]
}

enum MatchEventKind {
    case goal, ownGoal, penalty, yellow, red

    var emoji: String {
        switch self {
        case .goal: return "⚽️"
        case .ownGoal: return "🥅"
        case .penalty: return "⚽️"
        case .yellow: return "🟨"
        case .red: return "🟥"
        }
    }

    var label: String {
        switch self {
        case .goal: return ""
        case .ownGoal: return "(own goal)"
        case .penalty: return "(pen)"
        case .yellow: return ""
        case .red: return ""
        }
    }
}

struct MatchEvent: Identifiable {
    let id: String
    let kind: MatchEventKind
    let minute: String
    let player: String
    let teamId: String
}

struct GoalAlert {
    let text: String
    let at: Date
}

enum ESPNDate {
    // ESPN dates come as "2026-06-11T19:00Z" or "2026-06-12T10:00:00Z"
    private static func make(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = format
        return f
    }

    static let short = make("yyyy-MM-dd'T'HH:mm'Z'")
    static let full = make("yyyy-MM-dd'T'HH:mm:ss'Z'")

    static func parse(_ s: String) -> Date? {
        short.date(from: s) ?? full.date(from: s)
    }
}

enum NetworkNames {
    static let pretty: [String: String] = [
        "Tele": "Telemundo",
        "TELE": "Telemundo",
        "Uni": "Universo",
    ]

    static func clean(_ raw: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for n in raw {
            let name = pretty[n] ?? n
            if seen.insert(name).inserted {
                out.append(name)
            }
        }
        return out
    }
}

enum RoundNames {
    static let titles: [String: String] = [
        "group-stage": "Group Stage",
        "round-of-32": "Round of 32",
        "round-of-16": "Round of 16",
        "quarterfinals": "Quarterfinals",
        "quarterfinal": "Quarterfinals",
        "semifinals": "Semifinals",
        "semifinal": "Semifinals",
        "3rd-place-match": "Third Place",
        "third-place-match": "Third Place",
        "final": "Final",
    ]

    static func title(for slug: String) -> String {
        if let t = titles[slug] { return t }
        return slug.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
    }
}
