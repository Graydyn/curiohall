# Sectilia feedback log

Running notes on friction hit while using the Sectilia CLI to produce the Curio
Hall map art (about 5,000 images). Each entry: what we hit, why it hurt, what
would help.

## Planning-time observations

1. **Throughput: one job at a time, 3-job queue cap.** A ~5,000-image set means
   many hours of serial foreground runs, each needing a watching shell. A
   bulk/manifest submission mode (submit a list, poll or collect later) would
   remove most of that.
2. **`generate` always removes the background.** *(Resolved in 0.5.4: spec
   `background: {"type": "keep"}` keeps the image whole and opaque; the Atrium
   room is now a `generate` with `keep`.)* Full-frame painted
   illustrations (the story panels) cannot use it, so they have to go through
   `background`, which is built for scenery rather than character scenes.
3. **`background` jobs cannot be the source of `edit`.** A "boarded-up" variant
   of a painted scene cannot be derived, so the Hall exterior had to be split
   into per-wing sprites (restored + boarded) instead of one painted facade.
4. **`generate` cannot take style reference jobs.** *(Resolved in 0.5.4:
   `generate --style JOB_ID`, up to 8; we dropped the edit style pass.)* Only `edit` accepts `--style`,
   so matching a whole set to a locked look needs an extra edit pass per image
   (generate raw, then edit with the style refs), doubling the job count. Letting
   `generate` take `--style` jobs would remove that pass.

## Task 9 (style lock) observations

5. **Cold start on first job: ~10 minutes queued.** The first `generate` of the
   session sat `queued` for 10m14s waiting for the generator to start (stderr
   said "usually about 7 minutes"). Later jobs ran in under a minute. A shell
   with a 3-minute auto-background makes this awkward: the batch runner gets
   pushed to the background while the user waits. A `sectilia warmup` (or a
   cheap way to ask "is the generator hot?") would let us plan around it.
6. **Stdout JSON is pretty-printed over many lines.** "Every command prints one
   JSON object on stdout" read like one line; our batch runner parsed only the
   last line, got `}` and silently recorded `None` as the job id for the first
   two style probes. Fixed on our side (parse the whole stdout), but a
   `--json-line` / compact mode, or saying "multi-line" in the docs, would help.
7. **Same `--theme`, four quite different renderings.** Four style probes with
   one shared theme string came back as: a semi-realistic rendered display case,
   an inked storybook gaslamp, a soft painted conservatory corner (the Ghibli-ish
   look we want) and a near-photoreal dark globe. `--theme` alone does not hold
   a look; that is why the style refs (and the style-pass decision) matter.
8. **Probe cropped despite margin.** The gaslamp probe (512x512, margin 4) came
   back with the post cut off at the bottom edge rather than scaled to fit.
9. **`background` ran past its documented 45-minute cap.** The exterior base
   (2160x3240) took ~15 min, fine. The Grand Atrium scene (720x1560, job
   53c5f576) was still `running` after 60+ minutes with no error and an empty
   `waiting_for`, so the client's own 3600 s timeout fired first. There is no
   progress signal beyond "running", so it is impossible to tell "nearly done"
   from "stuck". A step/piece counter in `sectilia job`, and the server
   enforcing the 45-minute stop it documents, would help.
10. **A stuck background blocks the whole machine.** `~/.config/sectilia/job.lock`
    keeps the stuck background's id, so every later `generate`/`edit` sits
    waiting for it locally and nothing else can be submitted. With no cancel
    command (`sectilia cancel <id>` does not exist) a hung job halts all art
    work. A cancel command, or the server-side 45-minute stop actually firing,
    would unblock this.
