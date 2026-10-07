# install.sh patterns

Code patterns for `src/<id>/install.sh`. All snippets are POSIX `sh` and assume `set -eu` and a `FEATURE_ID` variable holding the Feature's ID.

## Header

```sh
#!/bin/sh
set -eu

FEATURE_ID='mytool'

# Option values reach install.sh as upper-cased environment variables.
VERSION="${VERSION:-latest}"
```

Keep the defaults identical to those in `devcontainer-feature.json`. The CLI always exports every option, so the fallback applies only when the user set an option to an empty value, and when the script is run directly (for example in negative tests).

## Root check

```sh
if [ "$(id -u)" -ne 0 ]; then
  echo "${FEATURE_ID}: install.sh must be run as root." >&2
  exit 1
fi
```

## Probing and installing dependencies

Probe by command, not by package, so that images which provide the tool some other way are left alone. Collect everything that is missing, then install once or fail once with the full list.

```sh
MISSING_PACKAGES=''
add_missing_package() {
  # $1: command to probe, $2: package(s) providing it
  if ! command -v "$1" >/dev/null 2>&1; then
    MISSING_PACKAGES="${MISSING_PACKAGES} $2"
  fi
}

add_missing_package 'curl' 'curl ca-certificates'
add_missing_package 'tar' 'tar'
add_missing_package 'gzip' 'gzip'

# curl can be present without a CA bundle when ca-certificates was skipped by
# --no-install-recommends; HTTPS then fails with an error that looks like a missing release.
if command -v 'curl' >/dev/null 2>&1 && [ ! -e '/etc/ssl/certs/ca-certificates.crt' ]; then
  if command -v 'apt-get' >/dev/null 2>&1; then
    MISSING_PACKAGES="${MISSING_PACKAGES} ca-certificates"
  else
    # Not fatal: an image without apt-get may keep its trust store elsewhere.
    echo "${FEATURE_ID}: no CA bundle at /etc/ssl/certs/ca-certificates.crt; a certificate error below would be why." >&2
  fi
fi

if [ -n "${MISSING_PACKAGES}" ]; then
  if ! command -v 'apt-get' >/dev/null 2>&1; then
    echo "${FEATURE_ID}: the following are required but missing, and apt-get is unavailable to install them:${MISSING_PACKAGES}" >&2
    echo "${FEATURE_ID}: install them in your base image, or use a Debian/Ubuntu-based image." >&2
    exit 1
  fi
  apt-get update -y
  # Intentionally unquoted: MISSING_PACKAGES is a space-separated package list.
  # shellcheck disable=SC2086
  DEBIAN_FRONTEND='noninteractive' apt-get install -y --no-install-recommends ${MISSING_PACKAGES}
  rm -rf /var/lib/apt/lists/*
fi
```

Remove `/var/lib/apt/lists/*` before the script ends whenever it ran `apt-get update`, whatever the update was for. An update that installs nothing, such as one that only confirms that rewritten apt sources are reachable, leaves the package lists in the image layer all the same, and Features that run later do their own `apt-get update` anyway.

Packages needed only during installation may be purged afterward, but only when this script installed them. Never remove something the image already had.

## Architecture

```sh
case "$(uname -m)" in
  x86_64 | amd64) ARCH='amd64' ;;
  aarch64 | arm64) ARCH='arm64' ;;
  *)
    echo "${FEATURE_ID}: unsupported architecture '$(uname -m)'." >&2
    exit 1
    ;;
esac
```

Map to whatever naming the upstream release uses. The branches that set `ARCH` must cover exactly the architectures in the Feature's test job (`architectures` of `test-<id>` in the test workflow): accepting any other architecture would install something CI never tests. When the upstream publishes no build for a supported architecture, that architecture is left out of the test job; give it its own branch that fails with a message saying so, rather than letting it reach the generic one:

```sh
  aarch64 | arm64)
    echo "${FEATURE_ID}: mytool publishes no build for arm64." >&2
    exit 1
    ;;
```

List the tested architectures in `NOTES.md`.

## Features for one distribution

A Feature that only has meaning on one distribution (see "Features for one distribution" in the skill) does nothing by default and checks the distribution only once an option asks for the work:

