---
name: feature-testing
description: This skill should be used when the user asks to "write a test for a feature", "add a scenario", "edit scenarios.json", "write test.sh", "add a negative test", "write duplicate.sh", "add an idempotency test", or otherwise works on files under `test/<feature>/` in a Dev Container Features repository. Explains how `devcontainer features test` discovers and runs tests and how to cover failure paths it cannot express.
---

# Testing Dev Container Features

Tests live in `test/<id>/`, mirroring `src/<id>/`. They run with `devcontainer features test`, which builds a container with the Feature installed and then executes an assertion script inside it. A test passes when the build succeeds **and** the script exits 0. To run the tests, use the `run-feature-tests` skill; this skill covers writing them.

## Test kinds

| File | Kind | What the CLI does |
|---|---|---|
| `test/<id>/test.sh` | Auto-generated | Builds `--base-image` (default `ubuntu:focal`) with the Feature at default options, runs `test.sh`. CI runs this for every supported base image. |
| `test/<id>/scenarios.json` + `test/<id>/<name>.sh` | Scenario | Each top-level key is a scenario name whose value is a `devcontainer.json`. Builds it, runs `<name>.sh`. |
| `test/<id>/<name>/` | Scenario files | Copied into the scenario's `.devcontainer/`, e.g. a `Dockerfile` referenced by `"build": { "dockerfile": "Dockerfile" }`. |
| `test/<id>/duplicate.sh` | Duplicate | Installs the Feature twice, once with default options and once with other values; option values are exposed as `<OPTION>` and `<OPTION>__DEFAULT`. |
| `test/_global/scenarios.json` | Global scenario | Scenarios spanning several Features. |
| `test/<id>/negative-tests.md` | Manual | Failure cases the CLI cannot express, run by `docker run`. See below. |

`test.sh` is mandatory for every Feature: the auto-generated run fails without it.

## What to cover

1. **Default options** (`test.sh`): the tool is on `PATH`, runs, is at the documented path with the documented owner and mode, and nothing is left behind that the Feature promises to clean up.
2. **Each option** (scenarios): one scenario per non-default value that changes behavior. Assert the effect of the option, not only that the build succeeded.
3. **Non-root remote user** (scenario): use one of the non-root test images from `${CLAUDE_PLUGIN_ROOT}/skills/feature-authoring/references/supported-distributions.md` (`mcr.microsoft.com/devcontainers/base` images) with `"remoteUser": "vscode"` whenever the Feature touches a user's home, a user-owned file, or `PATH`. The check runs as that user.
4. **Bare image** (scenario, when the Feature installs dependencies): an official Debian or Ubuntu image with `"remoteUser": "root"`, where tools like `curl` are missing, to exercise dependency installation.
5. **Idempotency** (`duplicate.sh`): when the Feature has options that change what is installed.
6. **Failure paths** (`negative-tests.md`): invalid option values, verification failures, missing dependencies without `apt-get`.

Scenarios pin their own `image`, so they run once rather than once per base image. Spread scenarios across the supported releases listed in `supported-distributions.md` instead of putting all of them on one image, and use only images listed there. Release numbers in the examples of this skill are illustrations; take the current ones from that file.

## Writing assertion scripts

```bash
#!/bin/bash
# Ensures that <what this scenario guarantees, in one or two sentences>.
set -e

# shellcheck source=/dev/null
source 'dev-container-features-test-lib'

check 'mytool is on PATH' bash -c 'command -v mytool'
check 'mytool runs' mytool --version

reportResults
```

