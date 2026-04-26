#!/usr/bin/env python3
"""Fantasy hockey playoff scorer using the NHL public API.

Scoring rules:
  Teams (each manager owns 1 East + 1 West):
    Win               = 2
    OT/SO loss        = 1
    Shutout (won 0-x) = +1
    Scored 5+ goals   = +1
  Skaters (each manager drafts 4):
    Goal              = 2
    Assist            = 1

Usage:
  python scorer.py                        # show standings
  python scorer.py --verbose              # show per-manager breakdown
  python scorer.py search "McDavid"       # find NHL player IDs
  python scorer.py games                  # list playoff games processed
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path

ROSTER_PATH = Path(__file__).with_name("rosters.json")
PLAYER_CACHE_PATH = Path(__file__).with_name(".player_cache.json")
API_BASE = "https://api-web.nhle.com/v1"
SEARCH_BASE = "https://search.d3.nhle.com/api/v1/search"
PLAYOFF_GAME_TYPE = 3
USER_AGENT = "fantasy-hockey-scorer/1.0"
TEAM_LOGO_URL = "https://a.espncdn.com/i/teamlogos/nhl/500/{tri}.png"
# ESPN uses different abbreviations than the NHL for a few clubs.
ESPN_TRI_ALIASES = {"TBL": "tb", "LAK": "la", "SJS": "sj", "NJD": "nj"}


def espn_logo_url(tri: str) -> str:
    return TEAM_LOGO_URL.format(tri=ESPN_TRI_ALIASES.get(tri.upper(), tri.lower()))


def http_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode("utf-8"))


# ---------- NHL API wrappers ----------

def search_player(query: str, limit: int = 10) -> list[dict]:
    q = urllib.parse.quote(query)
    url = f"{SEARCH_BASE}/player?culture=en-us&limit={limit}&q={q}&active=true"
    return http_json(url) or []


def score_for_date(d: date) -> dict:
    return http_json(f"{API_BASE}/score/{d.isoformat()}")


def boxscore(game_id: int) -> dict:
    return http_json(f"{API_BASE}/gamecenter/{game_id}/boxscore")


def player_landing(player_id: int) -> dict:
    return http_json(f"{API_BASE}/player/{player_id}/landing")


# ---------- Player metadata cache ----------
# Caches headshot URL, current team, sweater number per player so we don't
# hit the player landing endpoint on every refresh.

def load_player_cache() -> dict:
    if PLAYER_CACHE_PATH.exists():
        try:
            return json.loads(PLAYER_CACHE_PATH.read_text())
        except Exception:
            return {}
    return {}


def save_player_cache(cache: dict) -> None:
    PLAYER_CACHE_PATH.write_text(json.dumps(cache, indent=2))


def hydrate_player_meta(player_ids: set[int]) -> dict[int, dict]:
    cache = load_player_cache()
    dirty = False
    for pid in player_ids:
        key = str(pid)
        if key in cache:
            continue
        try:
            d = player_landing(pid)
            cache[key] = {
                "headshot_url": d.get("headshot"),
                "hero_url": d.get("heroImage"),
                "team_tricode": d.get("currentTeamAbbrev"),
                "sweater_number": d.get("sweaterNumber"),
                "first_name": (d.get("firstName") or {}).get("default"),
                "last_name": (d.get("lastName") or {}).get("default"),
                "position": d.get("position"),
            }
            dirty = True
        except Exception as e:
            print(f"  warn: failed to load player {pid}: {e}", file=sys.stderr)
            cache[key] = {}
    if dirty:
        save_player_cache(cache)
    return {int(k): v for k, v in cache.items()}


# ---------- Roster loading ----------

def load_rosters() -> dict:
    if not ROSTER_PATH.exists():
        sys.exit(f"Missing {ROSTER_PATH}")
    data = json.loads(ROSTER_PATH.read_text())
    if "managers" not in data or "playoff_start_date" not in data:
        sys.exit("rosters.json must have 'playoff_start_date' and 'managers'")
    return data


# ---------- Game collection ----------

def daterange(start: date, end: date):
    cur = start
    while cur <= end:
        yield cur
        cur += timedelta(days=1)


FINISHED_STATES = ("OFF", "FINAL", "OVER")
LIVE_STATES = ("LIVE", "CRIT")


def is_finished(state: str) -> bool:
    return state in FINISHED_STATES


def is_live(state: str) -> bool:
    return state in LIVE_STATES


def collect_playoff_games(start: date, end: date) -> list[dict]:
    """Return list of playoff games (finished + live) between start and end (inclusive).

    Live games are included so skater goals/assists count in real time.
    classify_team_result() gates W/OTL/SO/5+G points on game completion.
    """
    games: dict[int, dict] = {}
    for d in daterange(start, end):
        try:
            day = score_for_date(d)
        except Exception as e:
            print(f"  warn: failed to fetch {d}: {e}", file=sys.stderr)
            continue
        for g in day.get("games", []):
            if g.get("gameType") != PLAYOFF_GAME_TYPE:
                continue
            state = g.get("gameState", "")
            if not (is_finished(state) or is_live(state)):
                continue
            games[g["id"]] = g
    return list(games.values())


# ---------- Scoring ----------

def classify_team_result(game: dict, tricode: str) -> tuple[int, list[str]]:
    """Return (points, reason_list) for a team. Returns (0, []) if game isn't final."""
    if not is_finished(game.get("gameState", "")):
        return 0, []
    away = game["awayTeam"]
    home = game["homeTeam"]
    if tricode == away["abbrev"]:
        me, opp = away, home
    elif tricode == home["abbrev"]:
        me, opp = home, away
    else:
        return 0, []

    my_goals = me.get("score", 0)
    opp_goals = opp.get("score", 0)
    last_period = game.get("periodDescriptor", {}).get("periodType", "REG")  # REG/OT/SO

    pts = 0
    reasons = []
    if my_goals > opp_goals:
        pts += 2
        reasons.append("W")
        if opp_goals == 0:
            pts += 1
            reasons.append("SO")
    elif my_goals < opp_goals and last_period in ("OT", "SO"):
        pts += 1
        reasons.append("OTL")
    if my_goals >= 5:
        pts += 1
        reasons.append("5+G")
    return pts, reasons


