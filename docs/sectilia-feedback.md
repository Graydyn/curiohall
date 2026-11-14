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
