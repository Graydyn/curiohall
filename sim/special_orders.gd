class_name SpecialOrders
extends RefCounted
## The six sequential OrderSpecial requests: each activates when its campaign
## task completes, seeds the player with its generator chain's tier-1 item
## (our stand-in for the   cache-queue delivery), and pays gem/energy
## rewards when all its required items are delivered from the board.
## Time-free by design: no timers, no tick host.

signal special_changed

var next_id: int = 1
var active: bool = false

static func seed_items(row: Dictionary) -> Array:
    var chains_v: Variant = row.get("GeneratorChain")
    var chains: Array = chains_v if chains_v is Array else [chains_v]
    var out: Array = []
    for c in chains:
        var chain := String(c)
        out.append((chain + "_1") if chain.begins_with("sp") else (chain + "01"))
    return out

static func requirements(row: Dictionary) -> Array:
    var out: Array = []
    for i in range(1, 4):
        var key := "Requirement%d" % i
        var v: Variant = row.get(key)
        if v != null:
            out.append(String(v))
    return out

func _row(id: int) -> Dictionary:
    for row in ConfigDB.order_special:
        if int(row["Id"]) == id:
            return row
    return {}

func current() -> Dictionary:
    return _row(next_id) if active else {}

func is_all_done() -> bool:
    return not active and next_id > ConfigDB.order_special.size()

func maybe_activate(campaign: Campaign, game, now: float) -> bool:
    if active or next_id > ConfigDB.order_special.size():
        return false
    var row := _row(next_id)
    var trigger := String(row.get("Trigger", ""))
    if not trigger.begins_with("taskFinish-"):
        return false
    if not campaign.done.has(trigger.trim_prefix("taskFinish-")):
        return false
    active = true
    for seed_id in seed_items(row):
        Rewards.grant(String(seed_id), game, now)
    special_changed.emit()
    return true

func deliver(board: MergeBoard, game, now: float) -> Dictionary:
    if not active:
        return {"ok": false, "reason": "not_active"}
    var row := _row(next_id)
    var reqs: Array = requirements(row)
    # Check all requirements are satisfied before removing any
    for req in reqs:
        if board.count_of(req) < 1:
            return {"ok": false, "reason": "no_item"}
    # All satisfied, remove each one
    for req in reqs:
        board.remove_n_of(req, 1)
    var rewards_v: Variant = row.get("Rewards")
    var rewards: Array = rewards_v if rewards_v is Array else []
    Rewards.grant_all(rewards, game, now)
    active = false
    next_id += 1
    maybe_activate(game.campaign, game, now)
    special_changed.emit()
    return {"ok": true, "reason": ""}

func to_dict() -> Dictionary:
    return {"next_id": next_id, "active": active}

static func from_dict(d: Dictionary) -> SpecialOrders:
    var s := SpecialOrders.new()
    s.next_id = int(d.get("next_id", 1))
    s.active = bool(d.get("active", false))
    return s
