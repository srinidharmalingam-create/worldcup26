#!/usr/bin/env python3
"""Extract AUSL (Athletes Unlimited Softball League) games + standings from
theausl.com's public pages and write a normalized docs/ausl.json.

theausl.com is a Next.js site that embeds its data as an RSC payload in
self.__next_f.push([...]) calls. There is no CORS-enabled JSON endpoint, so
this runs server-side (a scheduled GitHub Action) and publishes the result to
GitHub Pages, where both the web app and the Mac app can read it same-origin.

No authentication and no private endpoints are touched — this reads the same
public HTML a browser loads.
"""
import json
import re
import sys
import urllib.request
from datetime import datetime, timezone

UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Matchday-AUSL/1.0"

# AUSL team name -> abbreviation + city (from MLB StatsAPI sportId=576 team list)
TEAMS = {
    "Talons":  ("UTA", "Salt Lake City"),
    "Bandits": ("CHI", "Chicago"),
    "Cascade": ("PDX", "Portland"),
    "Volts":   ("TEX", "Austin"),
    "Blaze":   ("CAR", "Durham"),
    "Spark":   ("OKC", "Oklahoma City"),
}


def fetch(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as r:
        return r.read().decode("utf-8", "ignore")


def rsc_payload(html):
    """Concatenate and unescape the Next.js flight payload."""
    chunks = re.findall(r'self\.__next_f\.push\(\[1,"(.*?)"\]\)', html, re.S)
    joined = "".join(chunks)
    try:
        return joined.encode("utf-8").decode("unicode_escape")
    except Exception:
        return joined


def balanced_objects(text, start_key):
    """Yield JSON objects that begin with `start_key` by brace-matching."""
    for m in re.finditer(re.escape(start_key), text):
        i = m.start()
        depth = 0
        for j in range(i, min(i + 12000, len(text))):
            c = text[j]
            if c == "{":
                depth += 1
            elif c == "}":
                depth -= 1
                if depth == 0:
                    try:
                        yield json.loads(text[i : j + 1])
                    except Exception:
                        pass
                    break


def team_index(ref, default):
    """Home/away are RSC references ending in 'competitors:N'."""
    if isinstance(ref, str):
        m = re.search(r"competitors:(\d+)", ref)
        if m:
            return int(m.group(1))
    return default


def norm_team(name, score):
    ab, city = TEAMS.get(name, (name[:3].upper(), ""))
    return {"name": name, "abbrev": ab, "city": city,
            "score": score if isinstance(score, int) else None}


def game_state(record, msg):
    r = (record or "").lower()
    m = (msg or "").lower()
    if "final" in r or "complete" in r or "final" in m:
        return "post"
    if any(k in r or k in m for k in ("progress", "live", "delay", "inning", "top ", "bot ", "mid ")):
        return "live"
    return "pre"


def parse_games(payload):
    seen = {}
    for g in balanced_objects(payload, '{"gameId":'):
        gid = g.get("gameId")
        comps = g.get("competitors") or []
        if not gid or len(comps) < 2 or not g.get("gameDateIso"):
            continue
        hi = team_index(g.get("homeTeam"), 0)
        ai = team_index(g.get("awayTeam"), 1)
        if hi >= len(comps) or ai >= len(comps):
            hi, ai = 0, 1
        state = game_state(g.get("recordStatus"), g.get("gameStatusMessage"))
        if (g.get("recordStatus") or "").lower() in ("cancelled", "postponed"):
            continue
        status = {"post": "Final", "live": (g.get("gameStatusMessage") or "Live"),
                  "pre": "Scheduled"}[state]
        venue = g.get("venue") or {}
        addr = venue.get("address") or {}
        nets, link = [], None
        for b in (g.get("broadcasts") or []):
            if b.get("name"):
                nets.append(b["name"])
            if not link and b.get("link"):
                link = b["link"]
        seen[gid] = {
            "id": str(gid),
            "dateIso": g["gameDateIso"],
            "state": state,
            "status": status,
            "home": norm_team(comps[hi].get("name", "?"), g.get("homeTeamScore")),
            "away": norm_team(comps[ai].get("name", "?"), g.get("awayTeamScore")),
            "venue": venue.get("name", ""),
            "city": addr.get("city", ""),
            "networks": nets,
            "link": link,
            "postseason": (g.get("gameTypeLk") == "PS"),
        }
    return [seen[k] for k in sorted(seen)]


def parse_standings(payload):
    rows = {}
    for o in balanced_objects(payload, '{"seasonId":'):
        if "franchiseSlug" not in o or o.get("standingsTypeLk") != "SEASON":
            continue
        # Highest seasonId wins = current season's regular-season table.
        rows.setdefault(o["seasonId"], []).append(o)
    if not rows:
        return []
    latest = max(rows)
    out = []
    for r in rows[latest]:
        name = r.get("franchiseSlug", "?")
        w, l = int(r.get("wins") or 0), int(r.get("losses") or 0)
        pct = f"{w / (w + l):.3f}".lstrip("0") if (w + l) else "—"
        ab, _ = TEAMS.get(name, (name[:3].upper(), ""))
        out.append({"name": name, "abbrev": ab, "wins": w, "losses": l, "pct": pct})
    out.sort(key=lambda x: (x["wins"] / max(1, x["wins"] + x["losses"]), x["wins"]), reverse=True)
    return out


def main():
    try:
        sched_html = fetch("https://theausl.com/schedule/")
        stand_html = fetch("https://theausl.com/standings/")
    except Exception as e:
        print(f"fetch failed: {e}", file=sys.stderr)
        sys.exit(1)

    games = parse_games(rsc_payload(sched_html))
    standings = parse_standings(rsc_payload(stand_html))

    if not games and not standings:
        print("extracted nothing — page structure may have changed", file=sys.stderr)
        sys.exit(2)

    out = {
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "league": "Athletes Unlimited Softball League",
        "games": games,
        "standings": standings,
    }
    path = sys.argv[1] if len(sys.argv) > 1 else "docs/ausl.json"
    with open(path, "w") as f:
        json.dump(out, f, indent=1)
    live = sum(1 for g in games if g["state"] == "live")
    print(f"wrote {path}: {len(games)} games ({live} live), {len(standings)} standings rows")


if __name__ == "__main__":
    main()
