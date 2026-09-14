# Fixture spec — the BASE side of the delta fixture

Not a real spec. See `../README.md`.

## Requirements

- **R1** — The fixture shall hold one requirement that does not move between base and head.
- **R2** — The fixture shall hold one requirement whose sentence is rewritten.
- **R3** — The fixture shall hold one requirement that is only re-wrapped, which is not an edit.
- **R5** — The fixture shall hold one more requirement that does not move.
- **R6** — The fixture shall hold one requirement that head supersedes.
- **R7** — The fixture shall hold one requirement that head withdraws.
- **R8** — The fixture shall hold one requirement that head deletes outright.
- **R9** — The fixture shall hold one requirement that was superseded before the base.
  Superseded by R1. Already superseded at the base, so it is not newly superseded.
- **R10** — The fixture shall hold one superseded requirement whose pointer moves.
  Superseded by R6. The pointer moves to R4 at head.