def collect_skater_stats(game_id: int, wanted: set[int]) -> dict[int, dict]:
    """Return {playerId: {'goals': n, 'assists': n, 'side': 'away'|'home'}} for IDs in `wanted`."""
    if not wanted:
        return {}
    try:
        bs = boxscore(game_id)
    except Exception as e:
        print(f"  warn: boxscore {game_id} failed: {e}", file=sys.stderr)
        return {}
    out: dict[int, dict] = {}
    pbgs = bs.get("playerByGameStats", {})
    for side_key, side_label in (("awayTeam", "away"), ("homeTeam", "home")):
        team = pbgs.get(side_key, {})
        for group in ("forwards", "defense"):
            for p in team.get(group, []):
                pid = p.get("playerId")
                if pid in wanted:
                    out[pid] = {
                        "goals": p.get("goals", 0),
                        "assists": p.get("assists", 0),
                        "side": side_label,
                    }
    return out


# ---------- Subcommands ----------

def cmd_search(args) -> int:
    results = search_player(args.query, limit=args.limit)
    if not results:
        print("No players found.")
        return 0
    for r in results:
        pid = r.get("playerId")
        name = r.get("name", "").strip()
        team = r.get("teamAbbrev") or r.get("lastTeamAbbrev") or "?"
        pos = r.get("positionCode", "?")
        print(f"  {pid:>8}  {name:<28} {pos:<2}  {team}")
    return 0


