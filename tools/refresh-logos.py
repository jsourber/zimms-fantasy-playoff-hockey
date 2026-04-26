#!/usr/bin/env python3
"""Bundle only the team logos the app actually needs.

Determines required teams from the union of:
  1. Teams in rosters.json (the league's drafted teams)
  2. Any team that played a playoff game in the last 30 days OR is on the
     schedule for the next 14 days (i.e. still alive in the bracket)

Then syncs mac/PlayoffPool/Logos/ — adding missing PNGs from ESPN's CDN
and removing any that aren't needed anymore.

Run this once at the start of the playoffs and again whenever a round ends.
"""
from __future__ import annotations

import json
import sys
import urllib.request
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ROSTERS = ROOT / "rosters.json"
DEST = ROOT / "mac" / "PlayoffPool" / "Logos"
USER_AGENT = "fantasy-hockey-scorer/1.0"

# ESPN uses different abbreviations than the NHL for a few clubs.
ESPN_ALIASES = {"TBL": "tb", "LAK": "la", "SJS": "sj", "NJD": "nj"}


def fetch_active_playoff_teams() -> set[str]:
    """Any team that's appeared in a playoff game from -30d to +14d."""
    teams: set[str] = set()
    today = date.today()
    for delta in range(-30, 15):
        d = today + timedelta(days=delta)
        try:
            req = urllib.request.Request(
                f"https://api-web.nhle.com/v1/score/{d.isoformat()}",
                headers={"User-Agent": USER_AGENT},
            )
            data = json.loads(urllib.request.urlopen(req, timeout=10).read())
        except Exception as e:
            print(f"  warn: {d} fetch failed: {e}", file=sys.stderr)
            continue
        for g in data.get("games", []):
            if g.get("gameType") == 3:  # playoffs
                teams.add(g["awayTeam"]["abbrev"])
                teams.add(g["homeTeam"]["abbrev"])
    return teams


def download_logo(tri: str, out: Path) -> int:
    url_part = ESPN_ALIASES.get(tri.upper(), tri.lower())
    url = f"https://a.espncdn.com/i/teamlogos/nhl/500/{url_part}.png"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=15) as resp:
        data = resp.read()
    out.write_bytes(data)
    return len(data)


def main() -> int:
    rosters = json.loads(ROSTERS.read_text())
    roster_teams: set[str] = set()
    for m in rosters["managers"].values():
        roster_teams.update(m.get("teams", []))

    print(f"Drafted teams ({len(roster_teams)}): {sorted(roster_teams)}")
    playoff_teams = fetch_active_playoff_teams()
    print(f"Currently active playoff teams ({len(playoff_teams)}): {sorted(playoff_teams)}")

    needed = roster_teams | playoff_teams
    print(f"\nNeeded ({len(needed)}): {sorted(needed)}\n")

    DEST.mkdir(parents=True, exist_ok=True)

    existing = {p.stem.replace("logo-", "") for p in DEST.glob("logo-*.png")}
    to_add = sorted(needed - existing)
    to_remove = sorted(existing - needed)

    for tri in to_remove:
        (DEST / f"logo-{tri}.png").unlink()
        print(f"  - removed {tri}")

    for tri in to_add:
        try:
            n = download_logo(tri, DEST / f"logo-{tri}.png")
            print(f"  + added   {tri}  ({n} bytes)")
        except Exception as e:
            print(f"  ! FAILED  {tri}: {e}", file=sys.stderr)
            return 1

    total = sum((DEST / f"logo-{t}.png").stat().st_size for t in needed if (DEST / f"logo-{t}.png").exists())
    print(f"\nBundle now has {len(needed)} logos, {total // 1024} KB total.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
