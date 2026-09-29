---
name: init-repository
description: This skill should be used when the user asks to "set up a Dev Container Features repository", "initialize a feature collection", "add CI for my features", "retrofit the release workflow", "bring this features repo up to date", or runs /dev-container-feature-development:init-repository. Creates or updates the workflows, dev container, and repository files that the other skills of this plugin expect, in a new or an existing repository.
---

# Initialize a Dev Container Features repository

Set up the current Git repository as a collection of Dev Container Features published to ghcr.io, or bring an existing collection in line with the layout that the `new-feature`, `run-feature-tests`, and `release` skills expect. Works on empty repositories and on repositories that already contain Features.

Reply to the user in the language they use. This skill writes files in the working tree only. It never commits, pushes, or changes repository settings on GitHub; those steps are listed for the user at the end.

## 1. Survey

1. Confirm the working directory is the root of a Git repository (`git rev-parse --show-toplevel`).
2. Identify the repository: `gh repo view --json nameWithOwner,isInOrganization`. When `gh` is unavailable or the repository has no GitHub remote yet, ask the user for `<owner>/<repo>`.
3. Record what exists. Identify workflows by what they do, not by file name:

   | Role | How to recognize it |
   |---|---|
   | Test | runs `devcontainer features test`, or calls a reusable workflow that does |
   | Release | uses `devcontainers/action` with `publish-features: "true"` |
   | Validate | uses `devcontainers/action` with `validate-only: "true"`, or runs `shellcheck` |

   Also check `src/*/devcontainer-feature.json`, `test/*/`, `.devcontainer/devcontainer.json`, `README.md`, `LICENSE`, and `.gitattributes`.
4. Record how dependencies are updated: `.github/dependabot.yml`, and a Renovate configuration in any of the locations Renovate reads (`renovate.json`, `renovate.json5`, `.github/renovate.json`, `.github/renovate.json5`, `.gitlab/renovate.json`, `.gitlab/renovate.json5`, `.renovaterc`, `.renovaterc.json`, `.renovaterc.json5`, or a `renovate` key in `package.json`).

## 2. Choose the dependency updater

Dependabot or Renovate keeps the pinned actions and the dev container's Features up to date. Decide which one in this order, and stop at the first rule that applies:

1. **The repository already uses one.** Keep it and do not add the other. A `dependabot.yml` that covers only the `devcontainers` ecosystem next to a Renovate configuration counts as Renovate.
2. **The user's instructions name one**, for example in `CLAUDE.md` or memory. Follow them, including any shared Renovate preset they name.
3. **Otherwise, ask** with `AskUserQuestion`. Recommend Dependabot: it is built into GitHub and needs no app installation. Offer Renovate for users who already run it elsewhere.

## 3. Resolve template values

The templates in `assets/` contain placeholders. Resolve them now; never leave a placeholder in a written file.

| Placeholder | Value |
|---|---|
| `__OWNER_REPO__` | `<owner>/<repo>` as GitHub displays it |
| `__NAMESPACE__` | `<owner>/<repo>` in lowercase |
| `__REPO__` | `<repo>` |
| `__CHECKOUT_REF__` | Latest release of `actions/checkout`, as `<sha> # <tag>` |
| `__DEVCONTAINERS_ACTION_REF__` | Latest release of `devcontainers/action`, as `<sha> # <tag>` |
| `__DIND_MAJOR__`, `__GITHUB_CLI_MAJOR__`, `__NODE_MAJOR__` | Current major version of `docker-in-docker`, `github-cli`, `node` in `ghcr.io/devcontainers/features` |

Pin actions to the commit of their latest release. Resolve the tag, then the commit it points to:

```bash
tag="$(gh release view -R actions/checkout --json tagName --jq .tagName)"
git ls-remote https://github.com/actions/checkout "refs/tags/${tag}" "refs/tags/${tag}^{}"
```

When two lines come back, the tag is annotated: use the SHA on the `^{}` line, which is the commit.

