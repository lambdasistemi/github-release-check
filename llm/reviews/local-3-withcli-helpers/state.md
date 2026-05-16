---
state: WaitingForSpecReview
issue: 3
branch: 3-withcli-helpers
worktree: /code/github-release-check-3
pr:
phase_stop: specs
mode: solo
role: orchestrator
sha:
review_file: specs/3-withcli-helpers/spec.md
updated_by: orchestrator
notes: |
  Spec drafted for issue #3 (withCli + versionOption helpers).
  Design decision locked at phase interview: optparse helper lives in
  a Cabal sublibrary `github-release-check:optparse`, not as a
  polymorphic API in core. Three open questions for the user are
  recorded in spec.md "Open questions for the user (specs stop)" —
  with recommendations. No plan/tasks/code yet; awaiting user review.
---

## Phase log

- 2026-05-16 — orchestrator: drafted spec.md, paused for user review
  per phase interview answer (`specs` stop).
