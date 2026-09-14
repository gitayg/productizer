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
