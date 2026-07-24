import Foundation

// MARK: - Leagues

enum SportLeague: String, CaseIterable, Identifiable {
    case softball, ausl, cricket, mlb, nfl, cfb, nba, nhl

    var id: String { rawValue }

    var label: String {
        switch self {
        case .softball: return "NCAA SB"
        case .ausl: return "AUSL"
        case .cricket: return "Cricket"
        case .mlb: return "MLB"
        case .nfl: return "NFL"
        case .cfb: return "CFB"
        case .nba: return "NBA"
        case .nhl: return "NHL"
        }
    }

    var emoji: String {
        switch self {
        case .softball: return "🥎"
        case .ausl: return "🥎"
        case .cricket: return "🏏"
        case .mlb: return "⚾️"
        case .nfl: return "🏈"
        case .cfb: return "🎓"
        case .nba: return "🏀"
        case .nhl: return "🏒"
        }
    }

    /// ESPN scoreboard path. Cricket is discovered dynamically; AUSL comes from
    /// our own published ausl.json (theausl.com has no CORS API).
    var apiPath: String? {
        switch self {
        case .softball: return "baseball/college-softball"
        case .mlb: return "baseball/mlb"
        case .nfl: return "football/nfl"
        case .cfb: return "football/college-football"
        case .nba: return "basketball/nba"
        case .nhl: return "hockey/nhl"
        case .cricket, .ausl: return nil
        }
    }

    /// Leagues with a usable standings table.
    var hasStandings: Bool {
        switch self {
        case .softball, .ausl, .mlb, .nfl, .nba, .nhl: return true
        case .cfb, .cricket: return false
        }
    }

    /// Leagues that also pull tomorrow's slate, so a quiet evening still
    /// shows what's next.
    var fetchesTomorrow: Bool {
        switch self {
        case .softball, .mlb, .nba, .nhl: return true
        case .nfl, .cfb, .cricket, .ausl: return false
        }
    }
}

// MARK: - AUSL (published ausl.json)

struct AUSLData: Decodable {
    let games: [AUSLGame]
    let standings: [AUSLStanding]
}

struct AUSLGame: Decodable {
    let id: String
    let dateIso: String
    let state: String
    let status: String
    let home: AUSLTeam
    let away: AUSLTeam
    let venue: String
    let city: String
    let networks: [String]
    let link: String?
}

struct AUSLTeam: Decodable {
    let name: String
    let abbrev: String
    let city: String
    let score: Int?
}

struct AUSLStanding: Decodable {
    let name: String
    let abbrev: String
    let wins: Int
    let losses: Int
    let pct: String
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
    let links: [SBLink]?
    let competitions: [SBCompetition]
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
    let linescores: [SBLineScore]?

    enum CodingKeys: String, CodingKey { case homeAway, score, winner, form, team, linescores }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        homeAway = try? c.decode(String.self, forKey: .homeAway)
        form = try? c.decode(String.self, forKey: .form)
        team = try c.decode(SBTeam.self, forKey: .team)
        linescores = try? c.decode([SBLineScore].self, forKey: .linescores)
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
    let links: [SBLink]?
}

struct SBLineScore: Decodable {
    let value: Double?
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

// MARK: - Standings

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

struct WinProbResponse: Decodable {
    let winprobability: [WPEntry]?
}

struct WPEntry: Decodable {
    let homeWinPercentage: Double?
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
    let siteURL: URL?        // ESPN team page
    let periods: [Int]       // line score per inning/quarter/period
}

struct Match: Identifiable {
    let id: String
    let kickoff: Date
    let home: TeamSide
    let away: TeamSide
    let state: MatchState
    let clock: String
    let statusDetail: String   // "Q4 2:31", "Stumps", "Bot 7th", "Final/OT"
    let venue: String
    let city: String
    let networks: [String]
    let gamecastURL: URL?

    var isLive: Bool { state == .live }
}

struct USRow: Identifiable {
    let id: String
    let name: String
    let logoURL: URL?
    let wins: Int
    let losses: Int
    let pct: String
    let gamesBehind: String
}

struct USTable: Identifiable {
    var id: String { name }
    let name: String
    let rows: [USRow]
}

enum MainTab: Hashable {
    case guide, mine
    case league(SportLeague)
}

struct GuideEntry: Identifiable {
    var id: String { "\(league.rawValue)-\(match.id)" }
    let league: SportLeague
    let match: Match
}

/// A score change worth flashing in the menu bar.
struct ScoreAlert {
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
