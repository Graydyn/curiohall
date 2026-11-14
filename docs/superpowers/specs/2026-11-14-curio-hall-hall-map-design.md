# Curio Hall — The Hall Map (home screen, wings, elements, story)

**Status:** Draft for approval, 2026-11-14.
**Roadmap:** `docs/curio-hall-roadmap.md` — replaces the Phase 4a placeholder map (`MapPanel`,
`HallLayout`) and absorbs Phase 4c ("Wings decoration").
**Creative anchor:** `docs/creative-direction.md` (palette, tone, cast, the 47 wings).

---

## 1. Intent

The map is the heart of Curio Hall, and today it is a placeholder overlay hanging off the merge
board. This project makes it the game's **home screen**: the place the player lands, watches
their Hall come back to life, makes it their own, and where the story unfolds. Every other
screen (merge board, shop, Society, Chronicle, events) is reached from here and returns here.

It is also the project that sets the **look and feel** of the whole game. Its art defines the
meta-layer style that the other screens will be aligned to afterward, so it must be judged on a
real phone, in game, all together — not in mockups or as isolated pieces.

**Why we can go big:** the team are Sectilia beta testers with effectively unlimited generation
credits. Art volume is not a constraint; the design deliberately leans on large quantities of
art (many elements, three looks each). Any Sectilia friction found while building should be
written down as feedback for the Sectilia team (see §9).

## 2. Goals, non-goals, anti-goals

**Goals**
- Map is the home screen; all navigation hubs from it.
- Two levels: a painted **exterior** of the Hall and grounds, and a detailed **wing view** per wing.
- Keep the campaign linear; no per-wing counters.
- Restoration is visible and granular: ~1,100–1,400 **elements** across 47 wings, each built by a
  few campaign tasks and passing visibly through restoration stages.
- Every finished element offers **three looks**; the player picks one on completion and can
  re-pick any time for free.
- The story plays **on the map**, triggered by restoration.
- Playable end to end on the phone (720×1280 portrait, Android export per `readme.md`).

**Non-goals (this project)**
- Restyling the merge board, shop, Society, event screens (they get aligned to this look later).
- Premium/event/shop-sold looks (the data model leaves room; nothing sells looks yet).
- Sound and music.
- Changing campaign economics (task costs, rewards, day order stay as configured).

**Anti-goals — failure even if it technically works**
- A busy, noisy map. The brief is *calm, dreamy, Ghibli-like* Victorian gaslamp whimsy.
- Art that doesn't belong together: elements that don't sit in their wing's perspective/lighting,
  or wings that clash with the exterior.
- Story scenes that interrupt so often they feel like a chore.
- A home screen that hides where to go next (the player should always see the next thing to do).

## 3. Decisions already made (with the user)

| Topic | Decision |
|---|---|
| Home | Map is the home screen; store/events/etc. are reached **only** from it. |
| Structure | Exterior map → tap a wing → detailed wing view. (Not one giant cloud-fogged map.) |
| Locked wings | Shown **boarded up** or **missing, replaced by an outline**. |
| Campaign | Stays **strictly linear** (one active wing at a time). Opening several wings isn't worth the rework. |
| Exterior counters | **None.** With a linear campaign every wing behind the player is fully restored, so per-wing counts add nothing. |
| Non-cast askers | Tasks whose `detail_icon` isn't one of the 11 cast show as a generic **Society request** (no portrait). Not every task needs a character. |
| Elements | "Option A": a few tasks build one element. Go heavy on element count. |
| Customization | On completing an element the player **picks one of 3 looks**; swap later free in an edit mode. |
| Story | Portrait-and-speech-bubble scenes over the live map for most beats; **painted panels** for the big moments (~47–60). |
| Process | One big build delivered together, not a throwaway spike. |

## 4. Approaches considered (build order)

- **A. Throwaway vibe pass first** — rough exterior + one wing + one scene on the phone fast, then
  design and build properly. Fastest look-check; rejected by the user because judging the vibe
  needs everything together, not a fragment.
- **B. Full design → plan → build it properly (chosen)** — one large build that lands the home
  screen, both map levels, the element system, looks, edit mode, story scenes and the full art
  set together.

## 5. The experience

### 5.1 Home screen (exterior)

```
┌──────────────────────────────┐
│ ⚡ 87  ● 1,240  ◆ 35   Lv 14 │  top HUD (energy, coins, gems, level/XP)
│                              │
│   [painted Hall + grounds,   │  pannable (drag) + pinch-zoom within bounds
│    wings as distinct parts   │
│    of the building/grounds]  │
│       ┌─────────┐            │
│       │Fossil   │  (glowing) │  active wing: scaffolding + lamps, gentle highlight
│       └─────────┘            │
│  [Expedition!]   [Gala]      │  live events float as banners on the map
│                              │
│ ┌──────────────────────────┐ │
│ │ Next: Mount the T-rex 40●│ │  "next task" strip → jumps to it
│ └──────────────────────────┘ │
│ [Workroom] [Shop] [Society] [Chronicle] │  bottom nav
└──────────────────────────────┘
```

