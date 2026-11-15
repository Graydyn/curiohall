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
