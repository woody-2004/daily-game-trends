# Night Shift — Developer Specification & Handoff

Everything a developer needs to understand, run, modify, and extend the game. Read this alongside `README.md` (player-facing overview) and `LAUNCH.md` (store/publishing package).

---

## 1. What the game is

**Night Shift** is a round-based multiplayer game for Roblox: **co-op survival horror + hidden traitor (social deduction)**.

- **Players:** 3–8 per server (auto-starts 10 seconds after the 3rd player joins).
- **Premise:** The crew must survive **3 nights** in a dark facility by keeping 5 generators running. A monster, **The Watcher**, hunts anyone outside the central lamp's safe zone at night. One randomly chosen player is secretly **The Mole**, who sabotages generators and lures the monster while pretending to help.
- **Session length:** ~7–8 minutes per match with default timings.
- **Platform:** Roblox (Luau, `--!strict`). Designed for proximity voice chat.

### Match flow (state machine)

```
lobby → [3+ players, 10s countdown]
  → for each night 1..3:
      day (40s)   — lights on, repair generators, discuss
      night (75s) — darkness + fog, generators decay, Watcher hunts
      dawn vote (20s, after nights 1 and 2 only) — majority exile
  → reveal (20s) — winner, mole identity, survivors
  → back to lobby
```

### Roles

| Role | Count | Goal | Abilities |
|---|---|---|---|
| **Crew** | all but one | Exile the mole, or have ≥1 crew member alive after night 3 | Repair generators (ProximityPrompt hold), flashlight |
| **Mole** | 1, random | Crew fails (Watcher takes everyone) | Everything crew has, plus per night: **2 Sabotages** (−60 health to the healthiest running generator, 20s cooldown, feed shows an unattributed "Generator G-X is failing fast!") and **1 Lure** (Watcher targets a chosen player for 8s) |

### Core mechanics

- **Generators (5):** 100 health each, arranged in a circle (radius 52 studs). Decay 4 hp/s during night only. Repairing (0.6s hold prompt, 9-stud range) adds +10 per trigger. A generator "breaks" at 0 health (light off, red body, feed message) and revives once repaired back to 30.
- **Safe zone:** central lamp, radius 14 studs. Active while **fewer than 3** generators are broken (`brokenCount < ceil(5/2)`). While active, players inside are untargetable and unkillable.
- **The Watcher:** server-driven monster (no Humanoid — a pivoted anchored model). Targets the lured player if a lure is active, else the nearest living player outside an active safe zone. Speed = 9 + 3 per broken generator (player walk speed is 16); **doubles** on total blackout (all 5 broken). Kills within 4.5 studs, then pauses 3s ("feast"). If no valid target, it circles the lamp at radius 20. Hidden below the map (Y = −80) during day/lobby. **It does not pathfind — it glides through walls** (known limitation, roadmap item).
- **Death & ghosts:** Watcher victims become ghosts (Humanoid health set to 0, `ghost = true`); they respawn at the **next dawn**. Exiled players are ghosts permanently (`exiled = true`, never revived).
- **Dawn vote:** after nights 1 and 2. Living players vote for a suspect or skip (UserId 0). Exile requires a strict majority of living players and no tie. Exiling the mole → instant crew win. Exiling an innocent → they're permanently ghosted, match continues.
- **Disconnects:** a leaving player becomes a ghost; if the **mole** leaves, the crew wins immediately ("The mole fled the facility").

### Win conditions

| Outcome | Condition |
|---|---|
| Crew wins | Mole exiled at a dawn vote, mole disconnects, or ≥1 living **crew** member after night 3 |
| Mole wins | All living players eliminated (or only the mole left alive) at any point during a night, or zero crew standing after night 3 |

---

## 2. Repository layout

```
prototypes/night-shift-roblox/
├── GameManager.server.lua   # ALL server logic (~925 lines) → ServerScriptService
├── ClientUI.client.lua      # ALL client UI/FX (~445 lines) → StarterPlayerScripts
├── NightShift.rbxlx         # one-click place file with both scripts embedded
├── publish.sh               # Open Cloud publish script (API key via env var)
├── README.md                # concept, setup, tuning knobs, roadmap
├── LAUNCH.md                # store copy, asset briefs, QA checklist, launch steps
└── DEVELOPER_SPEC.md        # this file
```

