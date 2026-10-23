# dev-container-feature-development

A Claude Code plugin for authoring, testing, and releasing [Dev Container Features](https://containers.dev/implementors/features/) in a repository laid out like [devcontainers/feature-starter](https://github.com/devcontainers/feature-starter) (`src/<id>/`, `test/<id>/`), published to ghcr.io with [devcontainers/action](https://github.com/devcontainers/action).

## Components

### Skills you invoke

| Skill | What it does |
|---|---|
| `/dev-container-feature-development:init-repository` | Creates or updates the CI and release workflows, Dependabot or Renovate configuration, dev container, README, and `.gitattributes`. Works on new and existing repositories, and lists the GitHub settings to change by hand. |
| `/dev-container-feature-development:new-feature [id] [what it installs]` | Researches the upstream, asks about the design, implements `install.sh` with its tests, runs them, and has the result reviewed. |
| `/dev-container-feature-development:run-feature-tests [id ...]` | Runs the tests on every supported base image and all scenarios, executes the manual negative tests, and analyzes failures. Uses CI results when Docker is unavailable. |
| `/dev-container-feature-development:release [id ...]` | Finds Features with unreleased changes, bumps versions through a pull request, runs the release workflow, and verifies the published tags. |

`new-feature`, `run-feature-tests`, and `init-repository` also run when you describe the task in your own words. `release` runs only when invoked explicitly.

### Skills loaded automatically

| Skill | When it applies |
|---|---|
| `feature-authoring` | Editing `src/<id>/`: the `devcontainer-feature.json` schema, `install.sh` conventions, where the repository defines its supported platforms, and dependency policy. |
| `feature-testing` | Editing `test/<id>/`: test kinds, scenarios, assertion scripts, and negative tests. |

### Agent

| Agent | What it does |
|---|---|
| `feature-reviewer` | Reviews a Feature and its tests against the authoring policy and reports numbered findings. Runs at the end of `new-feature`, when you ask for a review, and after the repository's base images or architectures change, across every Feature. |

## Conventions applied to Features

- Each repository decides the distributions and architectures it supports, as the `baseImage` matrix and the keys of `RUNNERS` in its reusable test workflow (usually `test-feature.yaml`). Features must work on every base image there, and CI tests them all. Only what CI tests counts as supported. Features support Debian and Ubuntu only, and every base image of the list is based on one of them.
- The base images are pinned to releases and include at least one `mcr.microsoft.com/devcontainers/base` image, which most dev containers are built on and which tests a non-root user. Each architecture is tested on a native runner of that architecture. A new repository starts from the initial values in the `init-repository` template; [supported-platforms.md](skills/feature-authoring/references/supported-platforms.md) explains how they are chosen. `init-repository` never changes these lists in an existing repository.
- Each Feature lists its architectures in its job in the CI workflow, and may leave one out only when the upstream publishes no build for it.
- Missing dependencies are installed with `apt-get`. Without `apt-get`, the Feature fails with a message saying that it supports Debian and Ubuntu only.
- Downloads are verified by checksum or signature.
- Dependencies, tested distributions, and tested architectures are documented in each Feature's `NOTES.md`.
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
