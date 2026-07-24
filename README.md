# 🥎 Matchday

A native macOS menu bar app for live scores across **NCAA softball, cricket, MLB, NFL, college football, NBA and NHL** — with US TV listings, in your local time zone. Everything lives in the menu bar: no Dock icon, no notification spam.

**[⬇ Download the latest release](https://github.com/srinidharmalingam-create/worldcup26/releases/latest)** — unzip, drag to Applications, right-click → Open the first time. macOS 13+, Apple Silicon & Intel.

**🌐 Not on a Mac?** Use the web version on any phone, tablet, or computer: **[srinidharmalingam-create.github.io/worldcup26](https://srinidharmalingam-create.github.io/worldcup26/)** — same scores, TV networks, and standings. (Source in [`docs/`](docs/index.html).)

## Features

### Menu bar ticker
- **Live score + game clock** for whatever's on (e.g. `⚾️ NYY 4–2 BOS Bot 7th`), with a `+N` count when several games are live.
- **Score alerts** — when anyone scores, the ticker flashes `⚾️ NYY scores! NYY 4–2 BOS` for 3 minutes.
- **Start countdown** — inside the last 10 minutes before the next game it switches to `🔔 NYY–BOS in 9m`.
- Starred teams always win the ticker slot.

### 📺 Today
A cross-sport TV guide: everything live right now plus everything else starting today, in chronological order with the networks carrying it. A countdown banner sits on top when nothing is live yet.

### ⭐️ My Teams
Every live and upcoming game for teams you've starred, across all leagues, in one view.

### League tabs
Each league gets its own tab with full game cards — logos (or abbreviations where a league has no crests), big scores, pulsing LIVE badges, venue, and TV network chips.

- **Box scores** — expand any finished or in-progress game for inning/quarter/period line scores, plus **live win probability**.
- **Standings** — a Games/Standings toggle for softball, MLB, NFL, NBA and NHL.
- **Cricket** auto-discovers the top active series worldwide (ICC events first) with full innings scorelines.
- **Team links** — click any team name or crest to open its ESPN page.
- **Add to Calendar** — export an upcoming game with its TV networks and a 10-minute alarm.

### Settings (gear icon)
Toggle score alerts and the start countdown, and hide any leagues you don't follow — hidden leagues disappear from the picker, the ticker, and the Today guide. "Start at login" lives in the footer.

All times are formatted by macOS using the computer's current time zone. Data refreshes every 2 minutes (45 seconds while anything is live) from ESPN's public scoreboard API — no API key required. Broadcast listings are US national networks.

## Season note

Leagues only show games when they're in season. NCAA softball runs February–June (Women's College World Series in early June); MLB April–October; NFL/CFB September–January; NBA/NHL October–June; cricket runs year-round somewhere in the world. Out of season, a league tab shows its last result and standings.

## Running it

```
open WorldCup26.app
```

Quit via the power button in the dashboard footer.

## Building from source

Requires Xcode Command Line Tools (any recent Swift).

```
./build.sh
```

Produces `WorldCup26.app` and `WorldCup26.zip` — a universal binary for Apple Silicon and Intel.

## Sanity check

```
WorldCup26.app/Contents/MacOS/WorldCup26 --test
```

prints today's games, standings, and cricket series fetched from ESPN for every league.
