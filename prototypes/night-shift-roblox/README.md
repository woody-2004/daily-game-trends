# Night Shift — Co-op Horror + Hidden Traitor (Roblox Prototype)

**3–8 friends survive 3 nights in a dark facility. One of you secretly wants everyone dead.**

Backed by the trend database: night-based co-op survival horror is the breakout format right now (99 Nights in the Forest, 14.2M peak CCU on Roblox), and "horror survival for non-Roblox platforms" / traitor hybrids are flagged opportunity zones. This merges the proven horror loop with the Best Friends sabotage/social-deception layer.

## How a match plays

- **Day (40s):** Lights on. Repair the 5 generators scattered around the facility. Talk. Plan. Suspect.
- **Night (75s):** Darkness + fog. **The Watcher** — a tall shadow with red eyes — hunts anyone outside the central lamp's safe zone. Generators decay and must be repaired *out there, in the dark*. If more than half go down, the lamp's safe zone fails too. Total blackout = the Watcher enrages.
- **The Mole:** One random player. Each night they get 2 disguised sabotages (feed just says *"Generator G-3 is failing fast!"*) and 1 **Lure** — silently steering the Watcher toward a chosen player. The mole wins if the crew doesn't make it.
- **Dawn vote:** After nights 1 and 2, the crew votes to exile someone. Exile the mole → crew wins instantly. Exile an innocent → they're a ghost for the rest of the match.
- **Deaths aren't permanent** — the Watcher's victims return as ghosts until dawn, so nobody sits out long.
- **Win conditions:** Crew wins by exiling the mole or having crew members alive after night 3. The mole wins if the Watcher takes everyone.

Everything ships in two scripts that build the whole game at runtime: arena, generators with health bars and repair prompts, day/night lighting + fog, flashlight tools, the Watcher's AI (targets nearest player outside the safe zone, speeds up per broken generator), all UI (role panel, mole abilities, dawn vote, reveal screen).

## Setup (5 minutes, no building required)

1. Open **Roblox Studio** → New → **Baseplate** template. *(Optional: delete the default Baseplate part — the script builds its own floor.)*
2. In Explorer:
   - Right-click **ServerScriptService** → Insert Object → **Script** → paste in `GameManager.server.lua`.
   - **StarterPlayer** → right-click **StarterPlayerScripts** → Insert Object → **LocalScript** → paste in `ClientUI.client.lua`.
3. **Test tab → Clients and Servers → Players: 3+ → Start.** Match auto-starts 10s after 3 players are in.
4. **Strongly recommended:** Game Settings → Communication → enable **proximity voice chat**. Hearing a friend's voice fade as they're dragged into the dark is the whole product.

## Tuning knobs (top of GameManager)

| Constant | Default | Effect |
|---|---|---|
| `NIGHTS` / `DAY_SECONDS` / `NIGHT_SECONDS` | 3 / 40 / 75 | Match pacing |
| `GEN_DECAY_PER_SEC` / `GEN_REPAIR_BOOST` | 4 / 10 | How hard nights push players out of the safe zone |
| `MONSTER_BASE_SPEED` / `MONSTER_SPEED_PER_BROKEN_GEN` | 9 / 3 | Terror scaling (player walk speed is 16) |
| `MOLE_SABOTAGE_PER_NIGHT` / `MOLE_LURE_PER_NIGHT` | 2 / 1 | Traitor power |
| `SAFE_ZONE_RADIUS` | 14 | Size of the lamp's protection |

## What's built in (beyond the core loop)

- **Full sound system** — day/night ambient loops, per-generator hum that cuts out on failure, monster growl, a proximity **heartbeat that speeds up as the Watcher closes in**, and stingers on kills/dawn/votes. Ships wired to placeholder IDs (silent) — swap in real free Toolbox audio in ~15 min, see `LAUNCH.md` §4.
- **Cosmetic monetization scaffolding** — 3 flashlight-skin Game Passes (Ember/Spectral/Bloodhunter beams) with server-side ownership checks, purchase prompts, and an in-game SKINS shop button. Cosmetic only, no pay-to-win. Create the passes in the Creator Dashboard and paste their IDs into `GAME_PASSES`, see `LAUNCH.md` §3.
- **`NightShift.rbxlx`** — one-click openable place file with everything embedded.
- **`LAUNCH.md`** — store copy, icon/thumbnail briefs, settings checklist, QA script, launch sequence.

## Roadmap after launch

1. **Playtest question #1:** do people scream *and* laugh? Horror-with-friends succeeds when terror and comedy blend (the Lethal Company effect).
2. Task variety beyond repair-holding (fuse mini-puzzles, two-person switches — forces splitting up).
3. Watcher pathfinding around walls (it currently glides through cover — spooky, but a smarter monster reads better) via `PathfindingService`.
4. Multiple monster types with different hunting rules; random facility layouts per match.
5. More cosmetics: ghost appearances, victory poses, kill effects.
