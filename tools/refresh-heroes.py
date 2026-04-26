#!/usr/bin/env python3
"""Bundle action-shot 'hero' images for every drafted skater.

Reads rosters.json → for each skater, asks NHL's /player/{id}/landing for the
heroImage URL → downloads, downscales to ~800px wide, and writes
mac/PlayoffPool/Heroes/hero-{playerId}.jpg.

JPEG instead of PNG because hero shots are photographic and JPEG cuts size
roughly 4-5x at no visible quality loss.
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

# We display the hero at 240pt tall (~720px on 3x). 800px wide is plenty.
TARGET_W = 800
JPEG_QUALITY = 80

ROOT = Path(__file__).resolve().parent.parent
ROSTERS = ROOT / "rosters.json"
DEST = ROOT / "mac" / "PlayoffPool" / "Heroes"
USER_AGENT = "fantasy-hockey-scorer/1.0"


def http_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.loads(resp.read().decode("utf-8"))


def http_bytes(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=20) as resp:
        return resp.read()


def main() -> int:
    if not HAVE_PIL:
        print("Pillow (PIL) is required. `pip install Pillow`", file=sys.stderr)
        return 2

    rosters = json.loads(ROSTERS.read_text())
    wanted: dict[int, str] = {}
    for m in rosters["managers"].values():
        for s in m.get("skaters", []):
            if s.get("id"):
                wanted[int(s["id"])] = s["name"]
    print(f"Drafted skaters ({len(wanted)})")

    DEST.mkdir(parents=True, exist_ok=True)

    existing = {int(p.stem.replace("hero-", "")) for p in DEST.glob("hero-*.jpg")}
    to_remove = existing - set(wanted.keys())
    to_add = set(wanted.keys()) - existing

    for pid in sorted(to_remove):
        (DEST / f"hero-{pid}.jpg").unlink()
        print(f"  - removed {pid}")

    failed = 0
    for pid in sorted(to_add):
        try:
            landing = http_json(f"https://api-web.nhle.com/v1/player/{pid}/landing")
            url = landing.get("heroImage")
            if not url:
                print(f"  ! no heroImage URL for {pid} ({wanted[pid]})", file=sys.stderr)
                continue
            raw = http_bytes(url)
            im = Image.open(io.BytesIO(raw)).convert("RGB")
            if im.width > TARGET_W:
                ratio = TARGET_W / im.width
                im = im.resize((TARGET_W, int(im.height * ratio)), Image.LANCZOS)
            buf = io.BytesIO()
            im.save(buf, format="JPEG", quality=JPEG_QUALITY, optimize=True)
            data = buf.getvalue()
            (DEST / f"hero-{pid}.jpg").write_bytes(data)
            print(f"  + added   {pid:>8}  {wanted[pid]:<24} ({len(data) // 1024} KB)")
        except Exception as e:
            print(f"  ! FAILED  {pid} ({wanted[pid]}): {e}", file=sys.stderr)
            failed += 1

    total_files = list(DEST.glob("hero-*.jpg"))
    total_bytes = sum(p.stat().st_size for p in total_files)
    print(f"\nBundle now has {len(total_files)} hero images, {total_bytes // 1024} KB total.")
    if failed:
        print(f"  ({failed} failures — those skaters will fall back to network)", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