- One large painted illustration of the Hall estate: front gates, main building, domes, the
  glasshouse, clock tower, gardens, courtyard, pool. Each of the 47 wings is a recognizable part
  of it (a dome, a window row, a garden plot, an annex).
- **Wing states on the exterior:**
  - *Locked, existing structure* (a room inside the main building): **boarded up** — planks,
    dust sheets, dark windows.
  - *Locked, separate structure* (Glasshouse Menagerie, Balloon Loft, Clock Tower, Observatory
    Walk, etc.): **missing**, drawn as a faint ink outline on the grounds.
  - *Active* (the wing currently being restored): scaffolding / lamps being lit, gentle highlight.
  - *Restored*: fully painted, warm gaslight glow in the windows.
- No per-wing counters (decided). Only the **active** wing is highlighted; tapping it (or the
  next-task strip) goes straight to the work. Restored wings can still be tapped to visit and
  re-arrange.
- On open, the camera centers on the active wing.
- The **Workroom** is the merge board (renamed in the nav only; the board itself is unchanged).

### 5.2 Wing view

- Tapping a reached wing zooms into its detailed view: a painted interior (or garden) scene for
  that wing, with its elements placed in it. Large wings get a taller scene that scrolls
  vertically; the very large ones (Deep Vaults 341 tasks, Hidden Passage 323) may split into
  2–3 sub-rooms with tabs.
- Each element is in one of three stages:
  1. **Outline** — faint ink outline where it will be (not started).
  2. **In progress** — the finished art under scaffolding / dust sheets, plus a small progress
     pip ("2/3").
  3. **Done** — the player's chosen look, settled into the scene.
- Tapping an element with an available task opens the **task card** (who asks, cost vs. coins,
  Complete). The asker is the task's `detail_icon` character via `Cast` when it is one of the 11
  cast; every other `detail_icon` (imelda, dominic, riley, … ~1,800 tasks) shows a generic
  **"Society request"** with the Society seal and no portrait. Completing the element's last
  task triggers the **look picker**: the three looks side by side, the player taps one, it
  settles into place, then the element's story beat plays.
- **Arrange mode** (brass "Arrange" toggle in the wing view): tap any finished element to reopen
  its look picker and swap, free.
- Back returns to the exterior.

### 5.3 Story scenes

- **Beats (portrait scenes):** the camera eases to the element; character portraits slide in
  from the screen edges with speech bubbles over the live wing; tap to advance; skippable.
  Portraits: the 11 cast members only, each with ~4 expressions (neutral, happy, surprised,
  worried). Story beats are written for the cast; non-cast askers never speak in scenes.
- **Painted panels:** the screen dims to 1–3 painted illustrations with captions, Victorian
  picture-book style. Used for each wing reopening (47) plus the five Chronicle milestones and
  key cast arrivals (Aldous day 12, Sam day 20, … per creative-direction) — ~55–60 total.
- **Frequency (my call):** a beat plays when an element finishes **only if that element has one
  authored**; aim for roughly one beat per story day plus wing-reopening panels, so the player
  sees story often but not after every single element. All scenes are re-watchable from the
  Chronicle.
- **Script content:** the original game's main-story dialogue isn't in our config (it lived in
  scene timelines). Scripts are authored fresh in Curio Hall's voice (see §7.4).

## 6. How it fits the current code

Today: `scenes/main.tscn` is the merge board with HUD/order bar/inventory and Shop/Map/Society/
Expedition/Gala buttons; `MapPanel` (`view/map_panel.gd`) + `HallLayout` (`view/hall_layout.gd`)
draw 47 colored boxes with task pins; `Campaign` (`sim/campaign.gd`) is the linear day/task sim.

### 6.1 Screen structure

- New **`HomeScreen`** becomes the root view. It owns the top HUD, the exterior map, the next-task
  strip, the bottom nav and event banners.
- The merge board (BoardView + order bar + inventory) becomes the **Workroom screen**, entered
  from the nav, with a single "back to Hall" control. Its Shop/Map/Society/Expedition/Gala buttons
  are removed (reached from home instead).
- Shop, Society, Chronicle, Expedition (`EventPanel`), Gala (`GalaPanel`) open from home as today's
  overlays. The Chronicle button moves from `MapPanel` to the home nav.
- `MapPanel` and `HallLayout` are retired.
- Board rejections still toast; the toast moves to a shared layer so every screen can use it.

### 6.2 New sim: elements

- **Element data** (`config/curio_hall_elements.json`, authored by us): per element — `id`,
  `area`, display `name`, ordered `tasks` (task keys `day_id`), `pos` in its wing scene, optional
  `subroom`, three `looks` (art ids), optional `beat` (story script id).
