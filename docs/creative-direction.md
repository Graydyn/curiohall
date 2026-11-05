# Curio Hall — Creative Direction

**Status:** Approved 2026-08-28.
**Scope:** Name, theme, tone, and visual style for the new merge game. This doc anchors all art and the full
text 

---

## Name

**Curio Hall**

Store listing title: **"Curio Hall: Merge Game"** (the suffix is for discoverability
only; in-game branding is always just *Curio Hall*).

## Concept

You inherit **Curio Hall**, the once-grand museum of a Victorian expedition society,
now dusty and shuttered. By merging the specimens, instruments, and oddities that flow
in from the society's expeditions, you fulfill acquisition orders, restore the Hall
wing by wing, and win back its eccentric members.

## Tone

**Victorian gaslamp whimsy.** Warm, witty, mildly fantastical. Specimens may glow,
tick, or misbehave, but this is a museum of wonders, not a fantasy game. No fixed
real-world geography; the society explores a romanticized, invented map.

## Theme 
| mechanic | Curio Hall fiction |
|---|---|
| Generators (`ItemModelConfig` spread fields) | Crates, cabinets, and apparatus from the field: specimen crates, a brass alembic, a fossil block. Tapping (energy) produces chain items. |
| ~40 merge chains, 543 items | Collection categories: botanical presses, mineral clusters, clockwork instruments, preserved creatures, cartography tools, tea service (the society runs on tea). |
| 14 single-item collectible chains | Rare "centerpiece" curios. |
| Orders (`OrderRandom` / `OrderItem`) | Acquisition requests from curators, patrons, and visiting scholars for exhibits. |
| 40 map areas + `Skin` decoration | Wings and rooms of the Hall: Atrium, Fossil Gallery, Astronomy Dome, Conservatory, Archives, etc. |
| 11 characters + intimacy tracks | Society members: the formidable curator, a rival collector, a shy taxidermist, a globe-trotting aeronaut, and so on. |
| Live-ops event archetypes (dig, explore, farmboard, freefall...) | Expeditions the society mounts. Digs are excavations; explore-path boards are charted journeys. Framing: "The Society Presents: Expedition to X." |

## Visual style

**Ornate vector deco.**

- Clean, bold vector shapes so merge items read clearly at ~60px; ornamentation lives
  in the meta-layer (map, characters, UI frames), not on board pieces.
- Victorian filigree, brass fittings, engraved-poster flourishes at the meta-layer.
- Palette anchors: **deep teal, burgundy, cream, brass**, with warm gaslight glows.
- Typography: engraved-poster display type for headers; plainer humanist type for
  body text and UI.
- Style must scale cheaply across 100+ live-ops event reskins.

## The cast (11 character slots)

Mapped one-to-one onto `CharacterIntimacyListConfig` slots so unlock days, gift
preferences, and intimacy gating carry over unchanged. Gift categories will be
rethemed later (e.g. chocolate → confections, flower → botanicals, book → volumes,
watch → timepieces) but keep the same slot mechanics.

| Slot | Name | Unlock | Full Name | Role |
|---|---|---|---|---|
| 1 | Cornelia | day 1 | **Cornelia Wren** | The formidable interim curator; your day-one guide, all etiquette and steel. |
| 2 | Barnaby | day 1 | **Barnaby Pluck** | Cheerful young porter and jack-of-all-trades; the social hub the early cast unlocks through. |
| 3 | Aldous | day 12 | **Prof. Aldous Finch** | Absent-minded ornithologist; narrates the natural-history wings. |
| 4 | Sam | day 20 | **Sam Vane** | Suave rival collector; charming, untrustworthy, slowly won over. |
| 5 | Mark | day 30 | **Mark Bloom** | Shy conservatory gardener; tends the living collections. |
| 6 | Anjali | day 40 | **Anjali Bose** | Expedition chef and confectioner; runs the Tea Room, feeds the society. |
| 7 | Hugo | day 60 | **Hugo Pemberton** | Clockwork engineer; keeps the Hall's brass contraptions ticking. |
| 8 | Prudence | day 80 | **Prudence Quill** | Exacting archivist; guardian of the society's records and secrets. |
| 9 | Zephyrine | day 90 | **Zephyrine "Zeph" Blackwood** | Mysterious cartographer just back from the unmapped edges of the world. |
| 10 | Rosalind | day 100 | **Rosalind Thorne** | Celebrated botanical illustrator and society patroness. |
| 11 | Ambrose | special | **Ambrose Hall** | The vanished founder of Curio Hall; the long-arc mystery the campaign circles. |

## The Hall wings (47 map areas)

`MainTaskConfig` uses areas 1 to 47. Ordered as the restoration journey: public rooms,
then collections, then workshops and gardens, then the Hall's secrets.

1. The Front Gates
2. The Grand Atrium
3. The Cloakroom & Vestibule
4. The Curator's Office
5. The Tea Room
6. The Hall of Feathers
7. The Butterfly House
8. The Conservatory
9. The Fossil Gallery
10. The Mineral Vault
11. The Shell & Coral Room
12. The Aquarium Grotto
13. The Map Room
14. The Library of Expeditions
15. The Archives
16. The Clockwork Workshop
17. The Hall of Instruments
18. The Astronomy Dome
19. The Orrery Landing
20. The Gaslight Gallery
21. The Sculpture Court
22. The Hall of Giants
23. The Insectarium
24. The Herbarium
25. The Apothecary Annex
26. The Gemstone Salon
27. The Meteorite Chamber
28. The Cabinet of Whispers
29. The Portrait Stair
30. The Founders' Gallery
31. The Music Box Parlor
32. The Print & Poster Room
33. The Model Ship Hall
34. The Balloon Loft
35. The Observatory Walk
36. The Moonlit Courtyard
37. The Reflecting Pool
38. The Glasshouse Menagerie
39. The Night Garden
40. The Deep Vaults
41. The Forgotten Wing
42. The Founder's Study
43. The Hidden Passage
44. The Chart Room of Lost Lands
45. The Grand Ballroom
46. The Clock Tower
47. The Attic of Marvels

## Naming/writing notes for the text rewrite

- Events are themed as expeditions and society functions ("The Society Presents...").
- Character voice: eccentric, affectionate, dry Victorian wit.
- Item names favor curiosity-cabinet flavor (specimen, apparatus, curio, exhibit).
