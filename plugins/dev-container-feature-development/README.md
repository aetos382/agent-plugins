# dev-container-feature-development

A Claude Code plugin for authoring, testing, and releasing [Dev Container Features](https://containers.dev/implementors/features/) in a repository laid out like [devcontainers/feature-starter](https://github.com/devcontainers/feature-starter) (`src/<id>/`, `test/<id>/`), published to ghcr.io with [devcontainers/action](https://github.com/devcontainers/action).

## Components

### Skills you invoke

| Skill | What it does |
|---|---|
| `/dev-container-feature-development:init-repository` | Creates or updates the test, release, and validate workflows, Dependabot configuration, dev container, README, and `.gitattributes`. Works on new and existing repositories, and lists the GitHub settings to change by hand. |
| `/dev-container-feature-development:new-feature [id] [what it installs]` | Researches the upstream, asks about the design, implements `install.sh` with its tests, runs them, and has the result reviewed. |
| `/dev-container-feature-development:run-feature-tests [id ...]` | Runs the tests on every supported base image and all scenarios, executes the manual negative tests, and analyzes failures. Uses CI results when Docker is unavailable. |
| `/dev-container-feature-development:release [id ...]` | Finds Features with unreleased changes, bumps versions through a pull request, runs the release workflow, and verifies the published tags. |

`new-feature`, `run-feature-tests`, and `init-repository` also run when you describe the task in your own words. `release` runs only when invoked explicitly.

### Skills loaded automatically

| Skill | When it applies |
|---|---|
| `feature-authoring` | Editing `src/<id>/`: the `devcontainer-feature.json` schema, `install.sh` conventions, supported distributions, and dependency policy. |
| `feature-testing` | Editing `test/<id>/`: test kinds, scenarios, assertion scripts, and negative tests. |

### Agent

| Agent | What it does |
|---|---|
| `feature-reviewer` | Reviews a Feature and its tests against the authoring policy and reports numbered findings. Runs at the end of `new-feature`, or when you ask for a review. |

## Conventions applied to Features

- Features must work on Ubuntu 26.04, Ubuntu 24.04, Debian 13, and Debian 12 (the latest two Ubuntu LTS releases and Debian stable and oldstable), and CI tests them all, plus `mcr.microsoft.com/devcontainers/base:3-ubuntu26.04` and `mcr.microsoft.com/devcontainers/base:3-ubuntu24.04` for a non-root user. Other distributions are supported only when that costs no more than a package-manager branch.
- Missing dependencies are installed with `apt-get`. Without `apt-get`, the Feature fails with a message naming what is missing.
- Downloads are verified by checksum or signature.
- Dependencies and tested distributions are documented in each Feature's `NOTES.md`.
- Failure paths that `devcontainer features test` cannot express are documented in `test/<id>/negative-tests.md`, which `run-feature-tests` executes.

## Requirements

- The latest version of [Claude Code](https://claude.com/claude-code).
- `git`.
- The repository must be hosted on GitHub, and Features are published to ghcr.io.
- [GitHub CLI](https://cli.github.com/) (`gh`), signed in to an account with access to the repository. `release` and `init-repository` require it; `run-feature-tests` needs it to read CI results, and `new-feature` uses it to research GitHub-hosted upstreams.
- `curl` and `jq`, for `release` and `init-repository`. `feature-reviewer` also uses `jq` to check JSON files when it is installed.
- For running tests locally with `run-feature-tests`: Docker and the [Dev Container CLI](https://github.com/devcontainers/cli) (`npm install -g @devcontainers/cli`). Negative tests bind-mount the working directory, so the Docker daemon must be able to see it; with docker-outside-of-docker inside a dev container, they are reported as not run. Without Docker or the CLI, `run-feature-tests` reads the results of the CI workflow instead and cannot run negative tests.
- Optional: `shellcheck`, used by `new-feature` and `feature-reviewer`, and `actionlint`, used by `init-repository`, when installed.

## Installation

```
/plugin marketplace add aetos382/agent-plugins
/plugin install dev-container-feature-development@aetos382
```

## Typical flow

1. `/dev-container-feature-development:init-repository` in a new or existing repository, then apply the manual settings it lists.
2. `/dev-container-feature-development:new-feature` for each Feature.
3. Commit, open a pull request, and merge when CI passes.
4. `/dev-container-feature-development:release`.
