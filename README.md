# daily-game-trends

Automated pipeline for tracking daily game industry trends, scoring mechanics, spotting market gaps, and generating new game concepts.

## Workflow

**Phase 1 — Trend Collection** (`trends/`, `trends_summary.md`)
Pull current charts and signals from Steam, mobile top charts, and short-form video platforms (TikTok). Snapshot raw findings per day in `trends/`, condense into `trends_summary.md`.

**Phase 2 — Analysis** (`mechanics_confidence.md`, `market_gaps.md`, `competitors.md`)
Score which mechanics are durable vs. hype, identify underserved genres/audiences, and track who else is already mining this space.

**Phase 3 — Synthesis** (`game_concepts.md`, `leaderboard.md`)
Combine trend + gap analysis into concrete game concepts (4 per run: Safe / Aggressive / AI-Native / Solo-Developer), and rank the top 25 concepts ever generated on a cross-run leaderboard.

## Files

| File | Purpose |
|---|---|
| `trends/` | Dated raw trend snapshots |
| `trends_summary.md` | Condensed daily trend digest |
| `mechanics_confidence.md` | Mechanics scored by durability/confidence |
| `market_gaps.md` | Underserved genres, audiences, niches |
| `competitors.md` | Existing trend-intelligence players in this space |
| `game_concepts.md` | Generated concepts from trend + gap synthesis, with a pinned Current Top Concept |
| `leaderboard.md` | Top 25 highest-scoring concepts ever generated, ranked |

## Cadence

Designed to run daily, appending a new file to `trends/` and refreshing the summary/analysis/synthesis files each run.
