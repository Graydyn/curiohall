class_name Events
extends RefCounted
## Live-ops expedition lifecycle: auto-rotating schedule with dev overrides,
## a second merge board built from event config (one extra open supply row at
## the bottom stands in for the   cache queue), and tier progress.
## Expiry advances on Game.tick_events (main.gd's 1s timer hosts the tick).

signal event_changed

enum State { IDLE, ACTIVE }

const VARIANT := "dogpark"   # phase 5a ships a single archetype variant

var state: int = State.IDLE
var variant: String = ""
var ends_at: float = 0.0
var next_event_at: float = 0.0   # 0.0 = start as soon as the gate passes
var board: MergeBoard = null
var best_tier: int = 0
var completed: bool = false
var paid_tier: int = 0   # highest tier whose prize has been granted

func is_active() -> bool:
    return state == State.ACTIVE

func tick(now: float, player: PlayerState) -> void:
    if state == State.IDLE:
        if now >= next_event_at and player.level >= ConfigDB.event_unlock_level(VARIANT):
            start_event(now)
    elif now >= ends_at:
        end_event(now)

func start_event(now: float) -> bool:
    if state == State.ACTIVE:
        return false
    var layout: Array = ConfigDB.event_board_layout(VARIANT)
    if layout.is_empty():
        return false
    variant = VARIANT
    board = MergeBoard.new()
    board.width = (layout[0] as Array).size()
    board.height = layout.size() + 1   # +1: the open supply row at the bottom
    BoardLayout.apply(board, layout)
    ends_at = now + float(ConfigDB.tuning["event_duration_seconds"])
    best_tier = 0
    completed = false
    paid_tier = 0
    state = State.ACTIVE
    event_changed.emit()
    return true

func end_event(now: float) -> void:
    if state != State.ACTIVE:
        return
    state = State.IDLE
    board = null
    variant = ""
    next_event_at = now + float(ConfigDB.tuning["event_gap_seconds"])
    event_changed.emit()

static func feed_chain_prefix() -> String:
    return String(ConfigDB.tuning["event_feed_item"]).rsplit("_", true, 1)[0] + "_"

## Stand-in for the   order->item cache delivery: each finished main
## order drops one feed item onto the supply row (lost with a warning if full).
func on_order_delivered(game, now: float) -> void:
    if state != State.ACTIVE:
        return
    # Member edge: a tier-2 feed item is worth two tier-1s, i.e. one prize tier.
    var key := "event_member_feed_item" if game.membership.is_member(now) else "event_feed_item"
    var item := String(ConfigDB.tuning[key])
    var row := board.height - 1
    var placed := false
    for x in range(board.width):
        var pos := Vector2i(x, row)
        if board.item_at(pos) == null and board.state_at(pos) == MergeBoard.CellState.OPEN:
            board.place(pos, ItemInstance.make(item))
            placed = true
            break
    if not placed:
        push_warning("Events: supply row full, feed item lost")
    else:
        event_changed.emit()

static func _tier_of(id: String) -> int:
    return int(String(id).rsplit("_", true, 1)[1])

## Progress tracks the feed chain only. Reaching a tier pays every unpaid
## prize up to it (members start at tier 2, so their first merge pays 2 and 3);
## producing the chain top marks the expedition complete.
func record_merge(new_type: String, game, now: float) -> void:
    if not new_type.begins_with(feed_chain_prefix()):
        return
    var t := _tier_of(new_type)
    if t > best_tier:
        best_tier = t
        event_changed.emit()
    if t > paid_tier:
        var ladder: Array = ConfigDB.tuning["event_tier_rewards"]
        for tier in range(paid_tier + 1, t + 1):
            if tier - 1 < ladder.size():
                Rewards.grant_all(ladder[tier - 1], game, now)
        paid_tier = t
        event_changed.emit()
    if not completed and not ConfigDB.items.get(new_type, {}).has("MergedType"):
        completed = true
        event_changed.emit()

func to_dict() -> Dictionary:
    return {"state": state, "variant": variant, "ends_at": ends_at,
            "next_event_at": next_event_at, "best_tier": best_tier,
            "completed": completed, "paid_tier": paid_tier,
            "board": board.to_dict() if board != null else null}

static func from_dict(d: Dictionary) -> Events:
    var e := Events.new()
    e.state = int(d.get("state", State.IDLE))
    e.variant = String(d.get("variant", ""))
    e.ends_at = float(d.get("ends_at", 0.0))
    e.next_event_at = float(d.get("next_event_at", 0.0))
    e.best_tier = int(d.get("best_tier", 0))
    e.completed = bool(d.get("completed", false))
    e.paid_tier = int(d.get("paid_tier", 0))
    var board_v: Variant = d.get("board")
    if board_v is Dictionary:
        e.board = MergeBoard.from_dict(board_v)
    return e
