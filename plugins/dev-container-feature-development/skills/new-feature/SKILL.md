---
name: new-feature
description: This skill should be used when the user asks to "create a new Dev Container Feature", "add a feature that installs X", "make a feature for X", "scaffold a feature", "write a feature that installs X", or runs /dev-container-feature-development:new-feature. Interviews the user about what the Feature installs, researches the upstream distribution, implements install.sh and its tests, runs them, and has the result reviewed.
argument-hint: "[feature-id] [what it installs]"
---

# Create a new Dev Container Feature

Take a Feature from idea to tested implementation in the current repository. Load the `feature-authoring` and `feature-testing` skills before writing any file; they define the conventions this workflow applies.

Reply to the user in the language they use. Do not commit; offer to at the end.

## 1. Check the repository

- The repository should be a Features collection: `src/` and a test workflow that runs `devcontainer features test`. When either is missing, suggest running the `init-repository` skill first, and continue only if the user wants to.
- When the argument names an ID, check that `src/<id>/` does not exist yet.

## 2. Research, then interview

Start from what the user already said. Before asking anything, research the upstream so that the questions can offer concrete choices:

- How the upstream distributes the tool: GitHub Releases assets, a vendor download URL, an apt repository, a language package manager, or an install script.
- Whether it publishes checksums or signatures, and in which format; the signing key's fingerprint, if any.
- Release asset naming across versions and architectures, and how the latest version can be discovered.
- Whether the tool needs per-user setup (config in the home directory, shell integration) or environment variables.

Use `gh release view -R <owner>/<repo>` and `gh release list` for GitHub-hosted projects and web search or fetch for others.

Then ask, with `AskUserQuestion`, about what remains open. Typical questions:

1. **ID and name**: propose a lowercase, hyphenated ID that does not collide with an existing `src/<id>`.
2. **Install method**: recommend a download of a verified release artifact over an apt repository or a piped install script. An apt repository lets `apt-get upgrade` move a pinned version, and an unverified install script runs whatever the server returns.
3. **Options**: `version` (with `latest`) is almost always right. Propose others only for behavior users will plausibly want to change.
4. **Per-user behavior**: whether the Feature configures anything for `_REMOTE_USER`.
5. **Architectures**: which of the upstream's Linux architectures to support.

Summarize the design (ID, options with defaults, install method, verification, files to create) and get the user's confirmation before writing files.

## 3. Implement

Create, following the `feature-authoring` skill:

- `src/<id>/devcontainer-feature.json` with `version` `1.0.0`, `documentationURL` and `licenseURL` pointing at this repository.
- `src/<id>/install.sh`, starting from the structure of `${CLAUDE_PLUGIN_ROOT}/skills/feature-authoring/examples/install.sh` and adapting it. The patterns it does not cover are in `${CLAUDE_PLUGIN_ROOT}/skills/feature-authoring/references/install-script.md`. Remove patterns that do not apply rather than leaving dead code.
- `src/<id>/NOTES.md` with How it works, Requirements, and Limitations.
- Any additional files the Feature packages.

Then the tests, following the `feature-testing` skill:

- `test/<id>/test.sh` for the default options.
- `test/<id>/scenarios.json` with a scenario per behavior-changing option value, a `non_root_user` scenario when anything touches a user's environment, and, when the Feature installs dependencies, a bare-image scenario that exercises that installation. Spread scenarios across the supported releases.
- `test/<id>/duplicate.sh` when options change what gets installed.
- `test/<id>/negative-tests.md` for every failure path in `install.sh` that tests cannot express.

Make `install.sh` and every test script executable, so that they can be run directly and match the convention of published Features. Use `chmod +x`, then record the mode with `git add --chmod=+x <files>`: on Windows, or with `core.fileMode=false`, Git does not pick up the bit from the file system. Tell the user that this stages the files.

Also update:

- The Features table in the root `README.md`, when there is one.
- The test workflow's Feature list, only if it hard-codes one instead of discovering Features from `src/`.

Run `shellcheck` on every new script when it is available and fix what it reports.

## 4. Test

Run the `run-feature-tests` skill for the new ID. Fix failures that are clearly caused by the new code and rerun; the user asked for a working Feature, so this loop is part of the task. When a failure points at a design decision (for example an upstream that does not publish checksums for one architecture), stop and ask.

## 5. Review

Launch the `feature-reviewer` agent on `src/<id>/` and `test/<id>/`. Present its findings with their numbers. Apply the fixes the user accepts, then rerun the affected tests.

## 6. Finish

Report the files created, the test results table from `run-feature-tests`, and the review outcome. Remind the user that the new Feature is published by the `release` skill (as a first release at `1.0.0`), and offer to commit the changes on a topic branch.