- **Grouping rule:** within each story day (7–18 tasks, one area), consecutive tasks are grouped
  into elements of 2–4, aiming for 3; then hand-tuned. Invariant: **every one of the 4,107 tasks
  belongs to exactly one element**, and elements never span days. A generator script produces the
  first cut; the authored JSON is the source of truth.
- Element stage is **derived** from `Campaign.done` (no new progress state): 0 tasks done →
  outline, some → in progress, all → done.
- **New saved state (save v11):** `looks` (element id → chosen look index, 0–2) and `seen_scenes`
  (set of scene ids). The look picker is mandatory on completion (my call), so there is no
  "un-picked" state; if the app closes mid-pick, the element shows look 0 and the picker reopens
  next time the wing is visited.
- `Campaign` itself is unchanged (linear by decision).

### 6.3 Story

- **Scene data** (`config/curio_hall_story.json`): scene id → kind (`beat` | `panel`), trigger
  (`element:<id>` | `area_restored:<area>` | `task:<day_id>`), and lines (speaker, expression,
  text) or panels (image id, caption).
- A **scene queue** listens to `Campaign.task_completed` / `area_restored` and the element-finished
  event, enqueues unseen scenes, and plays them after the look picker closes. Seen scenes go to
  `seen_scenes`; the Chronicle lists them for replay. Existing `StoryRecapConfig` Chronicle volumes
  keep working alongside.

### 6.4 Linear campaign (decided)

`Campaign` stays strictly linear: only the current day's tasks are available and a day can't
advance until all its tasks are done, so every wing behind the player is fully restored. The
only reasons to revisit an old wing are to admire it and to re-arrange looks.

## 7. Art

All art via the **Sectilia** skill. Stored under `assets/map/` (`exterior/`, `wings/<area>/`,
`elements/<area>/`, `portraits/`, `panels/`, `ui/`).

### 7.1 Style
- Painted, soft-edged, Ghibli-like calm; Victorian gaslamp; palette **deep teal, burgundy, cream,
  brass**, warm gaslight glows. Elements and scenes share a consistent 3/4 top-down perspective and
  warm key light, so elements sit naturally in their wing.
- UI chrome (badges, nav, task card, look picker, speech bubbles): brass fittings, filigree,
  engraved-poster display type for headers, plain humanist type for body (creative-direction).
- **Style checkpoint (my call):** before the mass generation, the builder produces a small set —
  the exterior, one wing with ~5 elements in three looks, two portraits, one panel — and shows the
  user once. Then everything else is generated in that style.

### 7.2 Volume (approximate)
| Asset | Count |
|---|---|
| Exterior base painting (grounds/sky) | 1 large |
| Exterior wing parts × states (boarded / outline / active / restored) | ~47 × 2–3 |
| Wing scene backgrounds (incl. sub-rooms) | ~55 |
| Element looks (3 per element) | ~3,300–4,200 |
| Portraits (11 cast × ~4 expressions) | ~44 |
| Painted panels | ~55–60 |
| UI chrome pieces | ~20 |

### 7.3 Cheap derivations
- **Outline** stage of elements and *missing* wings on the exterior: generated in-engine from the
  finished art (edge/ink shader), not separate art, so they always match.
- **In progress** stage: finished art + shared scaffolding/dust-sheet overlay sprites.
- Exterior wing states must line up pixel-for-pixel with the base painting: generate the restored
  wing part, derive *boarded up* by Sectilia edit of that same image.

### 7.4 Words
- ~1,100–1,400 element names and the story scripts are authored by the builder in the
  creative-direction voice (eccentric, affectionate, dry Victorian wit), as first-pass text the
  user iterates on. Names for looks are short ("Bronze skeleton", "Painted diorama").

## 8. Testing and verification
- Unit (GUT, `test.sh`): element data integrity (every task in exactly one element, no cross-day
  elements, 3 looks each, all referenced art exists); stage derivation from `Campaign.done`;
  Society-request fallback for non-cast askers; look pick/swap; save v11 round-trip + older-save reset per convention; scene queue
  triggers and seen-tracking.
- Smoke: boot lands on the home screen; nav to each screen and back.
- **The real test:** export the Android build and run it on the user's phone.

## 9. Sectilia feedback log
Keep `docs/sectilia-feedback.md` while building: anything that slowed generation down, gave
inconsistent results (perspective, palette drift, alignment between edited states), or that a
feature would have made easier. Report it to the user at the end.

## 10. Open for the user
Nothing open. Campaign stays linear, no exterior counters, non-cast askers are generic Society
requests (resolved 2026-11-14).

## 11. Left to the builder
Exact exterior composition and which wing sits where; pan/zoom feel; transition animations;
element positions within wings; sub-room splits for the largest wings; which elements carry
beats; plan task breakdown and order; asset file formats and import settings.