```sh
if [ -z "${PPA}" ]; then
  echo "${FEATURE_ID}: 'ppa' is empty; nothing to add."
  exit 0
fi

# os-release(5) allows quoted values, so ID="ubuntu" is as valid as ID=ubuntu. Sourcing the file in
# a subshell parses it the way the format prescribes and keeps its variables out of this script.
# shellcheck source=/dev/null
if [ ! -r '/etc/os-release' ] || ! (. '/etc/os-release' && [ "${ID:-}" = 'ubuntu' ]); then
  echo "${FEATURE_ID}: this Feature only supports Ubuntu-based images (ID=ubuntu in /etc/os-release)." >&2
  exit 1
fi
```

Validate every option before the first of these exits, the `exit 0` for the empty default included (see "Validating options"). An invalid value is an error on every distribution, also when the Feature goes on to do nothing.

On a supported architecture where there is nothing to act on, warn and change nothing rather than fail. A Feature that replaces the default host in apt sources meets this on Ubuntu's arm64 images, which name another host:

```sh
if [ "${CHANGED}" -eq 0 ]; then
  echo "${FEATURE_ID}: no apt source for the default host found; '${MIRROR}' is NOT in effect." >&2
  exit 0
fi
```

This is the same path as an edit in place that does not find its input (see "Idempotency"). It is not for a missing upstream build, which fails as shown under "Architecture".

## Resolving "latest"

First record whether the user named a version, before `latest` is resolved: only a version the user named is a promise the installed binary can be held to (see "Checking the installed version"). Both lookups below assume this block.

```sh
VERSION_PINNED='1'
if [ "${VERSION}" = 'latest' ]; then
  VERSION_PINNED=''
fi
```

Fetch into a variable first and parse second. Without `pipefail`, `curl ... | sed ...` hides a network failure as an empty result.

```sh
if [ "${VERSION}" = 'latest' ]; then
  if ! RESPONSE="$(curl -fsSL --retry 3 'https://api.github.com/repos/<owner>/<repo>/releases/latest')"; then
    echo "${FEATURE_ID}: could not query the latest release (see curl's message above)." >&2
    echo "${FEATURE_ID}: set the 'version' option to an exact version to skip this lookup." >&2
    exit 1
  fi
  # head -n 1 guards against a multi-line match putting a newline into VERSION.
  VERSION="$(printf '%s\n' "${RESPONSE}" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
  if [ -z "${VERSION}" ]; then
    echo "${FEATURE_ID}: no tag_name in the latest-release response." >&2
    exit 1
  fi
fi
VERSION="${VERSION#v}"
```

The unauthenticated GitHub API is rate-limited per IP (60 requests/hour), which shared CI runners hit. Mention in `NOTES.md` that pinning a version avoids the lookup. When a redirect-based endpoint exists (`https://github.com/<owner>/<repo>/releases/latest` redirects to the tag), prefer it over the API:

```sh
if ! LATEST_URL="$(curl -fsSLI --retry 3 -o /dev/null -w '%{url_effective}' "https://github.com/<owner>/<repo>/releases/latest")"; then
  echo "${FEATURE_ID}: could not resolve the latest release (see curl's message above)." >&2
  exit 1
fi
# A repository without a non-prerelease release redirects to /releases instead of /releases/tag/<tag>;
# taking the last path segment would then yield the version "releases".
case "${LATEST_URL}" in
  */releases/tag/*) VERSION="${LATEST_URL##*/}" ;;
  *)
    echo "${FEATURE_ID}: <owner>/<repo> has no published release to resolve 'latest' to." >&2
    exit 1
    ;;
esac
```

## Validating options

Validate every option, boolean and `enum` options included. The CLI does not enforce `type` or `enum` at build time (see `feature-json.md`), so a typo in the user's `devcontainer.json` reaches the script as written, and the script is the only place that can reject it. Fail on an invalid value; never treat it as false or as the default. The one exception is an empty value, which the `${VAR:-default}` read in the header replaces with the default.

A boolean accepts `true` and `false` only. Without the check, a test such as `[ "${INSTALLCOMPLETIONS}" = 'true' ]` silently treats `True` as false:

```sh
case "${INSTALLCOMPLETIONS}" in
  true | false) ;;
  *)
    echo "${FEATURE_ID}: invalid installCompletions '${INSTALLCOMPLETIONS}'; expected true or false." >&2
    exit 1
    ;;
esac
```

Declare a closed set of values as `enum` in `devcontainer-feature.json`, so that editors offer and check them, and accept exactly the same values in the script:

```sh
case "${CHANNEL}" in
  stable | beta) ;;
  *)
    echo "${FEATURE_ID}: invalid channel '${CHANNEL}'; expected stable or beta." >&2
    exit 1
    ;;
esac
```