def cmd_score(args) -> int:
    rosters = load_rosters()
    start = datetime.strptime(rosters["playoff_start_date"], "%Y-%m-%d").date()
    end = date.today()

    if not args.json:
        print(f"Fetching playoff games {start} → {end} ...")
    games = collect_playoff_games(start, end)
    if not args.json:
        finished = sum(1 for g in games if is_finished(g.get("gameState", "")))
        live = len(games) - finished
        print(f"  found {finished} finished + {live} live playoff game(s)")

    # Build all wanted player IDs
    all_skater_ids: set[int] = set()
    for m in rosters["managers"].values():
        for s in m.get("skaters", []):
            if s.get("id"):
                all_skater_ids.add(int(s["id"]))

    # Hydrate player metadata (cached) for headshots / sweater #s / current team
    if not args.json:
        print(f"  hydrating metadata for {len(all_skater_ids)} player(s) ...")
    player_meta = hydrate_player_meta(all_skater_ids)

    # Per-game: collect skater stats & team results
    skater_totals: dict[int, dict] = defaultdict(lambda: {"goals": 0, "assists": 0, "games": 0, "log": []})
    team_results: list[tuple[int, str, int, list[str], dict]] = []  # (gameId, tricode, pts, reasons, game)

    for g in games:
        # Team results & game-log entries only for FINISHED games — live game outcomes
        # are unknown until the buzzer.
        if is_finished(g.get("gameState", "")):
            for tri in (g["awayTeam"]["abbrev"], g["homeTeam"]["abbrev"]):
                pts, reasons = classify_team_result(g, tri)
                team_results.append((g["id"], tri, pts, reasons, g))
        # Skater stats accumulate from live + finished games.
        per_game = collect_skater_stats(g["id"], all_skater_ids)
        for pid, line in per_game.items():
            skater_totals[pid]["goals"] += line["goals"]
            skater_totals[pid]["assists"] += line["assists"]
            skater_totals[pid]["games"] += 1
            opp = g["homeTeam"]["abbrev"] if line["side"] == "away" else g["awayTeam"]["abbrev"]
            my_score = (g["awayTeam"] if line["side"] == "away" else g["homeTeam"])["score"]
            opp_score = (g["homeTeam"] if line["side"] == "away" else g["awayTeam"])["score"]
            skater_totals[pid]["log"].append({
                "date": (g.get("gameDate") or g.get("startTimeUTC", ""))[:10],
                "opp": opp,
                "home_or_away": line["side"],
                "team_score": my_score,
                "opp_score": opp_score,
                "goals": line["goals"],
                "assists": line["assists"],
                "points": line["goals"] * 2 + line["assists"],
            })

    # Now compute per-manager totals
    standings = []
    for name, m in rosters["managers"].items():
        team_pts = 0
        team_breakdown = []  # (tricode, pts, reasons_line)
        for tri in m.get("teams", []):
            tot = 0
            game_lines = []
            for gid, t, pts, reasons, g in team_results:
                if t != tri:
                    continue
                tot += pts
                opp = g["homeTeam"]["abbrev"] if tri == g["awayTeam"]["abbrev"] else g["awayTeam"]["abbrev"]
                my_score = (g["awayTeam"] if tri == g["awayTeam"]["abbrev"] else g["homeTeam"])["score"]
                opp_score = (g["homeTeam"] if tri == g["awayTeam"]["abbrev"] else g["awayTeam"])["score"]
                tag = ",".join(reasons) if reasons else "L"
                game_lines.append(f"      vs {opp}: {my_score}-{opp_score}  +{pts} ({tag})")
            team_pts += tot
            team_breakdown.append((tri, tot, game_lines))

        sk_pts = 0
        sk_breakdown = []
        for s in m.get("skaters", []):
            pid = int(s.get("id") or 0)
            line = skater_totals.get(pid, {"goals": 0, "assists": 0, "games": 0, "log": []})
            pts = line["goals"] * 2 + line["assists"]
            sk_pts += pts
            sk_breakdown.append((s["name"], pid, pts, line))
            # ensure key exists for downstream JSON
            line.setdefault("log", [])

        standings.append({
            "name": name,
            "total": team_pts + sk_pts,
            "team_pts": team_pts,
            "skater_pts": sk_pts,
            "team_breakdown": team_breakdown,
            "skater_breakdown": sk_breakdown,
            "teams": m.get("teams", []),
        })

    standings.sort(key=lambda x: x["total"], reverse=True)

    if args.json:
        # Pull today's playoff slate (live + scheduled + final).
        today = end
        try:
            today_payload = score_for_date(today)
        except Exception as e:
            print(f"  warn: failed to fetch today's slate: {e}", file=sys.stderr)
            today_payload = {"games": []}
        today_games = []
        for g in today_payload.get("games", []):
            if g.get("gameType") != PLAYOFF_GAME_TYPE:
                continue
            away = g.get("awayTeam", {})
            home = g.get("homeTeam", {})
            pd = g.get("periodDescriptor") or {}
            clock = g.get("clock") or {}
            ss = g.get("seriesStatus") or {}
            series_title = ss.get("seriesTitle") or ""
            game_no = ss.get("gameNumberOfSeries")
            if game_no:
                series_title = f"{series_title} · Game {game_no}".strip(" ·")
            top = ss.get("topSeedTeamAbbrev")
            bot = ss.get("bottomSeedTeamAbbrev")
            tw = ss.get("topSeedWins") or 0
            bw = ss.get("bottomSeedWins") or 0
            if top and bot:
                if tw > bw:
                    series_status = f"{top} leads {tw}-{bw}"
                elif bw > tw:
                    series_status = f"{bot} leads {bw}-{tw}"
                else:
                    series_status = f"Tied {tw}-{bw}"
            else:
                series_status = ""
            today_games.append({
                "id": g.get("id"),
                "state": g.get("gameState"),  # FUT/PRE/LIVE/CRIT/OFF/FINAL/OVER/INT
                "start_utc": g.get("startTimeUTC"),
                "period": {
                    "number": pd.get("number"),
                    "type": pd.get("periodType"),
                } if pd else None,
                "clock": {
                    "time_remaining": clock.get("timeRemaining"),
                    "in_intermission": clock.get("inIntermission", False),
                    "running": clock.get("running", False),
                } if clock else None,
                "away": {
                    "tricode": away.get("abbrev"),
                    "name": (away.get("name") or {}).get("default"),
                    "logo_url": espn_logo_url(away.get("abbrev") or ""),
                    "score": away.get("score"),
                    "record": away.get("record"),
                },
                "home": {
                    "tricode": home.get("abbrev"),
                    "name": (home.get("name") or {}).get("default"),
                    "logo_url": espn_logo_url(home.get("abbrev") or ""),
                    "score": home.get("score"),
                    "record": home.get("record"),
                },
                "series_title": series_title,
                "series_status": series_status,
            })

        out = {
            "updated_at": datetime.utcnow().isoformat(timespec="seconds") + "Z",
            "playoff_start_date": rosters["playoff_start_date"],
            "games_processed": len(games),
            "today": {
                "date": today.isoformat(),
                "games": today_games,
            },
            "standings": [
                {
                    "rank": i,
                    "name": s["name"],
                    "total": s["total"],
                    "team_pts": s["team_pts"],
                    "skater_pts": s["skater_pts"],
                    "teams": [
                        {
                            "tricode": tri,
                            "logo_url": espn_logo_url(tri),
                            "points": pts,
                            "games": [
                                {
                                    "opp": (g["homeTeam"]["abbrev"] if tri == g["awayTeam"]["abbrev"] else g["awayTeam"]["abbrev"]),
                                    "goals_for": (g["awayTeam"] if tri == g["awayTeam"]["abbrev"] else g["homeTeam"])["score"],
                                    "goals_against": (g["homeTeam"] if tri == g["awayTeam"]["abbrev"] else g["awayTeam"])["score"],
                                    "points": gp,
                                    "tags": greasons or ["L"],
                                    "date": (g.get("gameDate") or g.get("startTimeUTC", ""))[:10],
                                }
                                for gid, t, gp, greasons, g in team_results if t == tri
                            ],
                        }
                        for tri, pts, _ in s["team_breakdown"]
                    ],
                    "skaters": [
                        {
                            "name": nm,
                            "player_id": pid,
                            "team_tricode": (player_meta.get(pid) or {}).get("team_tricode"),
                            "sweater_number": (player_meta.get(pid) or {}).get("sweater_number"),
                            "headshot_url": (player_meta.get(pid) or {}).get("headshot_url"),
                            "hero_url": (player_meta.get(pid) or {}).get("hero_url"),
                            "goals": line["goals"],
                            "assists": line["assists"],
                            "games_played": line["games"],
                            "points": pts,
                            "games": sorted(line.get("log", []), key=lambda x: x.get("date", "")),
                        }
                        for nm, pid, pts, line in s["skater_breakdown"]
                    ],
                }
                for i, s in enumerate(standings, 1)
            ],
        }
        print(json.dumps(out, indent=2))
        return 0

    # Print leaderboard
    print()
    print(f"{'Rank':<5}{'Manager':<10}{'Teams':<14}{'Team':>6}{'Skater':>8}{'Total':>8}")
    print("-" * 51)
    for i, s in enumerate(standings, 1):
        teams = "/".join(s["teams"])
        print(f"{i:<5}{s['name']:<10}{teams:<14}{s['team_pts']:>6}{s['skater_pts']:>8}{s['total']:>8}")

    if args.verbose:
        print()
        for s in standings:
            print(f"\n=== {s['name']} ({s['total']} pts) ===")
            for tri, pts, lines in s["team_breakdown"]:
                print(f"  {tri}: {pts} pts")
                for ln in lines:
                    print(ln)
            print("  Skaters:")
            for nm, _pid, pts, line in s["skater_breakdown"]:
                print(f"    {nm:<24} {line['goals']}G {line['assists']}A  ({line['games']} GP)  = {pts} pts")
    return 0


