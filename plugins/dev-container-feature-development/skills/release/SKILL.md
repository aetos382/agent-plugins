---
name: release
description: Releases Dev Container Features from the current repository. Finds Features with unreleased changes, bumps their versions through a pull request, runs the release workflow, and verifies the tags on ghcr.io. Invoke as /dev-container-feature-development:release, optionally with Feature IDs.
argument-hint: "[feature-id ...]"
disable-model-invocation: true
---

# Release Dev Container Features

When Feature IDs are given as arguments, release only those. Otherwise consider every Feature under `src/`.

Reply to the user in the language they use. Stop and report whenever a step produces an unexpected result; do not work around it.

## Confirmation policy

Merging a pull request and running the release workflow are the two irreversible steps. Before each one, check whether approval is already required at run time: look for `permissions.ask` rules matching `gh pr merge` and `gh workflow run` in every settings scope that can be read, namely `.claude/settings.json` and `.claude/settings.local.json` in the project and `~/.claude/settings.json`.

- **Ask rules exist:** state what is about to happen ("Merging #12", "Running release.yaml on main") and run the command. The ask rule prompts the user, so asking in chat as well would make them confirm twice.
- **No ask rules:** ask in chat and wait for approval before running the command.

Run `gh pr merge` and `gh workflow run` as standalone commands, never chained with `&&` or `;`, so that the approval covers exactly that command.

## 1. Preconditions

- `git`, `gh`, `curl`, and `jq` are installed. Check each one separately, since `command -v` with several names succeeds when any of them exists: `for c in git gh curl jq; do command -v "$c" >/dev/null || echo "missing: $c"; done`. When one is missing, report it and stop.
- `git status --porcelain` is empty.
- After `git fetch origin`, the current branch is the default branch and matches its remote-tracking branch. Skipping the fetch makes merged changes look unmerged.
- Collect repository facts:
  - `gh repo view --json nameWithOwner,isInOrganization,defaultBranchRef`
  - The release workflow: the file under `.github/workflows/` that uses `devcontainers/action` with `publish-features: "true"`. Stop when there is none and suggest the `init-repository` skill.
  - The namespace: the workflow's `features-namespace` input when set, otherwise `<owner>/<repo>`. Lowercase it.
  - The GitHub package name of a Feature: the namespace without its first segment (the owner), followed by `/<id>`, with `/` encoded as `%2F`. For the namespace `octo/devcontainer-features` and the Feature `mytool`, that is `devcontainer-features%2Fmytool`. It is written `<package>` below.

## 2. Find what to release

For each Feature (in parallel across Features):

- Local version: `jq -r .version src/<id>/devcontainer-feature.json`
- Published version: `bash "${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/published-tags.sh" --max-semver <namespace>/<id>`
  - Exit 1: a network or registry problem. Stop and report; never treat it as "not published".
  - Exit 2: private or never published. Tell the two apart with `gh api <orgs|users>/<owner>/packages/container/<package> --jq .visibility` (`orgs` when `isInOrganization` is true):

    | Response | Meaning | Action |
    |---|---|---|
    | 404 Package not found | Never published | Treat as **first release** |
    | `private` | Published but private | The published version cannot be read. Stop and ask the user to make it public (see step 5) |
    | `public` | Public, yet anonymous access was denied | Unexpected. Stop and report |
    | 403 (missing `read:packages` scope) | Visibility unknown | Likely private. Ask the user |

- Last version bump: `git log -1 --format=%H -G'"version"[[:space:]]*:[[:space:]]*"' -- src/<id>/devcontainer-feature.json`. The pattern requires a string value, so that adding or removing an option named `version` (`"version": {`) is not mistaken for a bump. Confirm the result with `git show <commit> -- src/<id>/devcontainer-feature.json` when the file has several string-valued `version` keys.
- Changes since then: `git log --oneline <commit>..HEAD -- src/<id>` and `git diff <commit>..HEAD -- src/<id>`. Ignore changes that touch only `src/<id>/README.md`, which the release workflow regenerates.

Classify and present a table to the user:

| State | Condition | Action |
|---|---|---|
| First release | Never published | Publish the current version |
| Awaiting publish | Local > published | Publish without a bump (step 4) |
| Needs bump | Local = published, and `src/<id>` changed since the last bump | Step 3 |
| Error | Local < published | Stop and report |
| Up to date | Otherwise | Nothing |