Validate a free-form option before it reaches a URL, a path, or a command. Check the resolved value, not only the user's input, since a `latest` lookup can return something unexpected too. Allow only the characters the value can legitimately contain:

```sh
case "${VERSION}" in
  '' | *[!0-9A-Za-z.+-]*)
    echo "${FEATURE_ID}: invalid version '${VERSION}'; expected something like 1.2.3." >&2
    exit 1
    ;;
esac
```

Rejecting `/` also rejects `..` path segments, so the value cannot escape a temporary directory or change the path of a URL.

## Temporary directory

```sh
TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
# The signal traps exit rather than clean up directly: exiting runs the EXIT trap, so cleanup
# happens exactly once, and the script does not continue with its temp directory gone.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
```

## Verified download

Verify against a checksum file or signature that the upstream publishes separately from the artifact. Prefer signatures, and pin the signing key's fingerprint in the script: a key downloaded next to a tampered artifact would verify it. A checksum file from the same release detects corrupted or truncated downloads but not a compromised release; when that is all the upstream offers, use it and state the limitation in `NOTES.md`.

```sh
ARCHIVE="mytool_${VERSION}_linux_${ARCH}.tar.gz"
BASE_URL="https://github.com/<owner>/<repo>/releases/download/v${VERSION}"

if ! curl -fsSL --retry 3 -o "${TMP_DIR}/${ARCHIVE}" "${BASE_URL}/${ARCHIVE}"; then
  echo "${FEATURE_ID}: failed to download ${ARCHIVE} (see curl's message above)." >&2
  echo "${FEATURE_ID}: if that was a 404, version '${VERSION}' may not exist for ${ARCH}." >&2
  exit 1
fi
if ! curl -fsSL --retry 3 -o "${TMP_DIR}/checksums.txt" "${BASE_URL}/checksums.txt"; then
  echo "${FEATURE_ID}: failed to download checksums.txt (see curl's message above)." >&2
  exit 1
fi

# Compare the whole file-name field: a substring match would also pick up entries such as
# "<archive>.sig", and sha256sum -c would then fail on files that were never downloaded. The "*"
# prefix is how sha256sum marks binary-mode entries.
awk -v f="${ARCHIVE}" '$2 == f || $2 == "*" f' "${TMP_DIR}/checksums.txt" > "${TMP_DIR}/expected.txt"
if [ ! -s "${TMP_DIR}/expected.txt" ]; then
  echo "${FEATURE_ID}: ${ARCHIVE} is not listed in checksums.txt." >&2
  exit 1
fi
if ! (cd "${TMP_DIR}" && sha256sum -c --status expected.txt); then
  echo "${FEATURE_ID}: checksum mismatch for ${ARCHIVE}." >&2
  exit 1
fi
```

`sha256sum` is part of coreutils on Debian and Ubuntu; add it to the dependency probe when supporting other distributions.

## Checking the installed version

Run the binary from the temporary directory before installing it. This fails the build when the binary cannot run on this image, and keeps a wrong binary out of the install path. Assign to a variable: inside `echo "$(...)"` the substitution's exit status is lost.

```sh
INSTALLED_VERSION="$("${TMP_DIR}/mytool" --version)"
if [ -n "${VERSION_PINNED}" ]; then
  case "${INSTALLED_VERSION}" in
    *"${VERSION}"*) ;;
    *)
      echo "${FEATURE_ID}: downloaded binary reports '${INSTALLED_VERSION}', not the requested ${VERSION}." >&2
      exit 1
      ;;
  esac
fi
install -o 'root' -g 'root' -m 755 "${TMP_DIR}/mytool" '/usr/local/bin/mytool'
```

## Per-user setup

`_REMOTE_USER` is the user the dev container will be used as; `_CONTAINER_USER` is the container's user. Their homes are in `_REMOTE_USER_HOME` and `_CONTAINER_USER_HOME`. They can be empty when the script is run by hand, so fall back explicitly.

