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
   | Test | runs `devcontainer features test` |
   | Release | uses `devcontainers/action` with `publish-features: "true"` |
   | Validate | uses `devcontainers/action` with `validate-only: "true"`, or runs `shellcheck` |

   Also check `src/*/devcontainer-feature.json`, `test/*/`, `.github/dependabot.yml`, `.devcontainer/devcontainer.json`, `README.md`, `LICENSE`, and `.gitattributes`.

## 2. Resolve template values

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

## 3. Plan

Map each template to its destination:

| Template | Destination |
|---|---|
| `assets/workflows/test.yaml` | `.github/workflows/test.yaml` |
| `assets/workflows/release.yaml` | `.github/workflows/release.yaml` |
| `assets/workflows/validate.yaml` | `.github/workflows/validate.yaml` |
| `assets/dependabot.yml` | `.github/dependabot.yml` |
| `assets/devcontainer/devcontainer.json` | `.devcontainer/devcontainer.json` |
| `assets/README.md` | `README.md` |
| `assets/gitattributes` | `.gitattributes` |

Also create empty `src/` and `test/` directories only when the user will add a Feature right away; Git does not track empty directories.

For each destination, decide:

- **Create** when neither the file nor a workflow with the same role exists.
- **Update** when a file with the same role exists. Keep its file name (for example an existing `validate.yml`). Merge the template's substance into it rather than replacing it: preserve jobs, steps, Features, and settings the template does not have, and explain each change. The substance to carry over is:
  - Test workflow: Features discovered from `src/` instead of a hard-coded list; a `baseImage` matrix equal to the "CI base images" list in `${CLAUDE_PLUGIN_ROOT}/skills/feature-authoring/references/supported-distributions.md`; matrix values passed through `env`; a job for `test/_global` scenarios; the `tests-passed` aggregate job.
  - Release workflow: publishing with `generate-docs`, followed by the documentation pull request step; runs only on the default branch, one at a time.
  - Validate workflow: `validate-only` and ShellCheck over `git ls-files '*.sh'`, with the `validation-passed` aggregate job.
  - Actions pinned to commit SHAs with the tag in a comment.
- **Keep** when the existing file already satisfies the template.

`README.md` in an existing repository: add only what is missing, typically the Features table. Fill the table with one row per Feature, using `name` or `id` linked to `src/<id>` and `description` from its `devcontainer-feature.json`.

When `LICENSE` is missing, ask which license to use; the Features' `licenseURL` points to it.

Present the plan as a table (destination, action, summary of changes) and wait for the user's approval. Show the full diff for every updated file before writing it.

## 4. Apply

Write the approved files. Then check them:

- `jq empty` on every JSON file written.
- `actionlint` on the workflows, when it is installed.
- For existing Features, confirm that each `test/<id>/test.sh` exists, since the discovered matrix now tests every Feature under `src/`. List any that are missing and offer the `feature-testing` skill.

## 5. Hand over the manual steps

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
4. **Codespaces**: when creating a Codespace, approve the requested Actions write permission, which `gh workflow run` needs.
5. **After the first release**: ghcr.io creates packages private. Make each one public at `https://github.com/<users|orgs>/<owner>/packages/container/<repo>%2F<id>/settings` (with a custom `features-namespace`, the package name is the namespace without the owner, then `/<id>`). The `release` skill reminds about this too.

Finally, suggest committing the changes on a topic branch and opening a pull request, and offer the `new-feature` skill when `src/` is empty.
