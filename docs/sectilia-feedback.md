# Sectilia feedback log

Running notes on friction hit while using the Sectilia CLI to produce the Curio
Hall map art (about 5,000 images). Each entry: what we hit, why it hurt, what
would help.

## Planning-time observations

1. **Throughput: one job at a time, 3-job queue cap.** A ~5,000-image set means
   many hours of serial foreground runs, each needing a watching shell. A
   bulk/manifest submission mode (submit a list, poll or collect later) would
   remove most of that.
2. **`generate` always removes the background.** Full-frame painted
   illustrations (the story panels) cannot use it, so they have to go through
   `background`, which is built for scenery rather than character scenes.
3. **`background` jobs cannot be the source of `edit`.** A "boarded-up" variant
   of a painted scene cannot be derived, so the Hall exterior had to be split
   into per-wing sprites (restored + boarded) instead of one painted facade.
4. **`generate` cannot take style reference jobs.** Only `edit` accepts `--style`,
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