```sh
TARGET_USER="${_REMOTE_USER:-root}"

# getent runs on its own rather than in a pipeline, so that an unknown user is an error rather than
# an empty home directory that would send the files below to /.config.
if ! PASSWD_ENTRY="$(getent passwd "${TARGET_USER}")"; then
  echo "${FEATURE_ID}: user '${TARGET_USER}' does not exist." >&2
  exit 1
fi
TARGET_HOME="${_REMOTE_USER_HOME:-$(printf '%s\n' "${PASSWD_ENTRY}" | cut -d: -f6)}"
if [ -z "${TARGET_HOME}" ] || [ ! -d "${TARGET_HOME}" ]; then
  echo "${FEATURE_ID}: home directory of '${TARGET_USER}' not found." >&2
  exit 1
fi
TARGET_GROUP="$(id -gn "${TARGET_USER}")"

# Each missing level is created owned by the user. mkdir -p would leave ~/.config owned by root when
# it did not exist yet, and the user could then create nothing else in it.
for dir in "${TARGET_HOME}/.config" "${TARGET_HOME}/.config/mytool"; do
  if [ ! -d "${dir}" ]; then
    install -d -o "${TARGET_USER}" -g "${TARGET_GROUP}" -m 755 "${dir}"
  fi
done
install -o "${TARGET_USER}" -g "${TARGET_GROUP}" -m 644 "${SCRIPT_DIR}/config.toml" "${TARGET_HOME}/.config/mytool/config.toml"
```

`SCRIPT_DIR` is the Feature directory; see "Files next to install.sh" below.

Run commands as the user with `su -s /bin/sh "${TARGET_USER}" -c '...'` rather than `sudo`, which may not be installed. `-s` matters for system users whose login shell is `nologin`. Only `chown` what this script created; a recursive `chown` on the whole home can take ownership away from files that other Features placed there on purpose.

## Files next to install.sh

Resolve them from the script's directory, not the current directory:

```sh
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
install -m 755 "${SCRIPT_DIR}/entrypoint.sh" '/usr/local/share/mytool/entrypoint.sh'
```

A script referenced by `entrypoint` or a lifecycle hook in `devcontainer-feature.json` must be copied to a fixed location like this at build time; the Feature directory itself is not present in the running container.

## Idempotency

A Feature is installed twice on one image more often than it seems:

- The base image was prebuilt with the Feature, and the user lists it again. The CLI runs it again even when the options are the same, and the user's entry runs last.
- Another Feature pulls it in through `dependsOn`, and the user lists it too with other options or another version. Both run. Neither the Feature nor the user controls which runs last: the user's entry can run first. With the same version and options, the CLI runs it once.
- The duplicate test.

A second run must not fail, and must not damage what the first left. Beyond that, what it yields depends on what the script touches, and one script can mix the cases:

| The script | A second run | How |
|---|---|---|
| Creates settings or files | The later run wins. | Write whole files, `install` or `cp` over existing ones, `ln -sfn`. Prefer a dedicated file under `/etc/profile.d/` written in full over a line appended to a profile. |
| Adds to a list (packages, versions side by side) | Both results are present. The same options twice add nothing twice. | Check before appending: `grep -qxF "$LINE" "$FILE" \|\| printf '%s\n' "$LINE" >> "$FILE"`. |
| Creates what the options cannot reproduce (generated keys or IDs, initialized data) | What exists is kept. | Test for it first and skip. |
| Edits configuration in place | Warns and changes nothing when the input it expects is not there. | See below. |

State in `NOTES.md` which of these applies. The one thing never to do is to leave a requested option without effect and say nothing. Keeping a generated key is not that: the key does not come from an option.

Between two versions of the Feature, which also happens through `dependsOn`, only the first requirement holds: do not fail, and do not damage the earlier result.

### Edits in place

An edit in place looks for something to replace, and a second run may not find it, because the first run replaced it. A base image whose author already configured the same thing by other means looks exactly the same to the script. Treat both alike:

- When the requested value is already in place, succeed without a warning. The option took effect.
- Otherwise, when the expected input is missing, change nothing and print a warning that says what was not found and that nothing was changed. Do not fail: the image may be set up that way on purpose.
- Never apply part of an edit. Decide what to change before changing anything.
- Describe this in `NOTES.md` Limitations.

Do not record earlier runs (a marker file, a backup of the original) in order to undo them. That adds a state that can disagree with the real configuration, for a case in which the user gets a warning either way.

### Testing

Write `test/<id>/duplicate.sh` to have CI install the Feature twice; see the `feature-testing` skill.

## Environment for later shells

- Variables the tool always needs: use `containerEnv` in `devcontainer-feature.json`. It is set as `ENV` in the image, before `install.sh` runs, and applies to every process.
- `PATH` additions: `"containerEnv": { "PATH": "/usr/local/mytool/bin:${PATH}" }`.
- Settings that only login shells need: write a file to `/etc/profile.d/<id>.sh`.
