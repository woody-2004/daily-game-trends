# Night Shift — Launch Package

Everything needed to take the game from "published private place" to "live on Roblox," in order.

---

## 1. Store Listing (copy-paste ready)

**Title:**
```
Night Shift 🌑 [3-8 Players]
```

**Description:**
```
🔦 SURVIVE 3 NIGHTS. TRUST NO ONE. 🔦

Keep the generators running while THE WATCHER hunts in the dark.
But one of your friends is THE MOLE — secretly breaking generators
and luring the monster to you.

😱 Proximity voice chat recommended — hear your friends scream!
🗳 Vote each dawn: exile the traitor... or an innocent friend?
👻 Death isn't the end — ghosts return at dawn.
🌑 Every "power surge" might be sabotage. Or just bad luck. You'll never know.

3-8 players. Best with friends and voice chat.

⚙ UPDATES EVERY WEEK — leave feedback in the group!
```

**Genre:** Horror
**Sub-tags/keywords the algorithm likes:** horror, survival, traitor, social deduction, night, monster, friends, voice chat
**Max players per server:** 8 (matches MAX_PLAYERS in the script)

## 2. Icon & Thumbnail brief

You need 1 icon (512×512) and 1+ thumbnails (1920×1080). Make them in any image tool, or generate with an AI image tool with these prompts:

**Icon prompt:**
> Dark game icon, a glowing red pair of eyes in pitch darkness behind an unaware blocky Roblox-style character holding a flashlight, dramatic rim lighting, bold readable style, no text

**Thumbnail prompt:**
> Roblox-style horror game thumbnail, group of blocky characters around a lamppost in a dark facility at night, one character secretly smirking while sabotaging a generator behind the others, a tall shadow monster with red eyes approaching in the fog, cinematic lighting, bold "NIGHT SHIFT" title text

Thumbnail rule of thumb: the **traitor smirk** is the story. Horror thumbnails are everywhere on Roblox; *betrayal* + horror is the differentiator — show both.

## 3. Pre-launch settings (Creator Dashboard / Game Settings)

- [ ] **Communication → Enable voice chat** (proximity). This is the single most important setting for this game.
- [ ] **Permissions → Public** (when ready — leave Private until the checklist below passes)
- [ ] **Basic Info → Genre: Horror**, playable devices: Computer ✔ (Phone/Tablet optional — UI is scaled but untested on small screens)
- [ ] **Monetization → Passes → create 3 passes** named Ember Beam / Spectral Beam / Bloodhunter Beam (suggested price: 49-99 Robux each), then paste their numeric IDs into `GAME_PASSES` at the top of `GameManager.server.lua`
- [ ] **Age guidelines questionnaire** — answer honestly: mild fear themes, no blood/gore (the game only uses a 🩸 emoji in text), no realistic violence. Expect a "Moderate fear" content label; that keeps 9+ eligibility, which matters — a big slice of Roblox horror players are 9-12.

## 4. Sound assets (15 minutes, in Studio)

The code ships with a complete sound system wired to placeholder IDs (silent until swapped). In Studio: **View → Toolbox → Audio**, search each term, right-click → Copy Asset ID, paste into `SOUND_IDS` (top of `GameManager.server.lua`) and `STINGER_IDS` + heartbeat (top of `ClientUI.client.lua`):

| Key | Search the Toolbox for |
|---|---|
| ambientDay | "wind ambience loop" |
| ambientNight | "horror ambience drone" |
| generatorHum | "machine hum loop" |
| generatorFail | "power down electrical" |
| monsterGrowl | "monster breathing loop" |
| heartbeat (client) | "heartbeat loop" |
| killStinger (client) | "horror jumpscare stinger" |
| dawnChime (client) | "morning chime" |
| voteBell (client) | "dramatic bell" |
| repairTick | "wrench mechanical click" |

Only use audio marked as free-to-use from the Toolbox — Roblox blocks unlicensed audio automatically, so anything the Toolbox lets you insert is safe.

## 5. QA checklist (run once with 3 Studio test clients before going public)

- [ ] Match auto-starts 10s after 3rd player joins
- [ ] Each player sees their role toast (1 mole, rest crew)
- [ ] Generators decay at night, repair prompt works, health bars update
- [ ] The Watcher appears at night, chases the nearest player outside the lamp ring, kill works
- [ ] Killed player becomes ghost, revives at next dawn
- [ ] Mole: sabotage button fires (feed shows "power surge", no attribution), lure sends monster at chosen player
- [ ] Dawn vote appears for living players; majority exile works; exiling the mole ends the match with crew win
- [ ] Reveal screen shows correct mole name and survivors
- [ ] After reveal, next match can start (players return to lobby state)
- [ ] Nobody gets stuck: leave one client mid-night and confirm no errors in Output

## 6. Launch sequence

1. Complete sections 3-5 above.
2. Flip to **Public**.
3. Play 5+ public matches yourself the first evening — early sessions feed the discovery algorithm, and servers with an active dev get better session metrics.
4. Post 2-3 clips of the funniest mole reveals to TikTok/Shorts with the game link (this genre's proven acquisition channel — it's exactly how Meccha Chameleon and Steal a Brainrot grew).
5. Iterate weekly. The retention pattern for Roblox horror is content cadence: a new monster, a new map variant, a new mole ability every 1-2 weeks.

## 7. What's still manual vs. automated

| Step | Who |
|---|---|
| Code changes, balance tuning, new features | Claude (this repo → push to Roblox via Open Cloud once network access is live in a fresh session) |
| Publishing new versions via API | Claude (same as above) |
| Creating passes, settings, voice chat, going public | You (Creator Dashboard) |
| Sound ID swap-in (Toolbox is Studio-only) | You, once (15 min) |
| Playtesting with humans | You + friends |