11. **Capacity wait looked like "running".** Job 53c5f576 finally failed with
    cause `hammer_capacity` ("no hammer edit server was free for 120
    minutes"). For those 2 hours `sectilia job` showed `running` with an empty
    `waiting_for`, though it was really waiting for server capacity. The
    documented 45-minute cap does not count capacity wait; the real limit was
    120 minutes. The cause only appeared at the end. Showing
    `waiting_for: ["capacity"]` (or similar) while it waits would have saved
    two hours of watching, and let us switch to a fallback early.
12. **`--timeout` not honoured while queued for a cold server.** The Atrium
    resubmit (`background ... --timeout 160`, job 6debc1ba) kept waiting past
    20 minutes in `queued` ("waiting for hammer generate, edit to start,
    usually about 7 minutes") instead of exiting 7 at 160 s. An agent shell
    that relies on `--timeout` to stay in the foreground cannot.
13. **Hours with no GPU capacity, and the client kept saying "about 7 minutes".**
    The Atrium resubmit (6debc1ba, `--max-hammer-calls 10`) sat queued and then
    failed at 01:50 UTC with `hammer_capacity`: "no GPU capacity was available
    for hammer generate for 120 minutes". Together with 53c5f576, the service
    took about 4 hours to produce nothing, and the whole time stderr said
    "usually about 7 minutes". A status page or a `sectilia status` command
    showing current capacity and queue depth would let a user choose to wait or
    come back later, instead of tying up the machine lock for hours.
14. **`generate` subject capped at 500 characters, found by a 422.** The cap is
    not in `generate --help` or SKILL.md; the room fallback was rejected
    (`string_too_long`). Documenting the limit (and for `edit --instruction`,
    `background --description`) would save a round trip.
15. **Third capacity stall in a row.** After both Atrium backgrounds failed on
    `hammer_capacity`, a plain `generate` (job 11a4b138, 473x1024) sat
    `queued` with `waiting_for: ["generate"]` from 02:37 to past 03:08 UTC. Its
    own default `--timeout 600` did not fire either (item 12), so our runner's
    local timeout killed the CLI. All art work is stopped while the generator
    has no capacity; a status endpoint (`sectilia status`: generator up?
    queue depth? ETA?) would let callers decide to wait or come back later.
16. **The theme word "gaslamp" became an object.** With `--theme "painted
    Victorian gaslamp, ..."` the generator added an oil lamp or lantern to the
    umbrella elephant, the visitors' ledger and the marble bust (3 of the first
    5 elements). Removing the word fixed it. A note in the theme docs that
    nouns in `--theme` can turn into props would help.
17. **Sampled chroma key at tolerance 30 fails often on painted sprites.**
    About half the first Atrium generates failed validation with
    `chroma_key_border: border is not one color` (worst pixel 31 to 208 away),
    even with "isolated on a plain flat pale grey backdrop" in the subject:
    painted backdrops carry a soft vignette. Tolerance 60 passed most; glass
    (dodo bell jar), a stone fossil and a tall trunk stack only passed with
    `background: null`. Each failure costs four attempts first. Suggest the
    validator measure border uniformity after a light blur, or the generator
    be told to paint a truly flat backdrop when a chroma key is requested.
18. **Chroma key keeps the painted cast shadow as a pale blob.** After the key,
    a grey-white shadow patch stays under most sprites and reads as a light
    stain on the wing floor. We strip it with our own flood fill
    (`tools/clean_sprite.py`). An option to drop or keep cast shadows would help.
19. **Edits that recolour to dark leave white specks.** The "teal ironwork"
    gaslamp edit came back with white patches between the dark iron scrolls:
    the edit's white backdrop showing through, as the docs warn. Hard to avoid
    for filigree subjects.
20. **The generator draws about 2:3; other canvases letterbox.** The first
    room fallback (473x1024 with a magenta key) came back as a 2:3 picture with
    black bars. We now generate rooms at 683x1024 with `keep` and cover-fit to
    720x1280 ourselves. Documenting the native aspect, or `keep` filling the
    canvas (outpainting) would help.
21. **Edited states drift in framing.** "Board up the windows" edits of the
    Cloakroom and Curator's Office came back smaller and re-framed versus the
    restored image, so swapping restored/boarded in place jumps (the Atrium
    and the gates kept their framing). Portrait expression edits all re-posed
    the character front-on and zoomed out relative to the neutral generate; we
    re-derived each neutral by editing the *happy* image ("calm, closed mouth,
    keep framing"), which held framing. A "keep framing" guarantee, or a
    mask/inpaint edit that only touches a region (face, windows), would make
    states line up pixel for pixel as our spec's §7.3 needs.
22. **`--timeout` still not honoured while queued (0.5.4).** Generates and
    edits passed `--timeout 540` still sat past 11 minutes when queued for a
    cold server, so our runner's own timeout killed the CLI. We now recover the
    job id from `sectilia jobs --limit 1` and resume with `wait`.
23. **Servers go cold within ~20 minutes of idle.** Generate and edit each
    re-entered a 7 to 12 minute "waiting for hammer ... to start" whenever we
    switched between them or paused to review a contact sheet: about a third
    of the session's wall time. The skill's "look between small batches"
    advice and the cold-start window pull against each other; a longer
    keep-warm, or one server serving both generate and edit, would help.
24. **"Seen straight on" still came back in perspective.** A flat brass button
    plate for nine-slicing came back as a tilted 3/4 object twice ("seen
    perfectly straight on with no perspective"). `--camera` offers only
    eye_level/isometric; a flat orthographic front camera for UI pieces would
    help. We reused a flat frame that did come out right.
25. **Pale subjects and the chroma key do not mix.** A sampled key on a pale
    backdrop eats pale subjects where they touch it (the porcelain elephant's
    trunk, the cane settee, a marble fountain basin), and any generic
    "strip pale leftovers" pass we write has the same problem. What worked:
    `background: null` plus "a thin dark outline around the pale parts" in the
    edit instruction. A key colour chosen to contrast with the subject (say,
    a dark or saturated backdrop when the subject is pale) would avoid it.
26. **Outdoor scenes drift photoreal despite painted refs.** The Front Gates
    forecourt (generate + keep, refs: two style probes, the Atrium room and the
    exterior) came back near-photographic twice: real pebble texture, camera
    depth of field. Spelling out "hand-painted Ghibli-style background art,
    visible brushwork, flat painted gravel" pulled it most of the way back. The
    interior Atrium never drifted. Style refs seem to weigh less than the
    subject's own realism cues for outdoor ground textures.
27. **We are building masked inpainting out of crop + upload + edit.** To make
    the exterior wings sit in the painting, each wing is composited onto the
    base, a crop around it is uploaded, `edit`ed ("blend into one painting,
    contact shadow, keep framing"), and pasted back under our own feathered
    mask. It works when the edit keeps framing (gates, cottages: kept), but
    the edit repaints the *whole* crop: skies turned to pink fog, fine grass
    to smooth haze, and on one try the Atrium was redrawn isometric with the
    pool gone. So we mask down to the building plus a ground-contact ellipse
    and throw the rest away. A native region/masked edit (pass a mask, or a
    rect, and only that area changes, with the rest guaranteed identical)
    would make this one step with no drift. Allowing a region edit of a large
    `background` job (it cannot be an edit source today) would let us fix the
    exterior painting in place instead of compositing sprites over it.
28. **`background` composed a whole estate in one go, and well.** One 2160x3600
    `background` (30 hammer calls, style_core + the old exterior as
    `--style-job`) gave a single huge museum building with a domed entrance,
    towers, a glass gallery, side wings round a courtyard, dormer rows and an
    ivy wing, plus all ten requested garden structures and the gates, at
    clean 3/4 top-down. Two rough edges: the ten small structures came out as
    clean-edged stickers with no contact shadow (each needed a "settle" edit),
    and the lawn carries strong diagonal light rays that every later edit had
    to reproduce. The job ran 34 minutes with no progress output beyond
    "running"; a hammer-call count or stage on stderr would help judge it.
29. **"Remove X, leave the empty plot" invents a new garden.** 4 of 10
    removal edits re-drew the crop top-down as a formal hedged plot with
    paths (re-framed), 3 removed only part of the structure (kept a paved
    ring, a raised lawn pad, the night-garden beds) and one kept a floating
    balloon. Rewording to "erase the structure completely, together with its
    base, platform, paving and flowers, so only plain grass remains ... do not
    add hedges, paths, flower beds or anything else" fixed 7 of 8; the
    balloon needed naming explicitly. Positive-only phrasing could not carry
    "nothing here".
30. **State edits repaint outside the subject on large crops.** Boarding up a
    930x890 facade tile kept the building pixel-aligned (good), but also
    swapped the lawn and far wings behind it for blue sky, removed a rose
    bush and a tree in front, and made one tile's light warmer. We now keep
    only changes that are darker or greyer than the source and never a newly
    painted sky. A native masked edit (item 27) would remove all of this.
31. **"Settle" (relight, contact shadow) edits change size and content.** Of
    ten settle edits: one relit the whole crop 58 levels darker, one shrank
    the glasshouse, one deleted the courtyard's brick paving. "Make only
    subtle changes, do not move, redraw or re-frame" was in the instruction
    each time. A strength or "max change" knob for edit would help.
32. **One job per machine is now the bottleneck for a real asset list.** The
    service allows 3 jobs queued per user, but the CLI's machine lock sends only
    one at a time. Our remaining art (~1,400 generates, ~2,800 look edits, ~58
    scenes, ~55 panels) at a measured median of 64 s per generate and 96 s per
    edit is roughly 4-5 days of continuous generation, before cold starts.
    Letting one machine keep its 3 allowed jobs in flight (or a raised per-user
    limit for beta testers) would cut that to under 2 days without breaking the
    small-batch rule.
33. **About one in five element generates fails the chroma-key border check
    even at tolerance 60.** Across areas 3-10, 19 of 89 look-0 sprites failed
    `chroma_key_border` on all 4 attempts (worst pixel 61-192 away from the
    median), typically tall or hanging objects (chandelier, desk, painting,
    safe, hamper). Each failure burns four generations and a cold-queue slot.
    Retrying with background `null` always worked, so the fallback is cheap but
    manual for us. A server-side fallback (retry with `null` and an alpha
    matte when the border check fails twice) or a looser per-job border check
    would remove about 20 failed jobs per 90.
34. **Edits keep eating pale parts, and "thin dark outline around every pale
    part" is the fix that works.** In 8 of 178 look edits (white salt lamp,
    cream painted-iron table, porcelain hornbill, opaline lamp shade, cream
    urn, ash bureau, ...) the keyed edit deleted the pale areas. Re-editing
    with background `null` plus that phrase kept all of them whole. See item 25;
    it would be better if the key colour were chosen against the subject.
35. **Portrait generates come back turned three-quarters and larger than their
    edits, whatever `--facing front` says.** Each of the 9 new cast sources was
    3/4 on, while expression edits of them were front-on and 20-30% smaller.
    We now treat the generate as a source and make the final neutral an edit of
    the happy image, which lines up with the other expressions.
36. **A common noun in a subject becomes the literal object.** "a fine spray
    rose" gave a brass pipe wearing a flower, "rose heads" put roses on the
    watering cans. Rewording to "perforated sprinkler nozzle" fixed both. Same
    family as item 16.
37. **Switching between generate and edit still costs a cold start of 7-12
    minutes, and `--timeout` is still not honoured while queued.** Running every
    generate of a wing before any edit (the batch runner now orders them so)
    cut this to about one cold start per phase. A warm pool shared by both
    command types would be the real fix.
38. **Room scenes ignore "empty floor" and "wide".** The first Fossil Gallery
    came back with a giant skeleton spine lying down the middle of the floor,
    and the Cloakroom and Mineral Vault came back as narrow corridors. Spelling
    out "spanning almost the full width of the frame, nothing at all on the
    floor" fixed all three on the second try.
39. **The chroma-key border check failed more often on this chunk: 55 times over
    about 200 look-0 generates (wings 11-17).** 35 elements failed at least once.
    A same-request retry passed for 15 of them, and 20 needed background `null`
    (`art_bg: soft`). Hanging subjects (chandeliers, a gear mobile, jellyfish
    shades) fail almost every time, because their chains run off the top
    edge. Each failure burns four attempts and a queue slot, so a server-side
    fallback (item 33) would save about a quarter of the generate time.
40. **"Imaginary continents" comes back as the real Earth.** The Great Relief
    Model, the Leather Map Table and the Volume IV panel all painted Africa and
    Europe. "One invented island ... not the real world" fixed the relief model
    and the panel. The map table still shows real-looking coastlines after a
    second try.
41. **More noun-to-literal leaks (item 36):**
    - "rope pulley" drew a hangman's noose on the dumbwaiter, in all three
      looks;
    - "goose, swan and peacock quill pens" grew swan heads out of the pot;
    - "laid out like a small railway" laid the spectroscope on rails;
    - "a pool of lamplight" put the folio's stand in a pool of water;
    - "letterpress machine" drew a typewriter;
    - "crossed direction arms, bare of letters" still painted N and E.

    Each needed a reworded subject and a regenerate.
42. **"Close view of" panel subjects come back as an isolated object on grey,
    even with background `keep`.** The Kraken's-eye jar and the aquarium box
    panel did this. Adding "a full-frame painting filling the whole frame" fixed
    the jar. The aquarium needed "the tank fills the whole frame edge to edge".
43. **Edits with background `null` make white subjects see-through.** A
    "white enamel pail" edit came back translucent twice, even with the
    "thin dark outline" phrase that works for other pale parts (item 34).
    Recolouring the look (deep teal enamel) was the only fix.
44. **`sectilia generate` exited 6 ("could not download the image: The read
    operation timed out") for a job that had succeeded.** `sectilia wait` on
    the same id a minute later saved it. Exit 6 reads as "service down, stop",
    so the CLI should retry the download itself, or report it as exit 7 with
    `submitted: true`.
45. **Expression edits reframe and drop props.** One portrait's four
    expressions came out at different crops: the ledger came and went, and one
    character's edits switched to full length. Width-led alignment
    (align_states) then shrank whole figures, so we kept the raw edits. An
    edit option to lock the framing would help.
46. **Three jobs per machine works with one runner and three threads.** Each
    command's own stderr names its job id ("job <id> queued"), which made
    recovery unambiguous. However, edits mostly sat in `waiting_for: edit` (no
    free server slot), so real throughput was about 1.3 edits a minute: the
    extra parallelism mostly went to waiting. Generates ran about 3x faster
    than serial.
