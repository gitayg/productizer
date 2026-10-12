# Fixture spec — an import that marked nothing, named in the spec prose only

## Requirements

This section was drafted by Stage 0c from the existing repository.

### Ubiquitous — always active

- **R1** — The service shall serve a health endpoint.
- **R2** — The service shall log every request once.

### Event-driven

- **R3** — When a token expires, the service shall refuse the request.
- **R4** — When a job fails, the service shall retry it exactly once.

## Change log

| Date | Added | Summary |
|---|---|---|
| 2026-01-02 | R1–R4 | Drafted from the existing repository. |

## Decision record

| Date | Decision | Why | Who |
|---|---|---|---|
