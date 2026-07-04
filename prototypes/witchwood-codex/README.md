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

- `v2_additions.lua` — appended on top of the v1 (diverse ward
  placement) script. Adds:
  - A fix for the Codex_Expanded_Map_Witchwood group sitting
    underground/underwater: raycasts under one reference part to find
    the real terrain surface, then shifts every part in the group by
    that same delta so relative spacing (e.g. the Witch Hut's base and
    roof) stays intact.
  - A flashlight tool (players had none before), meshed with a free
    Creator Store asset ("Flashlight Handheld Lamp Dark Tool Light").
  - Four landmark buildings from the Creator Store, placed relative to
    the existing SafeZone_Lamp: a log cabin at center (Discussion
    Hall), an abandoned barn to the SE (Farm House), an abandoned
    building to the SW (Warehouse), and an industrial factory to the
    NE — matching the building-placement-matrix brief.
  - A flicker on the existing SafeZone_Lamp's light.

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
