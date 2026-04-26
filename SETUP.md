# Playoff Pool — setup (macOS first)

## What you have

- `scorer.py` — pulls NHL playoff scores, applies your league's rules, prints a leaderboard. Also has `--json` mode.
- `mac/PlayoffPool/*.swift` — SwiftUI macOS app. On refresh it shells out to `python3 scorer.py score --json` and renders the result.
- `.github/workflows/update-standings.yml` — for later (commits a `standings.json` to a public repo every 10 min, used by an iOS app).

## Run the Mac app

There's no `.xcodeproj` checked in. Easiest path:

1. **Open Xcode** → File → New → Project
2. Choose **macOS → App**, click Next
3. Settings:
   - Product Name: **PlayoffPool**
   - Team: your Apple ID (free is fine)
   - Organization Identifier: **com.jacobsourber**
   - Interface: **SwiftUI**, Language: **Swift**
   - Storage: None, Tests: off
4. Save it inside `mac/` (so you get `mac/PlayoffPool.xcodeproj`)
5. In the new project, **delete** the auto-generated `ContentView.swift` and `PlayoffPoolApp.swift` (move to trash)
6. **Drag** these four files from `mac/PlayoffPool/` into the Xcode project navigator (check "Copy items if needed" off, "Create groups" on, target = PlayoffPool):
   - `PlayoffPoolApp.swift`
   - `Models.swift`
   - `StandingsService.swift`
   - `LeaderboardView.swift`
   - `ManagerDetailView.swift`
7. **Disable App Sandbox** (so the app can spawn `python3`):
   - Click the project → PlayoffPool target → **Signing & Capabilities**
   - Find **App Sandbox**, click the **×** to remove it
8. Hit **▶ Run** (⌘R)

You should see the leaderboard. Click a manager to see their team game-by-game and skater stats. Refresh button (⌘R) re-runs `scorer.py`.

If the path to `scorer.py` is wrong, click the gear icon in the toolbar to override it.

## Editing the league

Edit `rosters.json` — the next refresh picks it up immediately (no rebuild needed).

## Useful CLI commands

```bash
python3 scorer.py                  # leaderboard
python3 scorer.py score -v         # full breakdown per manager
python3 scorer.py score --json     # what the Mac app consumes
python3 scorer.py games            # list playoff games processed
python3 scorer.py search "Name"    # find an NHL player ID
```

---

## Later: iOS / TestFlight (skip for now)

When you're happy with the Mac version and want it on your phone:

1. Push this folder to GitHub. The included Action will write `public/standings.json` every 10 min.
2. Create a new iOS target alongside `mac/`. Reuse `Models.swift`, `LeaderboardView.swift`, `ManagerDetailView.swift`. Replace `StandingsService.swift` with one that fetches the GitHub raw URL instead of running Python (the original version we built lives in git history).
3. Enroll in the Apple Developer Program ($99/yr) → Archive → upload to App Store Connect → distribute via TestFlight.