def cmd_games(args) -> int:
    rosters = load_rosters()
    start = datetime.strptime(rosters["playoff_start_date"], "%Y-%m-%d").date()
    end = date.today()
    games = collect_playoff_games(start, end)
    print(f"{len(games)} finished playoff game(s):")
    for g in sorted(games, key=lambda x: x.get("startTimeUTC", "")):
        a = g["awayTeam"]; h = g["homeTeam"]
        period = g.get("periodDescriptor", {}).get("periodType", "REG")
        suffix = f" ({period})" if period != "REG" else ""
        date_str = (g.get("gameDate") or g.get("startTimeUTC", ""))[:10]
        print(f"  {date_str}  {a['abbrev']} {a.get('score',0)} @ {h['abbrev']} {h.get('score',0)}{suffix}  [game {g['id']}]")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description="Fantasy hockey playoff scorer")
    sub = p.add_subparsers(dest="cmd")

    sp = sub.add_parser("search", help="Search NHL players by name")
    sp.add_argument("query")
    sp.add_argument("--limit", type=int, default=10)
    sp.set_defaults(func=cmd_search)

    sp = sub.add_parser("score", help="Compute current standings (default)")
    sp.add_argument("-v", "--verbose", action="store_true")
    sp.add_argument("--json", action="store_true", help="Emit machine-readable JSON to stdout")
    sp.set_defaults(func=cmd_score)

    sp = sub.add_parser("games", help="List playoff games seen so far")
    sp.set_defaults(func=cmd_games)

    args = p.parse_args()
    if not args.cmd:
        # default to score
        args = p.parse_args(["score"])
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
