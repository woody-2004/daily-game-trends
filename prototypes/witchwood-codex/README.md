# Witchwood (in "game")

This is **not** the Night Shift prototype — it's a separate Roblox experience
(universe `10440164192`, place `129932135691270`, publicly named "game")
built on Roblox's stock Village template plus a hand-built "Witchwood"
expansion and a working Night Shift–style game loop, all created by a
different tool ("Codex") before this repo's assistant ever touched it.

## What's here

- `game.rbxl` — the full binary place file, as published, for reference/backup.
- `CodexNightShift_GameManager.server.lua` — the server game loop (day/night/
  vote/reveal, mole role, wards, The Watcher), extracted from the place.
- `diverse_ward_placement.lua` — just the block that was added to the
  original script, moving the 5 generic ward markers onto real existing
  structures (Smithy, Mill, Dock, Bridge, Witch Hut, Rune Tower, a House,
  a Cottage) instead of leaving them as unlabeled floating parts.

## v2 additions

- A fix for the Codex_Expanded_Map_Witchwood group sitting
  underground/underwater: raycasts under one reference part to find
  the real terrain surface, then shifts every part in the group by
  that same delta so relative spacing (e.g. the Witch Hut's base and
  roof) stays intact. Confirmed working live (shifted ~22 studs).
- A flicker on the existing SafeZone_Lamp's light.

## v3: Creator Store assets don't work from a live server

v2 first tried loading 4 landmark buildings and a flashlight mesh via
`InsertService:LoadAsset` using free Creator Store model IDs (the same
approach used successfully in the separate Night Shift prototype).
Live testing (via Roblox Studio's own AI Assistant running the actual
game and reading the Output log) showed **all five asset loads failed**
with `"User is not authorized to access Asset"`.

This is a Roblox platform restriction, not a bad ID or a bug: a script
running in a live server can only `InsertService:LoadAsset` assets
owned by the experience's creator (or explicitly permitted) — being a
free/insertable-via-Toolbox-UI model does not make it loadable this
way at runtime. Swapping to different asset IDs would hit the same
wall.

v3 replaces both blocks with procedural construction (parts/unions
built directly, the same technique used throughout the Night Shift
prototype) so every zone always has a real building with zero external
dependency:
- **Camp House**: log cabin walls + pitched roof spanning the ward
  cluster at the center, around the existing SafeZone_Lamp/Ring.
- **Farm House & Lake**: red barn to the SE with a grain silo.
- **Warehouse**: fully-roofed grey concrete block to the SW, small
  doorway, no windows — absolute cover, matching the brief.
- **Factory**: industrial shed to the NE with a chainlink-style
  perimeter (three deliberate gaps for the three approach paths) and
  loose pipe clutter.
- **Flashlight**: a two-tone metal/rubber handle with a neon lens,
  built from three welded parts — same functional SpotLight as before.

## How the update was made

The only change made to the live place was a **surgical binary patch**:
the `Source` property of the `CodexNightShift_GameManager` script was
replaced in-place inside the `.rbxl` binary (found and rewritten via the
Roblox binary format's `PROP` chunk for that one instance), leaving every
other one of the ~22,000 instances in the place — every hand-placed
building, tree, lantern, and the other 32 scripts — byte-identical.
This was necessary because the place's art (Village template + Witchwood
expansion) can't be reconstructed from scratch without losing fidelity;
only the one script needed to change.

Do not run `build_rbxlx.py` or `publish.sh` from `../night-shift-roblox/`
against this place — those target a different universe/place entirely.

## v4: retry real Creator Store assets, fix the "clumped in center" bug

Two separate problems from v3, both addressed:

1. **Asset quality.** After v3 shipped, the same 4 landmark buildings (and
   the flashlight mesh) failed `InsertService:LoadAsset` with `"User is
   not authorized to access Asset"`. The user reported changing something
   asset-permission-related in the Creator Store/Dashboard and asked to
   retry. v4 re-attempts `InsertService:LoadAsset` for the same 5 asset
   IDs first; if a load now succeeds, that real model is scaled to the
   target footprint and used. If it still fails, the exact v3 procedural
   part-built shell/flashlight is used as a fallback — so the place always
   renders a real building/tool either way, and the Output log states
   which path each one took (`InsertService SUCCEEDED` / `failed ... using
   procedural fallback`), which is the only way to confirm live whether
   the new access actually changed anything, since this environment can't
   run the Roblox client itself.
2. **Positioning.** v3 placed all 4 buildings at fixed offsets from
   `Safe.Position`, and Camp House was built exactly *at* `Safe.Position`
   — which the user confirmed genuinely overlaps/clumps with the
   pre-existing hand-placed hamlet (screenshot showed roofs intersecting,
   ward lights poking through walls). v4 no longer hardcodes any offsets:
   it scans every `BasePart` under `Structures`, `Codex_Expanded_Map_
   Witchwood`, and `CodexGameplay` to compute the real bounding footprint
   of the existing scene, then places each of the 4 buildings outside
   that footprint (existing half-extent + 55-stud margin) in a distinct
   compass direction — Camp House north, Factory northeast, Farm House
   southeast, Warehouse southwest — so they can't clump with or overlap
   the original art no matter how large or off-center it actually is.
