# Best Friends — Roblox Prototype

**Everyone cooperates to keep the machine alive… but every player is secretly assigned one friend to sabotage without getting caught.**

- 3–8 players. Each player has a **station** (a glowing console in a circle) that constantly loses health — stand near yours and spam **Repair** to keep it green.
- Everyone secretly receives a **target** (shown only on your screen). Sabotage zaps your target's station, disguised in the event feed as a random "power surge" — nobody knows it was you. 3 charges, 12s cooldown.
- Think you know who's after you? You get **one accusation**. Right = they're exposed and lose sabotage forever, you get a full repair. Wrong = paranoia damage to your own station.
- Round lasts 90 seconds. Group wins if the machine takes **3 or fewer breaks** total. You *also* have a personal win if your target's station broke at least once — so you can win, lose, or both.
- End-of-round **reveal board** shows who was secretly targeting whom. That's the screenshot moment.

## Setup (5 minutes, no building required)

Both scripts generate everything (arena, stations, UI, remotes) at runtime.

1. Open **Roblox Studio** → New → **Baseplate** template.
2. In the Explorer panel:
   - Right-click **ServerScriptService** → Insert Object → **Script**. Delete its contents, paste in `GameManager.server.lua`, rename it `GameManager`.
   - Expand **StarterPlayer** → right-click **StarterPlayerScripts** → Insert Object → **LocalScript**. Delete its contents, paste in `ClientUI.client.lua`, rename it `ClientUI`.
3. Test with multiple players: **Test tab → Clients and Servers → set Players to 3 (or more) → Start.** Studio opens one window per player.
4. The round auto-starts 10 seconds after 3+ players are in.

## Publish

File → Publish to Roblox. In Game Settings: enable **Public**, set genre/age guidelines, write a title like *"BEST FRIENDS 🔪 (everyone is the traitor)"* — thumbnail with the reveal board is your best marketing asset.

## Tuning knobs (top of GameManager)

| Constant | Default | Effect |
|---|---|---|
| `ROUND_SECONDS` | 90 | Round length |
| `DECAY_PER_SEC` / `REPAIR_BOOST` | 6 / 8 | How busy players are just surviving |
| `SABOTAGE_DAMAGE` / `SABOTAGE_CHARGES` | 35 / 3 | Saboteur power |
| `GROUP_WIN_MAX_BREAKS` | 3 | Group difficulty |
| `WRONG_ACCUSE_DAMAGE` | 25 | Cost of paranoia |

## Roadmap after the core loop feels fun

1. **Playtest question #1:** is the reveal moment funny? If yes, everything else is polish.
2. Multiple minigame "tasks" beyond repair-spam (wire-connecting, timing bars) so sabotage has more disguises.
3. Round-end screenshot button / stylized reveal card for social sharing.
4. Cosmetics (station skins, sabotage effects) as the monetization layer — game passes, no pay-to-win.
5. Chain-reveal drama: show the target cycle as an animated arrow circle at reveal.
