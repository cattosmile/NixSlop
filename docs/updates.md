# Update automation

## Operational outcome

Each dependency family has a small named workflow, a unique
`update/<target>` branch, and a fixed validation/build boundary. All callers
share the `nixslop-update-global` concurrency group with cancellation disabled
and `queue: max`, so up to 100 pending runs are retained and processed one at a
time, ordered by when they actually begin waiting. GitHub does not guarantee
dispatch/start ordering. Even independent `flake.lock` updates therefore share
one publication lane. The reusable workflow never accepts a command or path
from a caller; its only input is the validated `program` enum.

## Daily schedule

GitHub Actions cron expressions use UTC.

| Workflow name | Target | Schedule |
| --- | --- | --- |
| `Update Codex` | `codex` | 00:17 daily |
| `Update Codex Desktop` | `codex-desktop` | 02:47 daily |
| `Update oh-my-codex` | `oh-my-codex` | 10:17 daily |
| `Update Foundations` | `foundations` | 12:47 daily |
| `Update Health` | sentinel | 23:47 daily |

Every update caller also supports manual dispatch. Dispatch the named caller,
not the reusable implementation workflow, to retain its permissions, explicit
secret forwarding, and global mutex.

## Fixed ownership and build map

`scripts/validate_update.py` rejects additions, deletions, renames, copies, and
paths outside these allowlists:

| Target | Update command | Allowed changed paths | Build/smoke scope |
| --- | --- | --- | --- |
| `codex` | Codex updater | `packages/codex/hashes.json` | `codex`, `oh-my-codex` |
| `codex-desktop` | Update `codex-desktop-linux` input | `flake.lock` | Computer Use backend plus all four desktop outputs |
| `oh-my-codex` | OMX updater | OMX `hashes.json` and `Cargo.lock` | `oh-my-codex` |
| `foundations` | Update `nixpkgs`, `systems`, and `home-manager` inputs | `flake.lock` | all seven public package outputs |

For lock-file targets, the validator compares semantic input graphs rather than
generated node names. Protected root-input closures must remain identical, the
intended closure must change, and unreachable lock nodes are rejected.

Every non-empty update runs, in order:

1. Python updater and workflow contract tests.
2. The fixed updater and exact ownership validation.
3. `nix flake check --all-systems --no-build --print-build-logs`.
4. Real x86 builds of the module, output, generated Home Manager, formatting,
   actionlint, and workflow-contract checks.
5. The real patch-source and packaged Computer Use desktop-plugin checks for
   desktop/foundation changes.
6. Target package builds and executable smoke tests. Foundations builds all
   seven outputs; Codex also builds OMX because the wrapper embeds Codex.

The `queue: max` key is supported by GitHub Actions but is newer than the
actionlint 1.7.12 concurrency schema. `.github/actionlint.yaml` suppresses only
that exact stale-schema diagnostic and only for the four fixed callers; every
other actionlint diagnostic remains enabled.

The normal `Check` workflow independently evaluates contracts and runs an
all-seven build matrix on pull requests and pushes to `main`.

## Pull request state machine

At preparation time the workflow records the exact `origin/main` SHA. Validated
changes are committed to the target's unique branch and pushed only after all
in-workflow checks pass and a fresh fetch proves that `main` is unchanged.
The workflow records that exact validated commit SHA, verifies that the remote
branch received it, and requires the PR's `headRefOid` to remain equal to it
through publish, create/edit, auto-merge, and polling. Automation then creates
or updates the target PR. Every PR lookup and mutation is constrained to a
same-repository PR whose base is exactly `main` and whose head is the exact
`update/<target>` branch; fork PRs with a matching branch name cannot be
selected. A previously quarantined `CLOSED` PR is reopened deterministically;
a prior `MERGED` PR results in a new PR for the new branch contents.

The workflow enables squash auto-merge, then polls every 30 seconds for at most
120 minutes:

- `MERGED` is success.
- `CLOSED`, `DIRTY`, API failure, identity mismatch, base drift, head drift, or
  timeout is failure.
- Other open merge states continue polling because branch policy may still be
  evaluating them.

Immediately before enabling auto-merge, and on every poll while the PR remains
open, both the freshly fetched `origin/main` SHA and the PR's `baseRefOid` must
still equal the SHA captured at preparation. Any drift fails closed and routes
the PR through quarantine instead of silently merging a result validated
against a different base. Auto-merge also uses GitHub's atomic
`--match-head-commit` guard, and even a `MERGED` poll result is accepted only
when the frozen PR values still satisfy `baseRefOid == expected_base` and
`headRefOid == expected_head`.

Before the global mutex is released, every non-merged PR is handled by an
`always()` cleanup step. It recovers the PR from the target branch if a partial
publish failed before recording its number, disables auto-merge, applies the
`update-quarantined` label, records the terminal reason, closes the PR, and
verifies the closed state. Cleanup failure hard-fails the workflow. Branches are
not deleted, allowing the next run to update and reopen the same target PR.
For an `OPEN` or `CLOSED` PR, cleanup deliberately permits changed base/head
OIDs so a compromised or raced update branch can still be quarantined, while
retaining the immutable same-repository/base-name/head-name identity boundary.
If the PR is already `MERGED`, cleanup records success only after proving both
its frozen `baseRefOid` and `headRefOid` equal the validated SHAs; a drifted
merge remains a hard workflow failure.

## Permissions, tokens, and repository policy

Both caller and reusable workflows explicitly grant `contents: write` and
`pull-requests: write`; reusable workflow permissions cannot elevate caller
permissions. Callers do not use `secrets: inherit`. The optional
`CACHIX_AUTH_TOKEN` is forwarded by name and is the only caller secret accepted
by the reusable workflow.

The built-in `GITHUB_TOKEN` is used for branches and pull requests. Pull
requests created by that token may not trigger a separate `pull_request`
workflow under repository policy, so the updater does not rely on `Check`
finishing: it performs the complete target validation before push. Auto-merge
also requires repository auto-merge, squash merging, and branch rules that are
compatible with automation. If protected checks must run automatically for bot
PRs, use a narrowly scoped GitHub App or PAT rather than weakening validation.

## Stable health signal for Hermes

`Update Health` has read-only `actions: read` and `contents: read` permissions.
It queries the latest **scheduled** run of each of the seven exact workflow names;
manual successes cannot mask a missed daily schedule. Every latest run must be
`completed` with conclusion `success`, and its schedule-entry `created_at`
timestamp must be no more than 36 hours old. The creation time is deliberate:
manually re-running an old scheduled run changes its update time but cannot mask
a missing daily schedule. The window tolerates ordinary GitHub schedule delays
and the serialized update queue while detecting a missed day.

Hermes should monitor the workflow named `Update Health`. It must validate both
the run conclusion and that the newest `Update Health` run itself was created
no more than 36 hours ago. The sentinel validates the seven updater workflows,
but a disabled or unscheduled sentinel cannot report its own absence. Do not
configure Hermes against a repository-wide generic latest run: unrelated CI or
manual dispatches would make that signal unstable.
