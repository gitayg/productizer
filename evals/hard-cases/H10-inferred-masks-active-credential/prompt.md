---
name: H10-inferred-masks-active-credential
tags: [positive, inferred, domain-entailment, booking, b18-hard]
plugins: ["../../../plugins/productizer"]
runs: 3
max_turns: 10
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep, Skill]
---

Run intake on the intent below for the `booking service`.

Everything this product has ever agreed is reproduced in full in this message.
There is no repository state for it: do not look for `.claude/productizer/`, do
not read or write any file outside the plugin you are running with, and do not
assume any requirement or principle that is not written below.

## Living spec

# Booking service — living spec

System
: `booking service` — the exact noun every requirement below uses. Never vary it.

Next requirement id
: `R43`

Requirements
: 38 active, 1 superseded, 1 withdrawn, 2 inferred.

## How to read this file

| Status | Meaning | Recorded as |
|---|---|---|
| Active | Current agreed behaviour | no marker; the requirement, plain |
| Superseded | Replaced by another requirement | `Superseded by R…` plus one line on why |
| Withdrawn | The behaviour no longer exists at all | `Withdrawn.` plus one line on why |
| Inferred | Read from the code on import; nobody has agreed to it | `Inferred from …` and `Unconfirmed.` |

An inferred requirement becomes active only when a human confirms it.

## Requirements

### Ubiquitous — always active

- **R1** — The booking service shall record the client, the practitioner and
  the time of every change to a booking.
- **R2** — The booking service shall store every appointment time in UTC and
  display it in the clinic's local time zone.
- **R12** — The booking service shall issue each video session credential no
  more than 15 minutes before the session starts.
- **R29** — The booking service shall be available for at least 99.5 percent of
  each calendar month.
- **R40** — The booking service shall send each client exactly one advance
  reminder per appointment, 24 hours before its start.
- **R42** — The booking service shall send every client-facing message in the
  language chosen on the client's profile.

### Event-driven

#### Search and booking

- **R3** — When a client searches for availability, the booking service shall
  list only slots that have a practitioner assigned.
- **R4** — When a client books a slot, the booking service shall send a booking
  confirmation within 1 minute.
- **R5** — When a client requests available slots, the booking service shall
  respond in roughly 800 ms.
- **R6** — When two clients book the same slot, the booking service shall
  confirm the first booking and refuse the second.
- **R7** — When a client books an appointment, the booking service shall take a
  deposit of 20 percent of the appointment fee.
- **R8** — When a client books an appointment, the booking service shall show
  the clinic's cancellation policy before taking payment.
- **R9** — When a clinic publishes a holiday closure, the booking service shall
  hide every slot inside the closure from search.
- **R41** — When a practitioner sets working hours, the booking service shall
  offer slots only inside those hours.

#### Reminders and messages

- **R11** — When an appointment is 48 hours away, the booking service shall send
  the client a reminder.
  Superseded by R40. Ruled 2026-05-11 (D4): clients who received two advance
  reminders cancelled more often, so there is one, 24 hours out.
- **R19** — When an appointment is cancelled by anyone, the booking service
  shall notify the practitioner within 5 minutes.
- **R26** — When an appointment ends, the booking service shall send the client
  a receipt.

#### Waitlist

- **R14** — When a slot is freed, the booking service shall offer it only to the
  first client on that practitioner's waitlist for 30 minutes.
- **R15** — When a waitlisted client declines an offered slot, the booking
  service shall keep them in their waitlist position.
- **R23** — When a client joins a waitlist, the booking service shall tell them
  their position on it.

#### Cancellations, changes and attendance

- **R13** — When a client moves an appointment to a new time, the booking
  service shall carry the deposit already paid to the new time.
- **R16** — When a client cancels more than 24 hours before the start, the
  booking service shall refund the deposit in full.
- **R17** — When a client cancels 24 hours or less before the start, the booking
  service shall retain the deposit.
- **R18** — When a practitioner cancels an appointment, the booking service
  shall refund the deposit in full.
- **R22** — When an appointment is marked as a no-show, the booking service
  shall retain the deposit.
- **R25** — When a client arrives at the clinic, the booking service shall
  record their arrival time.

#### Video

- **R35** — When a video appointment is booked, the booking service shall leave
  the joining link out of the booking confirmation.
  Inferred from test `test_join_link_not_in_confirmation`
  (`tests/test_video.py`). Unconfirmed.

