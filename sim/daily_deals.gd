class_name DailyDeals
extends RefCounted
## Gem-priced daily deals with limited stock and a 24h restock.

signal deals_changed

var stock: Dictionary = {}      # deal id (int) -> remaining count
var restock_at: float = 0.0

func _init() -> void:
    _reset_stock()
    restock_at = 0.0

func _reset_stock() -> void:
    for row in ConfigDB.daily_deals:
        stock[int(row["id"])] = int(row.get("leftCount", 0))

func _row_for(id: int) -> Dictionary:
    for row in ConfigDB.daily_deals:
        if int(row["id"]) == id:
            return row
    return {}

func deals() -> Array:
    var out: Array = []
    for row in ConfigDB.daily_deals:
        var id := int(row["id"])
        out.append({
            "id": id,
            "item": String(row["itemCode"]),
            "cost_gems": int(row.get("costCount", 0)),
            "stock": int(stock.get(id, 0)),
            "is_ad": int(row.get("ad", 0)) == 1,
        })
    return out

func buy(id: int, wallet: EnergyWallet, game, now: float) -> Dictionary:
    var row := _row_for(id)
    if row.is_empty() or int(stock.get(id, 0)) <= 0:
        return {"ok": false, "reason": "out_of_stock"}
    var cost := int(row.get("costCount", 0))
    if not wallet.spend_gems(cost):
        return {"ok": false, "reason": "not_enough_gems"}
    Rewards.grant(String(row["itemCode"]), game, now)
    stock[id] = int(stock[id]) - 1
    deals_changed.emit()
    return {"ok": true, "reason": ""}

func tick(now: float) -> void:
    if restock_at == 0.0:
        restock_at = now + float(ConfigDB.tuning["daily_deals_restock_seconds"])
        return
    if now >= restock_at:
        _reset_stock()
        restock_at = now + float(ConfigDB.tuning["daily_deals_restock_seconds"])
        deals_changed.emit()

func to_dict() -> Dictionary:
    return {"stock": stock.duplicate(), "restock_at": restock_at}

static func from_dict(d: Dictionary) -> DailyDeals:
    var dd := DailyDeals.new()
    var raw: Dictionary = d.get("stock", {})
    dd.stock = {}
    for k in raw:
        dd.stock[int(k)] = int(raw[k])
    dd.restock_at = float(d.get("restock_at", 0.0))
    return dd