Do not skip the "Awaiting publish" check. When this skill is rerun after a bump was merged but before the workflow succeeded, there are no changes since the last bump, and without the version comparison the Feature would be classified "Up to date" and never published.

## 3. Bump versions

Propose a bump for each Feature from its changes, using these criteria, and **wait for the user to confirm**:

- **Major**: existing users' configuration behaves differently or loses data. Removed options or changed meaning; changed install paths, volume names, or mount targets; a new `dependsOn`.
- **Minor**: backward-compatible additions. New options, new warnings or detection, broader platform support.
- **Patch**: bug fixes and documentation-only changes.

Then:

1. Create `release/<id>-v<version>`, or `release/<YYYY-MM-DD>` when bumping several Features.
2. Update `version` in each `src/<id>/devcontainer-feature.json`.
3. Commit following the repository's commit message conventions (check `git log`); when there are none, use `<id>: v<version>`. Push and open a pull request whose body lists the changes since the last release and the reason for each bump.
4. Wait for CI as described in "Waiting for checks" below. Stop and report on failure.
5. Merge following the confirmation policy: `gh pr merge <pr> --merge --delete-branch`. When the repository does not allow merge commits, use the method it allows (`gh repo view --json mergeCommitAllowed,squashMergeAllowed,rebaseMergeAllowed`).
6. `git switch <default-branch>` and `git pull --ff-only`.

## 4. Publish

Only when at least one Feature is "First release", "Awaiting publish", or was bumped in step 3. The workflow publishes every Feature under `src/` and skips versions that already exist.

1. Record, before dispatching:
   - The latest run ID: `gh run list --workflow <file> --limit 1 --json databaseId --jq '.[0].databaseId // empty'`
   - A reference time 60 seconds in the past, to absorb clock skew: `jq -n -r 'now - 60 | todate'`
2. List the Features and versions to be published, then run `gh workflow run <file> --ref <default-branch>` following the confirmation policy.
   - HTTP 403 `Resource not accessible by integration` means the token lacks Actions write permission. In Codespaces, that permission must be requested in `devcontainer.json` (`customizations.codespaces.repositories.<owner>/<repo>.permissions.actions: write`) and approved when the Codespace is created. Ask the user to run the workflow from `https://github.com/<owner>/<repo>/actions/workflows/<file>` on the default branch, and continue with step 4.3 once they confirm.
3. `gh workflow run` returns no run ID. Find the new run:

   ```bash
   gh run list --workflow <file> --event workflow_dispatch --branch <default-branch> --limit 10 \
     --json databaseId,createdAt,url \
     --jq '[.[] | select(.databaseId != <PREV_ID> and .createdAt >= "<SINCE>")]'
   ```

   Drop the `.databaseId != <PREV_ID> and` part when no previous run existed. With one candidate, use it. With several, show their times and URLs and let the user choose. With none, retry every few seconds and report if none appears within about a minute. Filtering by actor does not help: runs dispatched from a Codespace token and from the web UI have the same actor.
4. `gh run watch <id> --exit-status`. On failure, report `gh run view <id> --log-failed`.

## 5. Verify

1. For each published Feature, list the tags with `published-tags.sh` (without `--max-semver`). Expect the new version, its major and minor tags (`1.2.3` → `1`, `1.2`), and `latest`.
   - Exit 2 after a first release means the package is private; ghcr.io creates packages private by default. Ask the user to make it public at `https://github.com/<orgs|users>/<owner>/packages/container/<package>/settings` (there is no API for this), then verify again.
2. When the workflow opened a documentation pull request (branch `automated-documentation-update-*`):
   1. `gh pr close <pr>`, then `gh pr reopen <pr>`. The pull request was created with `GITHUB_TOKEN`, which does not trigger `pull_request` workflows, so required checks would never report. Reopening it as the user starts them.
   2. Wait for CI as described in "Waiting for checks" below.
   3. Merge following the confirmation policy, then `git pull --ff-only`.

Finish with a summary: published versions, pull requests, and workflow run URLs.

## Waiting for checks

Right after a pull request is created or reopened, no workflow may have been queued yet, and `gh pr checks <pr> --watch` then exits with "no checks reported" instead of waiting. Poll `gh pr checks <pr>` every few seconds until at least one check is listed, for up to about a minute, then run `gh pr checks <pr> --watch`. When no check appears within that time, report it rather than treating the pull request as passed or failed.
