class_name Iap
extends RefCounted
## Real-money IAP, DEV STUB ONLY. Purchases grant goods directly; no billing.

var bundle_bought: bool = false
var bundle_first_seen: float = -1.0   # -1 = not yet offered

func packs() -> Array:
    var out: Array = []
    for row in ConfigDB.iap_packs:
        out.append({
            "purchase_id": String(row["purchaseId"]),
            "goods": row["goods"],
            "icon": String(row.get("icon", "")),
        })
    return out

func purchase_pack(purchase_id: String, game, now: float) -> Dictionary:
    for row in ConfigDB.iap_packs:
        if String(row["purchaseId"]) == purchase_id:
            Rewards.grant_all(row["goods"], game, now)
            return {"ok": true, "reason": ""}
    return {"ok": false, "reason": "unknown"}

func _bundle_row() -> Dictionary:
    return ConfigDB.bundles[0] if ConfigDB.bundles.size() > 0 else {}

func _required_level() -> int:
    var cond := String(_bundle_row().get("condition", ""))
    if cond.begins_with("Level-"):
        return int(cond.substr(6))
    return 1

func note_seen(now: float) -> void:
    if bundle_first_seen < 0.0:
        bundle_first_seen = now

func bundle_state(game, now: float) -> Dictionary:
    var row := _bundle_row()
    var base := {"goods": row.get("goods", []), "purchase_id": String(row.get("purchaseId", ""))}
    if bundle_bought:
        base["available"] = false; base["reason"] = "already_bought"; return base
    if game.player.level < _required_level():
        base["available"] = false; base["reason"] = "locked"; return base
    if bundle_first_seen >= 0.0 and now >= bundle_first_seen + float(row.get("lastDuration", 0)):
        base["available"] = false; base["reason"] = "expired"; return base
    base["available"] = true; base["reason"] = ""; return base

func purchase_bundle(game, now: float) -> Dictionary:
    var st := bundle_state(game, now)
    if not st["available"]:
        return {"ok": false, "reason": st["reason"]}
    Rewards.grant_all(_bundle_row()["goods"], game, now)
    bundle_bought = true
    return {"ok": true, "reason": ""}

func to_dict() -> Dictionary:
    return {"bundle_bought": bundle_bought, "bundle_first_seen": bundle_first_seen}

static func from_dict(d: Dictionary) -> Iap:
    var iap := Iap.new()
    iap.bundle_bought = bool(d.get("bundle_bought", false))
    iap.bundle_first_seen = float(d.get("bundle_first_seen", -1.0))
    return iap
