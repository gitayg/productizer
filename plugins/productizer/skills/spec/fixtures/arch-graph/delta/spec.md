# Fixture spec — the HEAD side of the delta fixture

Not a real spec. See `../README.md`.

## Requirements

- **R1** — The fixture shall hold one requirement that does not move between base and head.
- **R2** — The fixture shall hold one requirement whose sentence was rewritten at head.
- **R3** — The fixture shall hold one requirement that is only
  re-wrapped, which is not an edit.
- **R4** — The fixture shall hold one requirement that head adds.
- **R5** — The fixture shall hold one more requirement that does not move.
- **R6** — The fixture shall hold one requirement that head supersedes.
  Superseded by R4. Replaced at head.
- **R7** — The fixture shall hold one requirement that head withdraws.
  Withdrawn. The behaviour is gone at head.
- **R9** — The fixture shall hold one requirement that was superseded before the base.
  Superseded by R1. Already superseded at the base, so it is not newly superseded.
- **R10** — The fixture shall hold one superseded requirement whose pointer moves.
  Superseded by R4. The pointer moves to R4 at head.
