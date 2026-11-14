# Curio Hall Hall Map Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Hall map the game's home screen — a painted exterior of the Hall, a detailed view per wing with ~1,400 restorable elements in three player-chosen looks, and story scenes that play on the map — with the full Sectilia art set, playable on the phone.

**Architecture:** Two new pure-sim classes sit beside `Campaign` (which stays unchanged and linear): `HallState` (chosen looks + pending look picks) and `Story` (scene queue + seen set); element stage is derived from `Campaign.done` via static `HallElements` helpers. Element, wing and scene content live in three new authored JSON configs loaded by `ConfigDB`. The view is restructured around a new `HomeScreen` root; the merge board becomes the `Workroom` screen; every view renders placeholder shapes when art is missing so code lands before art, then Sectilia art is generated in style-locked batches.

**Tech Stack:** Godot 4 / GDScript, GUT tests (`./test.sh`), Python 3 + Pillow for authoring/art tooling, the `sectilia` CLI (load the `sectilia` skill before any art task).

**Spec:** `docs/superpowers/specs/2026-11-14-curio-hall-hall-map-design.md`

## Global Constraints

- Viewport 720×1280 portrait (`project.godot`); must run from the Android export: `godot --headless --export-debug "Android" build/curiohall.apk` then `adb install -r build/curiohall.apk`.
- `Campaign` (`sim/campaign.gd`) logic is not changed: strictly linear, one active wing, day order as configured.
- No per-wing counters on the exterior. Only the active wing is highlighted.
- Askers: a task's `detail_icon` shows via `Cast` only if it is one of the 11 cast keys in `Cast.NAMES`; every other value shows **"Society request"** with the Society seal and no portrait. Only the 11 cast speak in story scenes.
- Look picker is mandatory on element completion; re-picking in Arrange mode is free.
- Save version 11; older saves back up to `save.corrupt.json` and reset (existing convention in `SaveManager`).
- Palette: deep teal, burgundy, cream, brass, warm gaslight glows; calm, dreamy, Ghibli-like Victorian gaslamp whimsy. Display type engraved-poster (IM Fell English SC), body humanist (Alegreya Sans); both OFL from github.com/google/fonts.
- Sectilia rules (from its skill): one job at a time, foreground only, never parallel or background, small batches with a look between them, always `--out`, keep job ids.
- Text voice: eccentric, affectionate, dry Victorian wit (`docs/creative-direction.md`).
- Log every Sectilia friction point in `docs/sectilia-feedback.md` as it happens.

## Review Focus

1. **Old save on upgrade** — a v10 save must back up and reset, booting cleanly to the home screen (Task 2 test).
2. **App closed between finishing an element and picking its look** — the picker must come back on the next visit to that wing; the element shows look 0 meanwhile (Task 2 + Task 6 tests).
3. **One task completion firing several triggers at once** (last task of a day finishes an element, advances the day, opens a new wing) — picker first, then every scene once, in trigger order, none dropped or duplicated (Task 3 test).
4. **Missing art** for any element, wing, portrait or panel — placeholder rendering, never a crash or blank screen (Task 5/6/7 tests).
5. **Android back button** in a wing, the Workroom or an overlay — returns one level toward home; on home it does nothing destructive (Task 4 test).

Also: campaign finished (no tasks left) — home shows no active wing and hides the next-task strip (Task 5 test).

---

## File Structure