- Begin every script with a comment stating what the test guarantees and why it matters, not a restatement of the checks.
- `dev-container-features-test-lib` is injected by the CLI. Keep the `# shellcheck source=/dev/null` directive on the `source` line itself.
- `check <label> <command> [args...]` runs the command and records a failure when it exits non-zero. `reportResults` exits 1 when any check failed. Always call it last.
- With `set -e`, the first failing `check` ends the script. Keep `set -e` so that unexpected errors in setup code still fail the test.
- When a check needs shell syntax (pipes, `$(...)`, `&&`), wrap it in `bash -c '...'` with **single quotes**, so that expansion happens inside the container at check time. Add `# shellcheck disable=SC2016` once at the top of the file with a comment explaining why.
- Inside `bash -c` pipelines, add `set -o pipefail;` so that a failure on the left side is not masked.
- A negated check such as `! grep -q foo file` also passes when `grep` fails for another reason, such as a missing `file`. Guard every precondition the negation would otherwise hide: `[ -f file ] && ! grep -q foo file`, or `command -v dpkg >/dev/null && ! dpkg -S /usr/local/bin/mytool`.
- Test scripts run as the scenario's remote user. Checks that only make sense as root must be conditional on `id -u`.
- Scenario names become file names: use `snake_case` and make them describe the configuration (`pinned_version`, `non_root_user`).

Complete examples are in `examples/`.

## scenarios.json

```json
{
  "pinned_version": {
    "image": "ubuntu:24.04",
    "remoteUser": "root",
    "features": {
      "mytool": { "version": "1.2.3" }
    }
  }
}
```

- Reference the Feature under test by its bare ID (`"mytool"`), not by a registry path.
- Other Features from the same repository can be referenced by bare ID too; published Features by full reference.
- Pin image tags to a release (`debian:13`, not `debian:latest`) so that a new release does not break unrelated pull requests.

## Negative tests

The CLI treats a failed build as a failed test, so a case that is supposed to fail cannot be a scenario. Document such cases in `test/<id>/negative-tests.md`. The `run-feature-tests` skill executes them, so follow this format exactly (see `examples/negative-tests.md`):

- An introduction naming which `install.sh` logic the cases cover and when to rerun them.
- A `## Setup` section with one interactive `docker run --rm -it ... <image> sh` command that mounts `src/<id>` read-only at `/mnt/f`. Every case starts from a fresh container created by this command, so a case may modify the container (for example disable `apt-get`) without affecting the next one.
- One `## Case <letter>: <condition>` section per case containing:
  - A `sh` code block with the commands to run inside the Setup container: option variables set explicitly, then `sh /mnt/f/install.sh; echo "exit status: $?"`.
  - A line `Expected: exit status <n>` followed by the expected side effects, for example "`/usr/local/bin/mytool` does not exist".
  - Optionally, a plain code block with expected stderr lines.
- A case that cannot run inside the Setup container (for example one that needs a different `--platform`) starts its section with the sentence `Run this case from the host.` and its code block is a complete `docker run` command. Such a command may differ from the Setup command only in `docker run` flags and the command run inside the container.

Expected stderr lines are matched as follows: each listed line must be contained in a line of stderr, in the listed order; other lines (apt output, curl's own messages) may appear in between, and a stderr line may continue past the listed text (for example a list of missing packages that depends on the image). The exit status must match exactly.

Keep each command self-contained. Negative tests may assume an x86_64 host: a case whose expected output or method depends on the host architecture starts with the sentence `Requires an x86_64 host.` To exercise an unsupported-architecture path without emulation, run the script under `linux32`, which makes `uname -m` report `i686`. State any other environment requirement in the case too, so that it can be reported as not run when unavailable.

Whenever install.sh contains a failure path that no test covers, add a comment near it pointing at `negative-tests.md`.

## Additional resources

- **`references/test-cli.md`** — `devcontainer features test` flags, how scenario directories are assembled, `checkMultiple`, duplicate-test variables, and debugging a failed build.
- **`examples/test.sh`** — default-options test.
- **`examples/scenarios.json`** and **`examples/non_root_user.sh`** — a scenario with a non-root remote user.
- **`examples/duplicate.sh`** — idempotency test.
- **`examples/negative-tests.md`** — manual failure cases in the format `run-feature-tests` executes.
