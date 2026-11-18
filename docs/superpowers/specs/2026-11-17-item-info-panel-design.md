# Item info panel — design

## Intent
Players can select a board item but have no way to learn what it is, where it
comes from, or what it's worth. A small **?** button opens an info panel for
the selected item, and the panel is also where non-special items get sold
(selling is not wired up anywhere today).

## What the panel shows
- **Family name and tier.** Items have no display names; derive the family from
  the art name in `ItemViewConfig` (`Flour05` -> "Flour", `RawFish01` -> "Raw Fish",
  trailing digits stripped, CamelCase split). Tier = position in the
  `MergedType` chain (root = tier 1). Fallback when there is no art name: the
  item id.
- **Generator.** The family name of the generator chain whose `Spread_Weight`
  drops this family (e.g. Flour -> "Grocery Bag"). Only real generators count
  (items with a generator, not chests). Families no generator makes show
  "Found in chests".
- **Consumables** (`CollectRewards`): "Tap twice to collect: 2 coins" etc., built
  from the reward tokens (gold/gem/energy/xp/item).
- **Generators:** what they produce (family names) and energy per tap.
- **Chests:** "Tap twice to open".
- **Sell button** for everything else (not consumable, not generator, not chest).

## Sell price (decided)
Price in coins = `2^(tier-1)`: one generator tap makes a tier-1 item, and each
tier doubles. Same for every family, including ones from free (0-energy)
generators and chest-only families. Drop odds are ignored. **Capped** at the item's
shop `Price` and its `OrderItemConfig` price (lowest wins), so selling never
beats buying or delivering (decided after review found shop arbitrage). Replaces the
config `SellingPrice`. Selling removes the item, adds the coins to the wallet,
closes the panel and clears selection.

## UI
- **?** button in the inventory panel header next to "Store selected"; disabled
  while nothing is selected (BoardView emits a selection-changed signal).
- Panel is a modal `CanvasLayer` overlay like `StoragePanel`: art, title
  ("Flour - Tier 5"), info lines, Sell button (with price), Close.

## Approaches considered
- Price including drop odds (rejected by user: less predictable).
- Hand-authored names table (rejected: hundreds of items; art names already
  carry the family).

## Calls I made (correct me)
- Chests aren't sellable.
- Coins are the sell currency, 1 coin per tap of energy.
- Logic (naming, tier, generator lookup, price, sell) lives in `sim/` and is
  unit tested; the panel is a thin view.
