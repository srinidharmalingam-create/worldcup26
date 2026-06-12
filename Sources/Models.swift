import Foundation

// MARK: - ESPN API response types

struct Scoreboard: Decodable {
    let events: [SBEvent]
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
    let homeAway: String
    let score: String?
    let winner: Bool?
    let form: String?
    let team: SBTeam
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
    let completed: Bool
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
    // ESPN dates look like "2026-06-11T19:00Z" (no seconds)
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm'Z'"
        return f
    }()

    static func parse(_ s: String) -> Date? {
        formatter.date(from: s)
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
