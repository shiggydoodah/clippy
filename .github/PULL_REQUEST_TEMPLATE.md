<!--
Use the GitHub PR title as the canonical work title.
Do not repeat the title as an H1 in this PR body.

Keep this PR high signal:
- Delete sections that are not materially relevant instead of filling them with N/A.
- Keep claims concrete and testable.
- If the Clipboard capture path is in scope, keep the capture-path checklist and its verification matrix.
- Add links (issues, related PRs) at the end when applicable.
-->

## Executive Summary

<!--
Explain the work in 1-3 short paragraphs for a reader who does not need every implementation detail.
Cover what changed, why it matters, and the practical impact on the app's behaviour.
Lightly technical is fine — avoid code walkthroughs and exhaustive file lists.
-->

## Summary

- Problem / intent:
- What changed in behaviour or design:
- Why this approach:
- Notable impact:
  - User-facing:
  - Data / storage:
- Out of scope (if any):

## Reviewer Guide

- Start review here (key files/paths):
- Highest-risk areas to scrutinise:
- Decisions worth challenging:

## Scope

- [ ] App lifecycle / status item (`Clippy/App`)
- [ ] Clipboard capture, classification, paste (`Clippy/Clipboard`)
- [ ] Storage, migrations, blobs (`Clippy/Storage`)
- [ ] Retention (`Clippy/Retention`)
- [ ] Panel and its views (`Clippy/Panel`)
- [ ] Settings (`Clippy/Settings`)
- [ ] Shared utilities (`Clippy/Shared`)
- [ ] Tests (`ClippyTests`)
- [ ] Project config / tooling / docs
- [ ] Other (describe):

## Risk, Privacy, and Correctness Notes

<!-- Keep this short for low-risk PRs. Expand only where it applies. -->

- Risk level and why:
- Privacy impact (what, if anything, newly reaches disk):
- Schema / migration impact (new migration? forward-only? tested against an existing DB?):
- Concurrency impact (what runs off the main thread, what state is actor-isolated):
- Performance impact (memory, idle CPU, panel summon latency):
- Dependencies added or changed (GRDB and KeyboardShortcuts are the only permitted packages):
- Recovery / rollback (what happens to an existing user's history if this ships and is reverted):

### Capture-Path Checklist (required when Clipboard, Storage, or Retention is in scope)

<!-- Delete this subsection if none of those are in scope. -->

- [ ] No networking introduced anywhere in the change
- [ ] Concealed, transient, and auto-generated pasteboard types are still skipped before any storage path
- [ ] Favourites remain exempt from every retention rule (age, count, size)
- [ ] Nothing new runs on the main thread — polling, classification, hashing, and blob writes stay on background queues
- [ ] The poll timer still does only a change-count comparison; no classification or filtering added to it
- [ ] Preview building stays bounded — O(limit), not O(length)
- [ ] Image thumbnails stay lazy and cached; no decoding at capture time
- [ ] Failures in the capture path are logged via `os.Logger` (subsystem `com.clip.app`), never swallowed
- [ ] No force unwrap (`!`) or force try (`try!`) added outside tests
- [ ] British spelling preserved in user-facing strings, type names, and DB columns

## Testing and Verification

- Automated coverage added/updated:
- Scenarios intentionally not covered yet (with reason/risk):
- Verification outcome summary (`pass`, `fail -> fixed -> pass`, `blocked`, or `skipped (docs-only; low risk)`):
  - Build:
  - Tests:
  - Manual run:

### Verification Commands Run

<!--
Run from the repo root. For docs-only PRs this block may be replaced with
`skipped (docs-only; reason)` plus a short low-risk rationale.
-->

```bash
xcodebuild -scheme Clippy -configuration Debug build
xcodebuild -scheme Clippy -destination 'platform=macOS' -only-testing:ClippyTests test
```

| Command                                         | Required | Result      |
| ----------------------------------------------- | -------- | ----------- |
| `xcodebuild ... build`                          | Yes      | `pass/fail` |
| `xcodebuild ... -only-testing:ClippyTests test` | Yes      | `pass/fail` |
| Ran the built app and exercised the change      | Yes      | `pass/fail` |

## Manual Verification

<!--
Tick only what this PR actually required. Anything touching capture, storage, or the
panel should cover the relevant rows below. Delete rows that do not apply.
-->

- [ ] Copying text, a URL, an image, and a file each produce the correct `kind`
- [ ] Copying from a password manager stores **nothing**
- [ ] Copying the same content twice does not create a duplicate row
- [ ] Panel appears over a fullscreen app
- [ ] Panel does not steal focus — the app underneath stays active
- [ ] Held ↓ through a history with a 100KB+ text clip: selection stays visible and on-screen, no stutter
- [ ] Idle memory under 60MB in Activity Monitor after 10 minutes

Additional focused checks:

- Flow/check:
- Expected outcome:
- Result (`pass/fail`):

## Notes for Reviewers

- Known tradeoffs / limitations:
- Deferred scope:
- Follow-up TODOs:

## Links

<!-- Remove if there are none. -->

- : [Link to ](...)