#### Practitioners and records

- **R37** — When a practitioner opens a client's booking history, the booking
  service shall show only the bookings with that practitioner.
- **R38** — When a client requests deletion of their account, the booking
  service shall delete their contact details within 30 days.

#### Integrations

- **R21** — When a clinic administrator exports the day's bookings, the booking
  service shall produce a CSV sorted by start time.
- **R31** — When a booking changes, the booking service shall publish a
  `booking.updated` webhook carrying the field `starts_at`.
- **R32** — When a practitioner's external calendar shows an event overlapping
  a booked appointment, the booking service shall alert the practitioner.

### State-driven

- **R10** — While a practitioner is marked on leave, the booking service shall
  refuse new bookings with that practitioner.
- **R24** — While a client has not arrived by 15 minutes after the start, the
  booking service shall mark the appointment as a no-show.
- **R39** — While the payment provider is unreachable, the booking service shall
  refuse new bookings that need a deposit.

### Unwanted behaviour

- **R20** — If a refund fails to reach the client's card, then the booking
  service shall retry it once a day for 5 days and then alert the finance team.
- **R30** — If a deposit payment fails, then the booking service shall release
  the slot after 15 minutes.
- **R33** — If a calendar sync fails, then the booking service shall retry it
  every 5 minutes for 1 hour.
- **R36** — If a client has three no-shows within 90 days, then the booking
  service shall block that client from booking online.
  Inferred (weak evidence) from `docs/policies.md` heading "Repeat no-shows".
  Unconfirmed. No code, test or config in this repo asserts this.

### Optional

- **R27** — Where a clinic enables proxy booking, the booking service shall let
  a client book an appointment for another adult.
  Withdrawn. Ruled 2026-04-02 (D3): see the decision record.
- **R28** — Where a clinic offers group sessions, the booking service shall cap
  each session at the size the clinic sets.
- **R34** — Where a clinic offers video appointments, the booking service shall
  let the client choose video or in person when booking.

## Design

### Video
The joining link embeds the single-use session credential. There is no joining
link without a credential. Serves R12, R34.

### Calendar sync
Sync runs per practitioner every 5 minutes; a failed run leaves the last
successful copy in place. Serves R32, R33.

## Acceptance criteria

| Requirement | Verified by | How |
|---|---|---|
| R1 | `test_every_change_is_attributed` | each mutation writes client, practitioner and time |
| R2 | `test_times_stored_utc` | stored value UTC, rendered in clinic zone |
| R3 | `test_search_hides_unassigned_slots` | slot without practitioner absent from results |
| R4 | `test_confirmation_within_a_minute` | confirmation sent under 60 s after booking |
| R5 | `test_slot_search_latency` | p95 over the fixture load below 800 ms |
| R6 | `test_double_booking_refused` | second booking of one slot refused |
| R7 | `test_deposit_twenty_percent` | deposit equals 20 percent of fee |
| R8 | `test_policy_shown_before_payment` | policy page precedes payment step |
| R9 | `test_closure_hides_slots` | slots inside a closure absent from search |
| R10 | `test_leave_refuses_bookings` | booking with practitioner on leave refused |
| R12 | `test_credential_minted_late` | credential issued at most 15 min before start |
| R13 | `test_move_carries_deposit` | moved booking keeps its deposit |
| R14 | `test_freed_slot_waitlist_first` | only waitlist head can book for 30 min |
| R15 | `test_decline_keeps_position` | position unchanged after decline |
| R16 | `test_early_cancel_refunds` | cancel at 25 h refunds deposit |
| R17 | `test_late_cancel_retains` | cancel at 24 h retains deposit |
| R18 | `test_practitioner_cancel_refunds` | practitioner cancel refunds deposit |
| R19 | `test_cancel_notifies_practitioner` | notification under 5 min |
| R20 | `test_refund_retry_then_alert` | 5 daily retries, then finance alert |
| R21 | `test_export_csv_sorted` | CSV rows ordered by start time |
| R22 | `test_no_show_retains_deposit` | no-show keeps deposit |
| R23 | `test_waitlist_position_told` | join response carries position |
| R24 | `test_no_show_at_fifteen_minutes` | unarrived at 15 min marked no-show |
| R25 | `test_arrival_time_recorded` | arrival writes a timestamp |
| R26 | `test_receipt_after_appointment` | receipt sent on end |
| R28 | `test_group_cap` | booking over cap refused |
| R29 | `test_monthly_availability_budget` | synthetic probe uptime for the month |
| R30 | `test_failed_deposit_releases_slot` | slot free 15 min after failure |
| R31 | `test_booking_webhook_shape` | payload validated against published schema |
| R32 | `test_calendar_overlap_alert` | overlapping external event alerts practitioner |
| R33 | `test_sync_retry_schedule` | 12 retries over an hour |
| R34 | `test_video_or_in_person_choice` | booking form offers both where enabled |
| R37 | `test_history_scoped_to_practitioner` | other practitioners' bookings absent |
| R38 | `test_account_deletion_contact_details` | contact details gone by day 30 |
| R39 | `test_provider_down_refuses_deposit_bookings` | booking needing deposit refused |
| R40 | `test_one_advance_reminder` | exactly one reminder, at 24 h |
| R41 | `test_slots_inside_working_hours` | no slot outside set hours |
| R42 | `test_messages_in_profile_language` | message language matches profile |