**Architecture principle: zero manual setup.** Both scripts build everything at runtime — arena geometry, lighting, the monster, tools, sounds, RemoteEvents, and every UI element. There are no prefabs, no assets to import, no Explorer wiring. To run: paste the two scripts into a Baseplate place (or open `NightShift.rbxlx`) and start a multi-client test with 3+ players.

---

## 3. Server: `GameManager.server.lua`

Single script in `ServerScriptService`. `Players.CharacterAutoLoads = false` — the match flow controls all spawning via `LoadCharacter()`.

### Section map (in file order)

| Section | What it does |
|---|---|
| `SOUND_IDS` + `makeSound()` | Sound asset table (all placeholder `rbxassetid://0` — see §7) and a helper that builds configured `Sound` instances |
| CONFIG | All tuning constants (see §6) |
| REMOTES | Creates `ReplicatedStorage.NightShiftRemotes` folder + 10 RemoteEvents (see §5) |
| STATE | `Crew` and `Generator` types; module-level `phase`, `nightNumber`, `timeLeft`, `crew` (keyed by UserId), `generators`, `matchActive` |
| ARENA | Builds floor (140×140), 4 perimeter walls, 6 fixed cover walls, central lamp + neon safe ring, invisible spawn point — all in `Workspace.NightShiftArena` |
| Generators | `buildGenerators()` places 5 generator models on a circle; each gets a PointLight, ProximityPrompt (repair), BillboardGui health bar, and 3 positional sounds. `updateGeneratorVisual()` syncs light/color/bar/hum. `markGeneratorBroken()` is the single break entry point |
| LIGHTING | `setDay()` / `setNight()` — ClockTime, ambient colors, fog (FogEnd 1000 day / 80 night), swaps ambient loops |
| FLASHLIGHT + GAME PASSES | `GAME_PASSES` (3 cosmetic beam skins, placeholder id 0), `ownsPass()` with per-user cache, `giveFlashlight()` (Tool + SpotLight, beam color from owned pass), purchase prompt handling (see §8) |
| MONSTER | Builds The Watcher model; `monsterStep(dt)` implements targeting/movement/kill (see §1) |
| SYNC | `publicState()` → everything clients may see; `syncAll()` broadcasts it; `sendPrivate(c)` sends role/charges to one player (role secrecy boundary) |
| MOLE ACTIONS | Server handlers for `SabotageRequest`, `LureRequest`, `VoteCast` — all validate role/phase/charges/cooldowns server-side |
| MATCH FLOW | `runMatch()` (enrollment, role assignment, the day/night loop), `runVote()`, `endMatch()` |
| PLAYER LIFECYCLE | Join (spawn + "match in progress" toast), leave (ghost + mole-flee win) |
| MAIN LOOP | Infinite `task.spawn` loop: in lobby, counts players, runs the 10s countdown, calls `runMatch()` |

### Key server functions

- **`runMatch()`** — the heart. Enrolls every present player into `crew`, assigns one random mole, resets generators, spawns characters, sends role toasts, hands out flashlights, then loops 3 nights: day phase (0.5s ticks: revive non-exiled ghosts, reset mole charges, sync), night phase (0.1s ticks: generator decay, `monsterStep`, loss check, sync every 0.5s), dawn vote after nights 1–2. Ends via `endMatch()`.
- **`monsterStep(dt)`** — targeting priority: active lure > nearest living player outside active safe zone > nobody (circle the lamp). Movement is manual XZ interpolation via `PivotTo` at Y=3.5. Kill check re-validates safe zone at the moment of contact.
- **`runVote()`** — 20s window; tallies non-ghost votes; strict-majority-no-tie exile; returns `true` if exiling the mole ended the match.
- **`endMatch(crewWin, reason)`** — fires `Reveal` to all clients, parks the monster, restores day, waits 20s, clears `crew`, returns phase to lobby.
- **Anti-cheat posture:** all authority is server-side. Mole ability handlers verify `role == "mole"`, `phase == "night"`, charge counts, and cooldowns; vote handler verifies `phase == "vote"` and non-ghost; repair prompt verifies enrollment and non-ghost. Remote args are typed `unknown` and type-checked before use. Roles are never in the public state broadcast — only `PrivateState` carries them.

---

## 4. Client: `ClientUI.client.lua`

Single LocalScript in `StarterPlayer > StarterPlayerScripts`. Builds a `ScreenGui` named `NightShiftUI` (`ResetOnSpawn = false`) entirely in code via three factory helpers (`label`, `panel`, `button`).