Find a Feature's current major version with the release skill's script:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/release/scripts/published-tags.sh" --max-semver devcontainers/features/docker-in-docker
```

and take the part before the first dot.

## 4. Plan

Map each template to its destination:

| Template | Destination |
|---|---|
| `assets/workflows/test.yaml` | `.github/workflows/test.yaml` |
| `assets/workflows/test-feature.yaml` | `.github/workflows/test-feature.yaml` |
| `assets/workflows/release.yaml` | `.github/workflows/release.yaml` |
| `assets/workflows/validate.yaml` | `.github/workflows/validate.yaml` |
| `assets/devcontainer/devcontainer.json` | `.devcontainer/devcontainer.json` |
| `assets/README.md` | `README.md` |
| `assets/gitattributes` | `.gitattributes` |

Add the templates for the chosen dependency updater:

| Updater | Template | Destination |
|---|---|---|
| Dependabot | `assets/dependabot.yml` | `.github/dependabot.yml` |
| Renovate | `assets/renovate.json` | `renovate.json` |
| Renovate | `assets/dependabot-devcontainers.yml` | `.github/dependabot.yml` |

With Renovate, Dependabot still updates the dev container's Features. Renovate cannot update `devcontainer-lock.json`, so `renovate.json` disables its `devcontainer` manager and leaves that ecosystem to Dependabot; without the Dependabot file, nothing would update the Features. When the user named a shared Renovate preset, extend it in `renovate.json` instead of `config:recommended`, and keep only the settings the preset does not already provide.

Also create empty `src/` and `test/` directories only when the user will add a Feature right away; Git does not track empty directories.

For each destination, decide:

- **Create** when neither the file nor a workflow with the same role exists.
- **Update** when a file with the same role exists. Keep its file name (for example an existing `validate.yml`). Merge the template's substance into it rather than replacing it: preserve jobs, steps, Features, and settings the template does not have, and explain each change. The substance to carry over is:
  - Test workflow: one `test-<id>` job per Feature, and `test-global` for `test/_global` scenarios, each calling the reusable `test-feature.yaml` with the Feature's ID and its architectures as a required input without a default; the `tests-passed` aggregate job, which needs every job and requires each to succeed. In `test-feature.yaml`: a `baseImage` matrix equal to the "CI base images" list in `${CLAUDE_PLUGIN_ROOT}/skills/feature-authoring/references/supported-platforms.md`; each architecture running on the runner that the "Architectures" table of that file names; inputs and matrix values passed through `env`.
  - Release workflow: publishing with `generate-docs`, followed by the documentation pull request step; runs only on the default branch, one at a time.
  - Validate workflow: `validate-only` and ShellCheck over `git ls-files '*.sh'`, with the `validation-passed` aggregate job.
  - Actions pinned to commit SHAs with the tag in a comment.
  - Dependency updates: GitHub Actions and the dev container's Features are both covered. With an existing Renovate configuration, check what it covers instead of rewriting it, and propose only the missing pieces.
- **Keep** when the existing file already satisfies the template.

The test workflow template has no Feature jobs. Keep the existing `test-<id>` jobs and `test-global` of the test workflow as they are, including their `architectures` and their entries in `needs`. This skill does not change the architectures an existing Feature is tested on, because that change also belongs in the Feature's `install.sh` and `NOTES.md`; the "Test jobs" section of the `feature-testing` skill covers it. For each Feature without a job, plan a `test-<id>` job in the form that the template's comment and that section show, plus `test-global` when `test/_global/scenarios.json` exists and the job does not, and list every job under `needs` of `tests-passed`. With no Feature yet, `tests-passed` has no `needs`; the `new-feature` skill adds them.

When an existing job leaves out an architecture of `${CLAUDE_PLUGIN_ROOT}/skills/feature-authoring/references/supported-platforms.md`, list the job and the architecture in the plan as information, without changing the job, so that the user can decide separately whether to extend the Feature.

Choose the architectures of each new job as follows. When the repository has `test/<id>/architectures` and `test/_global/architectures` files, which an earlier version of this plugin read, take each job's architectures from its file, one name per line, and plan to delete the files. Otherwise, propose them from the architectures in `${CLAUDE_PLUGIN_ROOT}/skills/feature-authoring/references/supported-platforms.md`, narrowed by what the Feature can install on each:

- When `install.sh` branches on `uname -m`, keep the supported architectures that the branches accept, and point out any that they reject, since the Feature is then not tested on it.
- When it does not branch, the Feature is architecture-independent as far as the script goes; start from all supported architectures.
- Either way, check that what the Feature installs exists for each proposed architecture, as the `new-feature` skill does: the upstream's release assets for a download, or the package's architectures for an apt repository, since a third-party repository may publish amd64 only. Leave out an architecture only when that check shows it has no build, and say which check that was.

For a new `test-global`, propose the architectures common to the Features its scenarios use. When the existing workflow did not run the Features on arm64, note that the first run there may still fail.

The test workflow and the reusable workflow must land in the same commit or pull request: the test workflow calls the reusable one.

`README.md` in an existing repository: add only what is missing, typically the Features table. Fill the table with one row per Feature, using `name` or `id` linked to `src/<id>` and `description` from its `devcontainer-feature.json`.

When `LICENSE` is missing, ask which license to use; the Features' `licenseURL` points to it.

Present the plan as a table (destination, action, summary of changes) and wait for the user's approval. Show the full diff for every updated file before writing it.

## 5. Apply

Write the approved files. Then check them:

- `jq empty` on every JSON file written.
- `actionlint` on the workflows, when it is installed.
- For existing Features, confirm that each `test/<id>/test.sh` exists, since each now has a `test-<id>` job, whose auto-generated test fails without it. List any that are missing and offer the `feature-testing` skill.
- Confirm the jobs of the test workflow, since CI cannot detect a missing job or a missing `needs` entry: every Feature under `src/` has exactly one job, `test-<id>`, calling `test-feature.yaml` with `feature: <id>`, so that the job name and `feature` agree; `test-global` exists when `test/_global/scenarios.json` does; no job names a Feature that is not under `src/`; and `tests-passed` needs every other job. `test-feature.yaml` itself checks the Feature ID and the architectures when it runs.
- When an existing Feature has the ID `global`, which is reserved because its job would collide with `test-global`, point it out and suggest renaming the Feature.

## 6. Hand over the manual steps

These need repository admin rights or are deliberately left to the user. Present them as a checklist, filling in the owner and repository:

1. **Branch ruleset** (Settings → Rules → Rulesets) for the default branch: require a pull request, and require the status checks `tests-passed` and `validation-passed`.
2. **Workflow permissions** (Settings → Actions → General): enable "Allow GitHub Actions to create and approve pull requests". The release workflow's documentation pull request fails without it.
3. **Claude Code approvals**: to have Claude Code ask before merging and releasing even in auto mode, add to the repository's `.claude/settings.json`:

   ```json
   {
     "permissions": {
       "ask": [
         "Bash(gh pr merge *)",
         "Bash(gh workflow run *)"
       ]
     }
   }
   ```

   The `release` skill detects these rules and then does not ask a second time in chat.
4. **Renovate** (only when Renovate was chosen): install the [Renovate GitHub App](https://github.com/apps/renovate) for the repository. Renovate opens pull requests for vulnerable dependencies from Dependabot alerts, so in Settings → Advanced Security enable Dependabot alerts and disable Dependabot security updates; otherwise both open a pull request for the same fix.
5. **Codespaces**: when creating a Codespace, approve the requested Actions write permission, which `gh workflow run` needs.
6. **After the first release**: ghcr.io creates packages private. Make each one public at `https://github.com/<users|orgs>/<owner>/packages/container/<repo>%2F<id>/settings` (with a custom `features-namespace`, the package name is the namespace without the owner, then `/<id>`). The `release` skill reminds about this too.

Finally, suggest committing the changes on a topic branch and opening a pull request, and offer the `new-feature` skill when `src/` is empty.
