#!/usr/bin/env python3
"""Bundle skater headshots for every drafted player.

Reads rosters.json → for each skater, asks NHL's /player/{id}/landing for the
current headshot URL → downloads it to mac/PlayoffPool/Headshots/headshot-{playerId}.png.

Re-run if rosters.json ever changes (it shouldn't mid-playoffs).
"""
from __future__ import annotations

import io
import json
import sys
import urllib.request
from pathlib import Path

try:
    from PIL import Image
    HAVE_PIL = True
except ImportError:
    HAVE_PIL = False

# Largest size we display the headshot at (Detail view hero is ~100pt @3x = 300px).
TARGET_PX = 256

ROOT = Path(__file__).resolve().parent.parent
ROSTERS = ROOT / "rosters.json"
DEST = ROOT / "mac" / "PlayoffPool" / "Headshots"
USER_AGENT = "fantasy-hockey-scorer/1.0"


def http_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))


def http_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return resp.read()


def main() -> int:
    rosters = json.loads(ROSTERS.read_text())
    wanted: dict[int, str] = {}
    for m in rosters["managers"].values():
        for s in m.get("skaters", []):
            if s.get("id"):
                wanted[int(s["id"])] = s["name"]
    print(f"Drafted skaters ({len(wanted)})")

    DEST.mkdir(parents=True, exist_ok=True)

    existing = {int(p.stem.replace("headshot-", "")) for p in DEST.glob("headshot-*.png")}
    to_remove = existing - set(wanted.keys())
    to_add = set(wanted.keys()) - existing

    for pid in sorted(to_remove):
        (DEST / f"headshot-{pid}.png").unlink()
        print(f"  - removed {pid}")

    for pid in sorted(to_add):
        try:
            landing = http_json(f"https://api-web.nhle.com/v1/player/{pid}/landing")
            url = landing.get("headshot")
            if not url:
                print(f"  ! no headshot URL for {pid} ({wanted[pid]})", file=sys.stderr)
                continue
            png = http_bytes(url)
            if HAVE_PIL:
                im = Image.open(io.BytesIO(png)).convert("RGBA")
                if max(im.size) > TARGET_PX:
                    im.thumbnail((TARGET_PX, TARGET_PX), Image.LANCZOS)
                buf = io.BytesIO()
                im.save(buf, format="PNG", optimize=True)
                png = buf.getvalue()
            (DEST / f"headshot-{pid}.png").write_bytes(png)
            print(f"  + added   {pid:>8}  {wanted[pid]:<24} ({len(png)} B)")
        except Exception as e:
            print(f"  ! FAILED  {pid} ({wanted[pid]}): {e}", file=sys.stderr)
            return 1

    total_files = list(DEST.glob("headshot-*.png"))
    total_bytes = sum(p.stat().st_size for p in total_files)
    print(f"\nBundle now has {len(total_files)} headshots, {total_bytes // 1024} KB total.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