### UI inventory

| Element | Purpose |
|---|---|
| **Top bar** | Phase ("☀ DAY 1/3", "🌑 NIGHT 2/3"…), countdown timer, generator status ("⚙ 4/5 up — 🏮 lamp SAFE", turns red when the safe zone fails) |
| **Role panel** (top-left) | "🔦 CREW" or "🔪 THE MOLE" (from `PrivateState` only) |
| **Feed panel** (bottom-left) | Rolling event log, max 6 lines (repairs, failures, kills, votes) |
| **Sabotage / Lure buttons** (bottom-right) | Only visible to the mole. Show charge counts; sabotage shows live cooldown ("⚡ … 12s"); grey out when unusable. Lure opens a scrollable target picker of living players |
| **Skins button + shop panel** (left) | 3 flashlight-skin buttons → `PurchasePass:FireServer(index)` |
| **Vote overlay** (center) | Suspect list + Skip; shown to living players in vote phase; hides after voting (`votedThisDawn` resets on each new vote phase) |
| **Toast** (top-center) | Private 5s messages (role assignment, death notice, lure confirmation) |
| **Reveal overlay** (center) | "🏆 CREW WINS" / "🔪 THE MOLE WINS", mole's name, reason, survivor list |

### Client-side FX

- **Proximity heartbeat:** on `RunService.Heartbeat`, distance from the local character to the last-synced monster position drives a looped heartbeat sound — volume 0→0.9 and playback speed 0.9→1.7 as the Watcher closes within 55 studs. Silent when it's day, you're a ghost, or the monster is out of range.
- **Stingers:** server fires `PlayStinger("killStinger" | "dawnChime" | "voteBell")`; client instantiates a one-shot Sound and self-destroys it.

The client is **presentation-only**: it renders state pushed from the server and sends requests. It holds no authoritative data; a modified client can at most see the public state every client receives (monster position is only included in night phase).

---

## 5. Remote protocol (`ReplicatedStorage.NightShiftRemotes`)

### Server → client

| RemoteEvent | Payload | Cadence |
|---|---|---|
| `StateSync` | `{ phase, night, totalNights, timeLeft, safeZone, brokenGens, totalGens, players[{userId,name,ghost,exiled}], generators[{id,health,broken}], monsterPos?{x,y,z} }` | ~every 0.5s during a match; every 1s in lobby. `monsterPos` is nil outside night phase |
| `PrivateState` | `{ role, sabotageCharges, sabotageCooldownLeft, lureCharges, ghost }` | To one player, on enrollment / dawn / after each ability use |
| `Feed` | message string | Event-driven, all clients |
| `Toast` | message string | Event-driven, one client |
| `Reveal` | `{ crewWin, reason, moleName, survivors[] }` | Once at match end, all clients |
| `PlayStinger` | sound key string | Event-driven, all clients |

### Client → server (all validated server-side)

| RemoteEvent | Payload | Guards |
|---|---|---|
| `SabotageRequest` | none | mole, alive, night, charges > 0, cooldown elapsed |
| `LureRequest` | target UserId | mole, alive, night, charges > 0, target valid/living/not-self |
| `VoteCast` | suspect UserId (0 = skip) | non-ghost, vote phase |
| `PurchasePass` | pass index (1–3) | index valid, pass id ≠ 0 → `PromptGamePassPurchase` |

---

## 6. Tuning constants (top of `GameManager.server.lua`)

| Constant | Default | Notes |
|---|---|---|
| `MIN_PLAYERS` | 3 | 4+ recommended for good deduction |
| `NIGHTS` / `DAY_SECONDS` / `NIGHT_SECONDS` | 3 / 40 / 75 | Match pacing |
| `VOTE_SECONDS` / `REVEAL_SECONDS` / `LOBBY_COUNTDOWN` | 20 / 20 / 10 | |
| `GENERATOR_COUNT` | 5 | Safe zone fails at `ceil(count/2)` broken |
| `GEN_DECAY_PER_SEC` / `GEN_REPAIR_BOOST` / `GEN_REVIVE_THRESHOLD` | 4 / 10 / 30 | Decay is night-only; repair is per prompt trigger |
| `MONSTER_BASE_SPEED` / `MONSTER_SPEED_PER_BROKEN_GEN` | 9 / 3 | Player walk speed is 16; blackout doubles the total |
| `MONSTER_KILL_RADIUS` / `MONSTER_FEAST_PAUSE` | 4.5 / 3 | |
| `SAFE_ZONE_RADIUS` | 14 | Studs from the lamp |
| `MOLE_SABOTAGE_PER_NIGHT` / `MOLE_SABOTAGE_DAMAGE` / `MOLE_SABOTAGE_COOLDOWN` | 2 / 60 / 20 | Sabotage always hits the healthiest running generator |
| `MOLE_LURE_PER_NIGHT` / `MOLE_LURE_DURATION` | 1 / 8 | |
| `ARENA_SIZE` / `GEN_CIRCLE_RADIUS` | 140 / 52 | |