## Change log

| Date | Added | Refined | Superseded / withdrawn | Summary |
|---|---|---|---|---|
| 2026-02-02 | R1–R34 | — | — | first spec for the booking service |
| 2026-03-09 | R35–R39 | — | — | import survey; R35 and R36 left inferred |
| 2026-04-02 | — | — | R27 withdrawn | proxy booking withdrawn (D3) |
| 2026-05-11 | R40–R42 | — | R11 → R40 | one advance reminder (D4) |

## Decision record

| Date | Decision | Why | Who |
|---|---|---|---|
| 2026-02-02 | D1 — Published webhook payloads change only by a new version. | Integrators cannot be rolled back on our behalf. | API owner |
| 2026-04-02 | D3 — The booking service will not let a client book an appointment for another adult, in any configuration. R27 withdrawn. | The consent of the adult being booked could not be verified, and two bookings were made by estranged partners. Bookings made by a parent or guardian for a child under 16 were not part of this decision. | Clinical governance lead |
| 2026-05-11 | D4 — One advance reminder per appointment, 24 hours before the start. R11 superseded by R40. | Clients who received two advance reminders cancelled more often. | Client experience lead |

## Constitution

# Booking — constitution

Product
: `booking`

Next principle id
: `P5`

## Principles

### P1 — A published contract is never changed in place
Active. Ratified 2026-02-02 by the API owner.

A webhook, field or event shape published to anyone outside this product
changes only by adding a new version alongside the old one.

Prevents
: Breaking an integration we cannot see and cannot roll back on the caller's
behalf.

Checked by
: The contract diff job in CI.

Enforced by
: R31.

### P2 — A client pays only for their own choices
Active. Ratified 2026-02-02 by the finance and clinical governance owners.

A client never loses money over a booking that someone other than the client
ended. A booking cancelled by a practitioner, by the clinic, or by the booking
service itself — including one cancelled to resolve a calendar-sync conflict —
is refunded in full, whatever the notice given.

Prevents
: Charging people for our own scheduling failures, which is the complaint that
most often reaches a regulator.

Checked by
: `test_practitioner_cancel_refunds`.

Enforced by
: R18.

### P3 — Every change to a booking is attributable
Active. Ratified 2026-02-02 by the clinical governance owner.

No booking is created, moved, cancelled or marked without a record of who or
what did it and when.

Prevents
: A disputed charge or a missed appointment that nobody can reconstruct.

Checked by
: `test_every_change_is_attributed`.

Enforced by
: R1.

### P4 — Clinical content never travels in a notification
Active. Ratified 2026-02-02 by the clinical governance owner.

Reminders, confirmations, receipts, texts and emails carry times, places and
names only. No diagnosis, treatment, clinical note or reason for the visit.

Prevents
: Health information landing on a shared phone or a work inbox.

Checked by
: The message template lint in CI.

Enforced by
: No requirement yet; the lint is the only control.

## Arriving intent

Put the video joining link in the booking confirmation, so clients can test
their camera and connection days before the appointment instead of scrambling
at the last minute.

## What to produce

Classify this intent against the spec and the constitution above as exactly one
of **extend**, **refine**, **duplicate** or **contradict**. Cite every
requirement id (`R…`) and principle id (`P…`) that bears on the decision, state
what happens to the spec next, and say plainly what has and has not been merged.

End your reply with exactly this line, and nothing after it:

VERDICT: <EXTEND|REFINE|DUPLICATE|CONTRADICT>