| File | Responsibility |
|---|---|
| `config/curio_hall_wings.json` | Per area 1..47: name, structure (`interior`/`separate`), exterior rect, subrooms (name, scene size). |
| `config/curio_hall_elements.json` | Per element: id, area, subroom, name, tasks, pos, subject, looks, beat. |
| `config/curio_hall_story.json` | Per scene: id, kind, trigger, lines or panels. |
| `tools/build_elements.py` | First-cut grouping of tasks into elements + wings skeleton; merges with existing authored fields. |
| `tools/art_manifest.py` | Emits Sectilia job manifests from the configs. |
| `tools/sectilia_batch.py` | Runs a manifest serially, skips done outputs, records job ids. |
| `tools/contact_sheet.py` | Tiles a folder of PNGs into one image for visual review. |
| `tools/check_art.py` | Lists every asset the configs reference that's missing on disk. |
| `sim/hall_elements.gd` | `HallElements`: static stage/progress/next-task queries over config + `Campaign`. |
| `sim/hall_state.gd` | `HallState`: looks, pending picks, signals, save dict. |
| `sim/story.gd` | `Story`: trigger → scene queue, seen set, save dict. |
| `sim/config_db.gd` | + load/validate the three new configs. |
| `sim/game.gd`, `sim/save_manager.gd` | + `hall`, `story`, `pick_look`, trigger emission, save v11. |
| `view/hall_art.gd` | `HallArt`: path conventions + cached texture lookup (null when missing). |
| `view/curio_theme.gd` | Builds the shared `Theme` (fonts, brass panels/buttons). |
| `view/home_screen.gd` | Home root: top HUD, exterior, next-task strip, bottom nav, event banners, screen stack, back handling, toast. |
| `view/exterior_map.gd` | Pan/zoom painted exterior with per-wing state sprites. |
| `view/wing_view.gd` | Wing scene, subroom tabs, element sprites, Arrange toggle. |
| `view/element_sprite.gd` | One element in its stage (outline shader / scaffolding / chosen look). |
| `view/shaders/ink_outline.gdshader` | Ink-outline rendering of a texture's alpha edge. |
| `view/task_card.gd`, `view/look_picker.gd` | Task purchase card; three-look picker. |
| `view/story_player.gd` | Plays beat and panel scenes from `Story`. |
| `view/workroom.gd` | Merge-board screen (BoardView + OrderBar + InventoryPanel + back). |
| `view/cast.gd` | + `is_cast`, `asker_name`. |
| `view/chronicle_panel.gd` | + "Scenes" replay section. |
| `scenes/main.tscn`, `scenes/main.gd` | Rebuilt around `HomeScreen`. |
| Removed | `view/map_panel.gd`, `view/hall_layout.gd`, `test/unit/test_hall_layout.gd` (+ `.uid`s). |
| `assets/map/…`, `assets/fonts/…` | Art and fonts (paths in Task 5's `HallArt`). |

---

### Task 1: Hall content configs, grouping script, ConfigDB loading

**Files:**
- Create: `tools/build_elements.py`, `config/curio_hall_wings.json`, `config/curio_hall_elements.json`, `config/curio_hall_story.json` (start as `[]`)
- Modify: `sim/config_db.gd`
- Test: `test/unit/test_hall_config.gd`

**Interfaces:**
- Produces (ConfigDB fields): `hall_wings: Dictionary` (area:int → row), `hall_elements: Dictionary` (id:String → row), `area_elements: Dictionary` (area:int → Array of rows, in task order), `element_by_task: Dictionary` ("day_id" → element id), `story_scenes: Dictionary` (id → row), `scenes_by_trigger: Dictionary` (trigger:String → Array of scene ids, config order).
- Row schemas (JSON):
  - wing: `{"area": 9, "name": "The Fossil Gallery", "structure": "interior"|"separate", "exterior_rect": [x, y, w, h], "subrooms": [{"name": "…", "size": [720, H]}]}` — exterior canvas is 2160×3240.
  - element: `{"id": "09_004", "area": 9, "subroom": 0, "name": "…", "tasks": ["31_1","31_2","31_3"], "pos": [x, y], "subject": "…", "looks": [{"name": "…", "instruction": null}, {"name": "…", "instruction": "…"}, {"name": "…", "instruction": "…"}], "beat": "beat_031"|null}` — `pos` is the element's bottom-center in its subroom scene's pixels.
  - scene: `{"id": "beat_031", "kind": "beat"|"panel", "trigger": "element:09_004"|"area_opened:9"|"day:12"|"task:20_11", "lines": [{"speaker": "cornelia", "expr": "neutral"|"happy"|"surprised"|"worried", "text": "…"}]}` or `"panels": [{"caption": "…"}]` (panel art path is derived, Task 5).

- [ ] **Step 1: Write `tools/build_elements.py`.** Grouping rule per story day of n tasks (tasks in id order): `k = max(1, round(n/3))`, increase k while `ceil(n/k) > 4`; split into k consecutive groups, sizes as even as possible (larger groups first). Element ids `"%02d_%03d" % (area, index within area)`. Subrooms: chunk each area's elements, in order, into subrooms of ≤40. Placeholder `pos`: rows of 4 across 720px, 260px apart starting y=320; subroom `size` = `[720, max(1280, 320 + rows*260 + 200)]`. Placeholder `name` = `"Exhibit <id>"`, `subject` = `""`, looks named `"Look 1..3"`, `beat` null. Wings: names from `docs/creative-direction.md`'s list (copy from the current `HallLayout._ROWS`), `structure` `"separate"` for areas 7, 8, 18, 34, 35, 36, 37, 38, 39, 46 else `"interior"`, placeholder `exterior_rect` on a 4-column grid over 2160×3240. Re-running preserves every field already present in the existing JSON for matching ids/areas (only fills missing ones). Expected output: 1,408 elements, max 120 in one area, 58 subrooms total.
- [ ] **Step 2: Run it.** `python3 tools/build_elements.py` → prints `elements=1408 subrooms=58`.
- [ ] **Step 3: Write failing tests** in `test/unit/test_hall_config.gd`:

```gdscript
func test_every_task_in_exactly_one_element() -> void:
    assert_eq(ConfigDB.element_by_task.size(), ConfigDB.main_task_by_key.size())  # 4107
    var seen := {}
    for id in ConfigDB.hall_elements:
        for key in ConfigDB.hall_elements[id]["tasks"]:
            assert_false(seen.has(key), "task in two elements: " + key)
            seen[key] = true

func test_elements_never_span_days_and_have_three_looks() -> void:
    for id in ConfigDB.hall_elements:
        var row: Dictionary = ConfigDB.hall_elements[id]
        var days := {}
        for key in row["tasks"]:
            days[String(key).split("_")[0]] = true
        assert_eq(days.size(), 1, id)
        assert_between((row["tasks"] as Array).size(), 1, 4, id)
        assert_eq((row["looks"] as Array).size(), 3, id)
        assert_eq(row["looks"][0]["instruction"], null, id)

func test_all_47_wings_with_subrooms_covering_elements() -> void:
    for area in range(1, 48):
        assert_true(ConfigDB.hall_wings.has(area))
        for el in ConfigDB.area_elements[area]:
            assert_lt(int(el["subroom"]), (ConfigDB.hall_wings[area]["subrooms"] as Array).size())

func test_validate_rejects_bad_scene_refs() -> void:
    # scene with trigger element:99_999 and a non-cast speaker → validate() reports both
```

The last test loads a fixture dir (`test/fixtures/hall_bad/`, copy of the three configs with one bad scene: trigger `element:99_999`, speaker `imelda`) through `ConfigDB.validate_hall(wings, elements, scenes) -> Array[String]` and asserts two errors.
- [ ] **Step 4: Run** `./test.sh` → new tests FAIL (fields missing).
- [ ] **Step 5: Implement** loading in `ConfigDB.load_all` (clear the new dicts at the top as the others are) and `validate_hall(...) -> Array` called from `validate()`. Validation: every main task in exactly one element; element tasks exist and share a day; 3 looks; wing per area 1..47; subroom index valid; scene ids unique; trigger is one of the four forms and references an existing element/area/day/task; `lines[].speaker` ∈ `Cast.NAMES` keys and `expr` ∈ the four values; element `beat` references an existing scene of kind `beat`.
- [ ] **Step 6: Run** `./test.sh` → all PASS.
- [ ] **Step 7: Commit** `feat: hall wing/element/story configs and ConfigDB loading`.

### Task 2: Element stages, HallState, Game integration, save v11

**Files:**
- Create: `sim/hall_elements.gd`, `sim/hall_state.gd`
- Modify: `sim/game.gd`, `sim/save_manager.gd`, `test/unit/test_save.gd` (version 10 → 11)
- Test: `test/unit/test_hall_state.gd`

**Interfaces:**
- Consumes: Task 1 ConfigDB fields.
- Produces:
  - `HallElements` (static): `enum Stage { OUTLINE, IN_PROGRESS, DONE }`; `stage(id: String, c: Campaign) -> Stage`; `progress(id: String, c: Campaign) -> Vector2i` (done, total); `next_task(id: String, c: Campaign) -> String` (first undone key or ""); `is_workable(id: String, c: Campaign) -> bool` (next task is in `c.tasks_today()`); `of_task(key: String) -> String`; `in_area(area: int) -> Array`; `finished_count(area: int, c: Campaign) -> int`.
  - `HallState`: `signal element_finished(id: String)`, `signal look_changed(id: String, look: int)`; `var looks: Dictionary`, `var pending_pick: Array`; `finish(id: String) -> void` (appends to pending, emits); `look_of(id: String) -> int` (default 0); `set_look(id: String, look: int) -> void` (stores, removes from pending, emits); `pending_in_area(area: int) -> Array`; `to_dict()`, `static from_dict(d) -> HallState`.
  - `Game`: `var hall: HallState`; `pick_look(id: String, look: int) -> Dictionary` (`{ok, reason}`; reasons `unknown_element`, `not_done`, `bad_look`); `complete_task` additionally calls `hall.finish` when the task's element becomes DONE, and returns `"element": id` in its result dict when that happens. `SAVE_VERSION := 11`; save key `"hall"`.

- [ ] **Step 1: Failing tests** (`test_hall_state.gd`), using day 1 (tasks 1..7 → elements `01_000` (tasks 1_1..1_4) and `01_001` (1_5..1_7) under Task 1's rule):

```gdscript
func test_stage_follows_campaign_done() -> void:
    var g := Game.fresh(1000.0, 42); g.wallet.coins = 1000
    assert_eq(HallElements.stage("01_000", g.campaign), HallElements.Stage.OUTLINE)
    g.complete_task(1, 1000.0)
    assert_eq(HallElements.stage("01_000", g.campaign), HallElements.Stage.IN_PROGRESS)
    assert_eq(HallElements.progress("01_000", g.campaign), Vector2i(1, 4))
    assert_eq(HallElements.next_task("01_000", g.campaign), "1_2")

func test_finishing_element_queues_mandatory_pick() -> void:
    var g := Game.fresh(1000.0, 42); g.wallet.coins = 1000
    watch_signals(g.hall)
    for id in [1, 2, 3]: g.complete_task(id, 1000.0)
    var res: Dictionary = g.complete_task(4, 1000.0)
    assert_eq(res["element"], "01_000")
    assert_signal_emitted_with_parameters(g.hall, "element_finished", ["01_000"])
    assert_eq(g.hall.pending_pick, ["01_000"])
    assert_eq(g.hall.look_of("01_000"), 0)

func test_pick_look_rules() -> void:
    # not_done for 01_001, bad_look for 3 and -1, unknown_element for "zz";
    # ok for ("01_000", 2) clears pending; re-pick ("01_000", 1) ok (Arrange)

func test_pending_pick_survives_save_round_trip() -> void:
    # finish 01_000 without picking; Game.from_dict(g.to_dict()) → pending_pick == ["01_000"]

func test_v10_save_resets() -> void:
    # write a valid-shaped dict with save_version 10 to SaveManager.path → load_game() == null
    # and the corrupt backup exists
```

- [ ] **Step 2: Run** `./test.sh` → FAIL.
- [ ] **Step 3: Implement** `sim/hall_elements.gd`, `sim/hall_state.gd`; wire `Game.fresh`/`to_dict`/`from_dict`/`complete_task`/`pick_look`; add `"hall"` to `SaveManager`'s required keys; bump version and the v10→v11 comment.
- [ ] **Step 4: Run** `./test.sh` → PASS (including updated `test_save.gd`).
- [ ] **Step 5: Commit** `feat: element stages, HallState looks and save v11`.

### Task 3: Story queue

**Files:**
- Create: `sim/story.gd`
- Modify: `sim/game.gd`, `sim/save_manager.gd`
- Test: `test/unit/test_story.gd` (with fixture scenes injected via `ConfigDB.story_scenes` / `scenes_by_trigger` in `before_each`, restored in `after_each`)

**Interfaces:**
- Consumes: Task 1/2.
- Produces: `Story`: `signal scene_queued(id: String)`; `var seen: Dictionary`, `var queue: Array`; `enqueue(triggers: Array) -> void` (unseen, not-already-queued scene ids for each trigger, triggers in the given order, scenes in config order); `has_pending() -> bool`; `peek() -> Dictionary` (scene row or {}); `finish_current() -> void` (pops, marks seen); `replayable() -> Array` (seen scene rows, config order); `to_dict()`, `static from_dict(d) -> Story`.
- `Game`: `var story: Story`; `Game.fresh` enqueues `["area_opened:1"]`; `complete_task` on success enqueues, in this order: `"task:<key>"`, `"element:<id>"` (if finished), `"day:<new day>"` (if advanced), `"area_opened:<new area>"` (if the area changed). Save key `"story"`.

- [ ] **Step 1: Failing tests:** completing task 1_4 with fixture scenes on `task:1_4`, `element:01_000` → queue order `[task scene, element scene]`; completing day 1's last task with scenes on `element:01_001`, `day:2`, `area_opened:2` → queue order element, day, area; enqueueing the same trigger twice doesn't duplicate; `finish_current` marks seen and a later enqueue of that trigger adds nothing; queue + seen survive a save round-trip; fresh game has the `area_opened:1` scene queued when one exists.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: story scene queue driven by campaign triggers`.

### Task 4: Home screen structure, Workroom, navigation, back button

**Files:**
- Create: `view/home_screen.gd`, `view/workroom.gd`, `view/curio_theme.gd`, `assets/fonts/IMFellEnglishSC-Regular.ttf`, `assets/fonts/AlegreyaSans-Regular.ttf`, `assets/fonts/AlegreyaSans-Bold.ttf`, `assets/map/ui/` placeholders not required
- Modify: `scenes/main.tscn`, `scenes/main.gd`, `view/hud.gd` (horizontal top-bar layout: energy, coins, gems, level), `view/cast.gd`
- Delete: `view/map_panel.gd`, `view/hall_layout.gd`, `test/unit/test_hall_layout.gd` and their `.uid` files
- Test: `test/unit/test_smoke.gd` (update), `test/unit/test_home_nav.gd`

**Interfaces:**
- Produces:
  - `HomeScreen` (Control, full-rect): `setup(g: Game)`; `open_workroom()`, `open_wing(area: int)`, `go_back() -> bool` (false when already at home with nothing open); `show_toast(reason: String)`; `signal screen_changed(name: String)` with names `"home"`, `"workroom"`, `"wing"`. Bottom nav buttons named `NavWorkroom`, `NavShop`, `NavSociety`, `NavChronicle`; event banners `ExpeditionBanner`, `GalaBanner` (visibility/text rules copied from today's `_refresh_expedition_button`/`_refresh_gala_button`). Hosts the existing `ShopPanel`, `SocietyPanel`, `ChroniclePanel`, `EventPanel`, `GalaPanel` overlays.
  - `Workroom` (Control): `setup(g: Game, toast: Callable)`; contains `BoardView`, `OrderBar`, `InventoryPanel` at today's positions; `signal back_requested`. No other buttons.
  - `CurioTheme.build() -> Theme` (fonts above; PanelContainer/Button styleboxes in cream/brass/teal).
  - `Cast.is_cast(original: String) -> bool`, `Cast.asker_name(original: String) -> String` (cast display name, else `"Society request"`).
  - `main.gd` keeps `REJECT_MESSAGES` (moved into `HomeScreen`), the save-pending wiring (add `game.hall.look_changed`, `game.hall.element_finished`, `game.story.scene_queued`), the 1 s tick/flush timer, and save on close/pause. Android back: `get_tree().set_auto_accept_quit(false)`/`quit_on_go_back = false`, handle `NOTIFICATION_WM_GO_BACK_REQUEST` → `home.go_back()`.
- Exterior and wing areas are empty placeholders in this task (Tasks 5/6 fill them).

- [ ] **Step 1: Failing tests** (`test_home_nav.gd`, instantiating `main.tscn` like `test_smoke.gd`): boot shows home (`screen_changed` not needed; assert `home.current_screen() == "home"`), `NavWorkroom` press → `"workroom"` with BoardView input enabled; `go_back()` → `"home"`; second `go_back()` returns false and stays home; open Shop overlay then `go_back()` closes it; `Cast.asker_name("imelda") == "Society request"`, `Cast.asker_name("cornelia") == "Cornelia Wren"`. Update `test_smoke.gd`'s scripted board loop to reach the board through the Workroom and drop the `UI/ExpeditionButton` assertion in favour of `ExpeditionBanner` visibility.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Download the fonts** (raw files from github.com/google/fonts `ofl/imfellenglishsc/` and `ofl/alegreyasans/`), then implement.
- [ ] **Step 4: Run** `./test.sh` → PASS; `godot run .` boots to home and the Workroom works.
- [ ] **Step 5: Commit** `feat: Hall home screen hub, Workroom screen, back navigation`.

### Task 5: Art lookup + exterior map + next-task strip

**Files:**
- Create: `view/hall_art.gd`, `view/exterior_map.gd`, `view/shaders/ink_outline.gdshader`
- Modify: `view/home_screen.gd`
- Test: `test/unit/test_exterior.gd`

**Interfaces:**
- Produces:
  - `HallArt` (static, cached, returns null when missing): `exterior_base()`, `wing_exterior(area: int, state: String)` (state `"restored"`/`"boarded"`), `wing_scene(area: int, subroom: int)`, `element(id: String, look: int)`, `portrait(speaker: String, expr: String)`, `panel(scene_id: String, index: int)`, `ui(name: String)`. Paths: `res://assets/map/exterior/base.png`, `…/exterior/wing_%02d_<state>.png`, `…/wings/%02d/scene_<sub>.png`, `…/elements/%02d/<id>_<look>.png`, `…/portraits/<speaker>_<expr>.png`, `…/panels/<scene_id>_<index>.png`, `…/ui/<name>.png`. `HallArt.clear_cache()` for tests.
  - `ExteriorMap` (Control): `setup(g: Game)`, `refresh()`, `center_on(area: int)`, `signal wing_tapped(area: int)`. Canvas 2160×3240; drag pans, pinch/ctrl-wheel zooms 0.5–1.5, clamped to the canvas. Per wing at `exterior_rect`: LOCKED+`interior` → boarded sprite; LOCKED+`separate` → restored sprite through `ink_outline` (faint, no fill); ACTIVE → restored sprite + soft pulsing gaslight glow + scaffolding overlay `ui("scaffold")`; RESTORED → restored sprite with warm window glow. Missing art → a rounded rect in the state's palette colour with the wing name. Only reached wings (ACTIVE/RESTORED) emit `wing_tapped`.
  - Next-task strip in `HomeScreen`: the first workable element of the active area (`HallElements.is_workable`), text `"Next: <element name>  <cost>●"`; tap → `open_wing(area)` focused on that element. Hidden when `campaign.is_complete()`.
  - `ink_outline.gdshader`: canvas_item shader drawing the texture's alpha edge as a soft ink line (`uniform vec4 ink_color`, `uniform float width`), interior transparent.

- [ ] **Step 1: Failing tests:** with no art on disk (point `HallArt` at an empty base dir via `HallArt.base_dir`), `ExteriorMap` builds 47 wing nodes without errors; wing states match `campaign.area_state`; tapping a LOCKED wing emits nothing, the ACTIVE wing emits `wing_tapped(1)`; next-task strip text on a fresh game names element `01_000` and cost 26; with `campaign.day = 283` (past the last day) the strip is hidden and no wing is ACTIVE.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: painted exterior map with wing states and next-task strip`.

### Task 6: Wing view, element sprites, task card, look picker, Arrange

**Files:**
- Create: `view/wing_view.gd`, `view/element_sprite.gd`, `view/task_card.gd`, `view/look_picker.gd`
- Modify: `view/home_screen.gd`
- Test: `test/unit/test_wing_view.gd`

**Interfaces:**
- Consumes: `HallElements`, `HallState`, `Game.complete_task`/`pick_look`, `HallArt`, `Cast.asker_name`.
- Produces:
  - `WingView` (Control): `setup(g: Game, area: int, focus_element: String = "")`; subroom tabs (hidden if one subroom); vertical scroll over the subroom scene size; `signal back_requested`; `signal picks_done` (emitted after the picker closes with nothing pending). On open, if `hall.pending_in_area(area)` is non-empty the picker opens for the first pending element. Arrange toggle button `ArrangeToggle`.
  - `ElementSprite` (Control): `setup(row: Dictionary, g: Game)`, `refresh()`; OUTLINE → look-0 texture through `ink_outline`; IN_PROGRESS → look-0 texture dimmed + `ui("scaffold")` overlay + pip `"2/3"`; DONE → `element(id, hall.look_of(id))`. Missing texture → placeholder silhouette (rounded rect 160×160 in state colour, name label). `signal tapped(id: String)`.
  - Tap behaviour: Arrange on + DONE → picker; else workable → `TaskCard`; else nothing (locked toast `not_today` only if the element is in a future day).
  - `TaskCard`: element name, `Cast.asker_name(detail_icon)` with the cast portrait (`portrait(speaker,"neutral")`) or Society seal `ui("society_seal")`, cost vs coins, Complete (disabled when short), Back. Failures → toast.
  - `LookPicker`: three looks side by side with names; tap → `game.pick_look`; mandatory (no close button) unless opened from Arrange.

- [ ] **Step 1: Failing tests:** fresh game, open wing 1 → 2 element sprites in OUTLINE; complete tasks 1–3 via the card's Complete → `01_000` IN_PROGRESS pip `"3/4"`; complete task 4 → picker opens; pick look 2 → sprite DONE uses look 2, `picks_done` emitted; finish an element, rebuild the `WingView` from a save round-trip without picking → picker opens on setup; Arrange on, tap DONE element → picker opens and has a close button; task card for a task whose `detail_icon` isn't cast shows `"Society request"`; everything works with no art present.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: wing view with element stages, task card, look picker, arrange mode`.

### Task 7: Story player + Chronicle replay

**Files:**
- Create: `view/story_player.gd`
- Modify: `view/home_screen.gd`, `view/chronicle_panel.gd`
- Test: `test/unit/test_story_player.gd`

**Interfaces:**
- Consumes: `Story`, `HallArt.portrait/panel`, `WingView.picks_done`.
- Produces: `StoryPlayer` (CanvasLayer, layer above overlays): `setup(g: Game)`, `play_pending() -> void` (plays `story.peek()` scenes until empty, calling `story.finish_current()` after each), `play(scene: Dictionary)` (replay without touching the queue), `signal finished`. Beat: dim 25%, portraits slide in from left/right (speaker alternates side by first appearance), speech bubble with name + text, tap advances, Skip button skips the whole scene. Missing portrait → name plate only. Panel: dim to 85%, panel image (missing → cream card) with caption, tap advances through `panels`. For `element:` beats, `HomeScreen` scrolls the open `WingView` to that element first.
- When to play: `HomeScreen` calls `play_pending()` after `WingView.picks_done`, after returning to home, and on boot (the `area_opened:1` intro). Never while a look pick is pending.
- `ChroniclePanel`: a "Scenes" section listing `story.replayable()` titled by wing/element name; tap → `StoryPlayer.play(scene)`.

- [ ] **Step 1: Failing tests** with fixture scenes: queue of [beat, panel] plays in order, each marked seen once; Skip on a beat marks it seen and moves to the panel; pending pick in the open wing blocks `play_pending()` until `picks_done`; replay from Chronicle doesn't change `seen`/`queue`; missing art plays without errors.
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `feat: on-map story player and chronicle scene replay`.

### Task 8: Art tooling + Sectilia feedback log

**Files:**
- Create: `tools/art_manifest.py`, `tools/sectilia_batch.py`, `tools/contact_sheet.py`, `tools/check_art.py`, `docs/sectilia-feedback.md`, `assets/map/jobs.json` (`{}`)

**Interfaces:**
- `art_manifest.py <kind> [--areas 1-12] [--style-jobs-from KEY...] > manifest.json` where kind ∈ `exterior-wings`, `wing-scenes`, `elements`, `portraits`, `panels`. Each manifest entry: `{"key": "<unique>", "out": "assets/map/…png", "cmd": "generate"|"edit"|"background", "args": {...}, "source_key": "<key of the job to edit>"|null}`. Specs (painted, `alpha_threshold` 8, `background` null, `margin` 4 unless stated):
  - elements: look 0 `generate`, canvas `[384, 384]`, anchor `bottom_center`, subject = element `subject` + `", painted Victorian museum exhibit, soft Ghibli-like light, deep teal burgundy cream brass palette, 3/4 top-down view"`, `--style` the wing's locked style jobs; looks 1–2 `edit` of look 0 with the look's `instruction`.
  - exterior wings: restored `generate` canvas fitting `exterior_rect` (max side 1024), anchor `bottom_center`; boarded `edit` of restored: `"board up the windows and doors with weathered planks, dust sheets, dark unlit windows, keep everything else identical"`.
  - wing scenes: `background --style painted --size 720xH`, description from the wing name + `"interior seen from 3/4 top-down, open floor space for exhibits, soft gaslight, calm"`, `--style-job` locked style jobs.
  - portraits: neutral `generate` canvas `[512, 768]`, anchor `bottom_center`, `--facing front`; other three expressions `edit` of neutral.
  - panels: `background --style painted --size 720x960` from the panel caption + cast description, `--style-job` locked style + that cast's neutral portrait.
- `sectilia_batch.py manifest.json --limit N`: runs pending entries serially in the foreground (skip when `out` exists), resolves `source_key` → job id from `assets/map/jobs.json`, records each finished job id under its key, handles exit codes per the Sectilia skill (7 with `submitted:true` → `sectilia wait`; 4/5 → log and skip, never auto-resubmit more than once; 3/6 → stop and report). Prints `done=X skipped=Y failed=Z remaining=R`.
- `contact_sheet.py <dir> --out <png> [--cols 6]`: tiles PNGs with filenames for a quick visual check via the Read tool.
- `check_art.py`: lists every missing path implied by the configs (Task 5 path rules) and exits non-zero when anything is missing; `--summary` prints counts per kind.

- [ ] **Step 1: Implement the four tools** and a `--dry-run` for `sectilia_batch.py` that prints the commands.
- [ ] **Step 2: Verify:** `python3 tools/art_manifest.py elements --areas 1 | python3 tools/sectilia_batch.py /dev/stdin --dry-run` prints 6 commands (2 elements × 3 looks) with the edit lines referencing look-0 keys; `python3 tools/check_art.py --summary` reports the full missing counts (elements 4,224, wing scenes 58, exterior wings 84 (37 interior × 2 + 10 separate × 1), portraits 44, panels per story config).
- [ ] **Step 3: Commit** `chore: sectilia art manifest, batch runner and checks`.

### Task 9: Style lock — first art in game, user checkpoint

Load the `sectilia` skill first. Run `sectilia whoami` (exit 3 → ask the user to `sectilia login`).

**Files:** `assets/map/…` (subset below), `config/curio_hall_elements.json` + `config/curio_hall_wings.json` (area 2 authored), `assets/map/jobs.json`, `docs/sectilia-feedback.md`

- [ ] **Step 1: Style references.** Generate 3–4 small style probes (a brass-and-teal museum display case, a Victorian gaslamp, a corner of a painted conservatory) as painted `generate` jobs; pick the best two by eye; record their keys as `style_core` in `jobs.json`. These are the `--style` / `--style-job` refs for everything after.
- [ ] **Step 2: Exterior.** `background --style painted --size 2160x3240` of the Hall estate grounds (gates at the bottom, paths, gardens, pool, courtyard, sky, soft evening gaslight; building footprints left as open lawn/plazas where wing sprites will sit). Then the restored + boarded sprites for areas 1–4 and outline-only check for area 34 (separate). Set those wings' `exterior_rect`s to sit on the painting (view the base image to place them).
- [ ] **Step 3: Grand Atrium (area 2).** Author its 16 elements fully (name, subject, three looks with names/instructions, pos placed by viewing the generated scene) and generate the scene + all 48 element images via the batch runner, 3 at a time with a contact-sheet look between batches.
- [ ] **Step 4: Characters + panel + UI.** Cornelia and Barnaby portraits (4 expressions each), one painted panel (`area_opened:2`), and UI pieces: `scaffold`, `society_seal`, `badge_glow`, brass nav buttons, task card frame, speech bubble, look-picker frame. Write the area-2 opening panel scene and two beats into `curio_hall_story.json`.
- [ ] **Step 5: Wire the UI art** into `CurioTheme`/views where `HallArt.ui(...)` exists; run `./test.sh` → PASS.
- [ ] **Step 6: Build and install** the APK (readme commands); play: home → Atrium → finish an element → pick → beat.
- [ ] **Step 7: Commit** `art: style lock — exterior, Grand Atrium, first portraits and UI`.
- [ ] **Step 8: CHECKPOINT — stop and ask the user** to look at it on their phone. Record their style notes in `docs/superpowers/specs/2026-11-14-curio-hall-hall-map-design.md` §7.1 and regenerate anything they reject before continuing.

### Task 10: Author all element content (wings 1, 3–47)

**Files:** `config/curio_hall_elements.json`, `config/curio_hall_wings.json`

Fill, for every element: a distinct `name` (curiosity-cabinet flavour, fitting its wing), a `subject` for Sectilia (one concrete exhibit/fixture, no text or lettering), three looks (look 0 the canonical version; looks 1–2 genuinely different treatments with an edit `instruction` each, e.g. "make it a bronze casting on a marble plinth"); wing `structure`, subroom names. Use the day's task order as a little restoration arc (fixtures and cleanup early, star exhibits late in each day). Positions are placed later against the generated scene (Task 12).

- [ ] **Step 1:** Areas 1, 3–16. **Step 2:** Areas 17–31. **Step 3:** Areas 32–47. After each step: `./test.sh` PASS (validation), commit `content: element names and looks, areas X–Y`.
- [ ] **Step 4: Verify** no placeholder names remain: `grep -c '"Exhibit ' config/curio_hall_elements.json` → 0; no empty `subject`.

### Task 11: Author story scenes

**Files:** `config/curio_hall_story.json`, `config/curio_hall_elements.json` (`beat` fields)

- One **beat** per story day (282, minus those already written in Task 9), attached to the day's final element (`trigger: "element:<id>"`, and the element's `beat` set), 3–8 lines, spoken only by cast unlocked by that day (unlock days from `docs/creative-direction.md`: Cornelia/Barnaby day 1, Aldous 12, Sam 20, Mark 30, Anjali 40, Hugo 60, Prudence 80, Zephyrine 90, Rosalind 100; Ambrose appears only as a mystery: notes, voices, portraits-on-the-wall references — no speaking lines). The beats carry a through-line: restoring the Hall, winning back the society, the vanished founder.
- **Panels:** one `area_opened:<area>` panel per wing 1–47 (1–3 captions each); one `day:<n>` arrival panel for each of Aldous, Sam, Mark, Anjali, Hugo, Prudence, Zephyrine, Rosalind; one `task:<key>` panel for each Chronicle milestone task (`20_11`, `37_10`, `43_11`, `47_11`, `52_11`).
- [ ] **Step 1:** Days 1–94. **Step 2:** Days 95–188. **Step 3:** Days 189–282 + all panels. After each: `./test.sh` PASS, commit `content: story scenes, days X–Y`.

### Task 12: Mass art generation

Load the `sectilia` skill. All jobs through `tools/sectilia_batch.py` with `--limit 3`, contact-sheet review every few batches; reject/regenerate anything off-style (wrong perspective, text in image, palette drift). Log Sectilia friction in `docs/sectilia-feedback.md` as you go.

- [ ] **Step 1: Exterior wings** for all 47 areas (restored + boarded for `interior`, restored for `separate`), placing each `exterior_rect` on the base painting. Commit.
- [ ] **Step 2: Portraits** for the remaining 9 cast × 4 expressions (Ambrose: neutral only, as a painted founder's portrait). Commit.
- [ ] **Step 3: Wing scenes** for all 58 subrooms; after each scene, view it and set the `pos` of that subroom's elements on its floor space (no overlaps, larger star exhibits centre-stage). Commit per ~10 scenes.
- [ ] **Step 4: Elements**, by wing ranges — areas 1–16, 17–31, 32–47 — each look-0 batch reviewed before its edit looks. Commit per wing.
- [ ] **Step 5: Panels** for every panel scene. Commit.
- [ ] **Step 6: Verify** `python3 tools/check_art.py` exits 0.

### Task 13: Whole-game pass on the phone, roadmap, feedback

**Files:** `docs/curio-hall-roadmap.md`, `docs/sectilia-feedback.md`

- [ ] **Step 1:** `./test.sh` → all PASS.
- [ ] **Step 2:** Build + install the APK; play from a fresh install through at least wing 3 and use a DEV/save edit to jump to a late wing (e.g. set `campaign.day` to 200 in a saved file) to check large-wing subrooms, scrolling and performance; fix what breaks (texture import: enable mipmaps + `etc2_astc` already on; keep element textures at 384px).
- [ ] **Step 3:** Roadmap: add a "Hall Map" phase entry (✅) linking spec and plan; mark Phase 4c as absorbed into it; note `MapPanel`/`HallLayout` retired.
- [ ] **Step 4:** Commit `docs: roadmap — Hall map home screen`.
- [ ] **Step 5:** Report to the user: the build is on the phone, plus the Sectilia feedback list from `docs/sectilia-feedback.md`.
