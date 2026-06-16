# Roadmap — Sengoku: Way of the Sword

> *"Plan for what is difficult while it is easy; do what is great while it is small." — Sun Tzu*

This is the living growth plan: everything on the table for making Sengoku deeper, smarter,
and more beautiful. It's roughly ordered by impact, not commitment — pick what's fun.

## Where we are now (v1.2)
**New in v1.2:** the map is now the **real geography of Japan** — actual coastline and province
borders (46 provinces with Sengoku-era names), **terrain relief** (mountains/hills), **bright
clan-coloured territories** over the land, and **zoom + pan** (scroll to zoom, right-drag to pan,
Fit to reset) so you can read the action up close.

## Where we were at (v1.1)
A complete, playable single-player game: secret koku auction (turn-order + ninja + levy bids),
five unit types, castles + castle-building, ronin, a shared ninja with assassinations, daimyō
generals that lead and level up, faithful ranged→melee d12 combat, three AI strengths, a title
screen, an in-game field guide, and an Art-of-War theme throughout. Ships as Windows + Web builds.

**New in v1.1:** a **battle-odds preview** (hover an enemy to see your Monte-Carlo win %),
**true daimyō elimination** (lose your last general and your clan falls, its lands to the conqueror),
**fog of war + a ninja spy action** (enemy army makeup is hidden until you scout it),
**AI personalities** (aggressive / defensive / economic / opportunist rivals), and **save / load**.

It is built as a **single-file immediate-mode prototype** (`src/main/main.gd`). That's the biggest
piece of intentional debt — see "Foundation" below.

---

## Phase 1 — Depth & faithfulness (toward the real board game)
- ✅ **Full map of Japan** *(done v1.2)*: the real coastline + 46 historical provinces (from
  prefecture geodata), real adjacency and regions. *(Next: finer kuni subdivisions, varied income.)*
- ✅ **True daimyō elimination** *(done v1.1)*: lose your *last* daimyō and you're knocked out (the
  iconic rule), with their territory/units transferring to the conqueror.
- ✅ **Fog of war + scouting** *(done v1.1)*: enemy army *composition* is hidden (totals stay visible);
  the ninja's **spy** action reveals it. *(Next: hide totals too, and spy/assassinate risk.)*
- **Richer ninja**: spy vs. assassinate choice, ninja survival/capture risk, repeat-use.
- **Ronin hire phase**: a dedicated hire step with a ronin pool, per the original game's flow.
- **Honor / loyalty / morale**: provinces revolt, ronin desert, morale swings after big losses.
- **Diplomacy**: tacit or formal non-aggression pacts and betrayals with AI clans.
- **Historical mode**: real Sengoku clans (Oda, Takeda, Uesugi, …), starting positions, and
  set-piece scenarios (e.g., the road to Sekigahara).

## Phase 2 — Smarter rivals (the "Worthy Rivals" pillar)
- **Look-ahead AI**: replace the greedy heuristic with light search / scoring so Hard truly plans.
- ✅ **AI personalities** *(done v1.1)*: aggressive, defensive, opportunist, economic — each bids and fights differently.
- **Adaptive difficulty & handicaps** for new players.
- **Readable intent**: telegraph AI threats so the player can outwit, not just out-roll.

## Phase 3 — Game feel & balance
- **Balance pass**: tune unit costs/hit-values, castle garrison strength, income curve, and the
  win threshold; reduce late-game grind. (Current autoplay: ~7–19 rounds.)
- ✅ **Battle preview / odds** *(done v1.1)* before committing an attack (win % + risk band).
- **Undo-before-commit** in planning; confirmations on irreversible moves.
- ✅ **Save / load** an in-progress campaign *(done v1.1)*; **hotseat** pass-and-play for 2–5 humans *(next up)*.
- **Online multiplayer** (the architecture is meant to support it — needs the deterministic core).

## Phase 4 — Presentation & polish
- **Audio** (needs real assets): taiko/shamisen ambient score, UI clicks, sword/gun battle SFX,
  the ninja's whisper, a victory sting. *(The one thing code alone can't deliver.)*
- **Animation**: marching armies between provinces, richer dice-roll theater, capture flourishes,
  banner-raise on conquest, defeat fade.
- **Art upgrade**: hand-designed clan mon, painted/parchment map texture, unit sprites instead of
  number chits, daimyō portraits, a proper victory screen.
- **Map texture & terrain**: mountains/plains/coast styling that also affects movement/defense.
- **UX**: hover tooltips everywhere, a settings menu, **accessibility** (text scaling, colorblind
  palettes, reduce-motion — already partially specified), gamepad support, key remapping.
- **Mobile / touch support**: the game is currently desktop-only (mouse-click input, fixed
  1280×720 layout). Phones generally won't load or play the web build. Real support means touch
  input, a responsive layout, and a mobile-tuned export — a meaningful effort, tracked here.
- **Localization**: the engine and fonts already support it; extract strings and add languages
  (Japanese first — the fonts include the glyphs).

## Phase 5 — Content & modes
- **Campaign / scenarios** with objectives and a light narrative frame.
- **Random map generator** and adjustable match settings (clans, map size, win target).
- **Achievements**, stats, and a post-game summary (best generals, biggest battles).
- **In-game tutorial** that teaches the 9-phase flow step by step.

---

## Foundation (technical debt to pay before scaling)
The prototype is intentionally quick-and-dirty. Before piling on features, rebuild it properly:
- **Node-based architecture**: split the single `main.gd` into scenes/systems (Map, Economy,
  Turn engine, Combat, AI, UI) — see the art bible's data-driven map approach.
- **Deterministic, command-driven game state**: the keystone for save/load *and* online play.
- **Data-driven everything**: provinces, clans, units, and balance in resource/JSON files.
- **Automated tests** (gdUnit4) for the formulas: combat, economy, turn order, AI scoring.
- **CI**: a GitHub Actions workflow to auto-build Windows/Web and attach to releases on tag.

---

## Distribution
- Keep the **Web build** (GitHub Pages) as the instant "try it" link.
- Add **Linux & macOS** builds to releases (cross-export from one machine).
- Consider an **itch.io** page (and later Steam) once feel/audio land.

---

*Contributions welcome — pick anything above, or open an issue with your own idea.*
*"Opportunities multiply as they are seized."*