---

## 7. Sound system (needs asset IDs before launch)

Fully wired but **ships silent**: every ID is the placeholder `rbxassetid://0` (invalid ID = no sound, no error). Two tables to fill:

- `SOUND_IDS` (server): `ambientDay`, `ambientNight`, `generatorHum` (per-generator positional loop, night only, stops on break), `generatorFail`, `monsterGrowl` (positional loop on the Watcher), `repairTick`, plus unused server-side keys.
- `STINGER_IDS` + `heartbeatSound.SoundId` (client): `killStinger`, `dawnChime`, `voteBell`, heartbeat loop.

Swap procedure and Toolbox search terms per key are in `LAUNCH.md` §4 (~15 minutes in Studio; Toolbox audio is Studio-only, so this step is manual).

---

## 8. Monetization (cosmetic only)

Three flashlight-skin **Game Passes** — Ember / Spectral / Bloodhunter beams (beam + handle colors, zero gameplay effect):

1. Create the passes in Creator Dashboard → Monetization → Passes (suggested 49–99 Robux).
2. Paste the numeric IDs into `GAME_PASSES` at the top of the server script. `id = 0` entries are safely inert.

Server-side flow: `ownsPass()` checks `UserOwnsGamePassAsync` with a per-user session cache (cleared on leave); `giveFlashlight()` applies the **last** owned pass in the list; `PromptGamePassPurchaseFinished` updates the cache and hot-swaps the equipped flashlight on purchase.

---

## 9. Known limitations / current TODO state

1. **Placeholder sound IDs** — game is silent until §7 is done.
2. **Placeholder Game Pass IDs** — skins shop prompts nothing until §8 is done.
3. **Watcher has no pathfinding** — it glides through walls and cover. Roadmap: `PathfindingService`.
4. **Repair is trigger-spam** — hold prompt fires discrete +10 boosts; no task variety yet (roadmap: fuse mini-puzzles, two-person switches).
5. **Fixed map layout** — same arena every match (intentional for learnability now; random layouts on the roadmap).
6. **Mobile untested** — UI uses fixed-offset positioning; scaled but unverified on small screens (`LAUNCH.md` §3).
7. **Late joiners spectate** — players joining mid-match spawn and roam but aren't enrolled until the next match; they see the lobby toast.
8. **Vote UI lists only living non-self players** — ghosts can't vote (by design) and dead players can't be voted for.

## 10. Roadmap (priority order, from README)

1. Playtest for the terror/comedy blend (the Lethal Company effect) — validates the concept.
2. Task variety beyond repair-holding (forces the crew to split up — more mole opportunities).
3. Watcher pathfinding via `PathfindingService`.
4. Multiple monster types; randomized facility layouts.
5. More cosmetics: ghost appearances, victory poses, kill effects.

## 11. Testing & publishing

- **Local test:** Studio → Test tab → Clients and Servers → Players: 3+ → Start. Full QA script: `LAUNCH.md` §5.
- **Publish via API:** `publish.sh` pushes `NightShift.rbxlx` through Open Cloud (`ROBLOX_API_KEY` env var required, plus universe/place IDs). Manual steps that can't be automated (passes, voice chat, going public) are listed in `LAUNCH.md` §7.

## 12. Context: why this game

Backed by the repo's trend database (`trends/`, `trends_summary.md`, `game_concepts.md`): night-based co-op survival horror is the breakout Roblox format (99 Nights in the Forest, 14.2M peak CCU), and traitor/social-deception hybrids are a flagged market gap. Night Shift merges the proven horror loop with the sabotage layer prototyped earlier in `prototypes/best-friends-roblox/`. Proximity voice chat is the core product bet — fear + betrayal is the differentiator, not graphics.
