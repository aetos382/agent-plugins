#!/bin/sh
# Example install.sh for a Feature that installs a single binary from GitHub Releases.
# Replace every "mytool" and "example-org/mytool" with the real names; the structure is what matters.
set -eu

FEATURE_ID='mytool'
INSTALL_PATH='/usr/local/bin/mytool'
REPOSITORY='example-org/mytool'

# Option values reach install.sh as upper-cased environment variables.
MYTOOL_VERSION="${VERSION:-latest}"

# Recorded before 'latest' is resolved: only a version the user named is a promise the installed
# binary can be held to.
VERSION_PINNED='1'
if [ "${MYTOOL_VERSION}" = 'latest' ]; then
  VERSION_PINNED=''
fi

if [ "$(id -u)" -ne 0 ]; then
  echo "${FEATURE_ID}: install.sh must be run as root." >&2
  exit 1
fi

# uname -m rather than dpkg --print-architecture, so that detection does not depend on Debian tooling.
case "$(uname -m)" in
  x86_64 | amd64) ARCH='amd64' ;;
  aarch64 | arm64) ARCH='arm64' ;;
  *)
    echo "${FEATURE_ID}: unsupported architecture '$(uname -m)'." >&2
    exit 1
    ;;
esac

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
add_missing_package 'sha256sum' 'coreutils'

# An image can ship curl without ca-certificates when it was skipped by --no-install-recommends;
# HTTPS then fails with a certificate error that reads like a missing release.
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

if [ "${MYTOOL_VERSION}" = 'latest' ]; then
  # The releases/latest page redirects to the newest tag. Following the redirect avoids the
  # unauthenticated API's rate limit, which shared CI runners exhaust quickly.
  if ! LATEST_URL="$(curl -fsSLI --retry 3 -o /dev/null -w '%{url_effective}' "https://github.com/${REPOSITORY}/releases/latest")"; then
    echo "${FEATURE_ID}: could not resolve the latest release of ${REPOSITORY} (see curl's message above)." >&2
    echo "${FEATURE_ID}: set the 'version' option to an exact version to skip this lookup." >&2
    exit 1
  fi
  # A repository without a non-prerelease release redirects to /releases instead of
  # /releases/tag/<tag>; the last path segment would then be taken for the version "releases".
  case "${LATEST_URL}" in
    */releases/tag/*) MYTOOL_VERSION="${LATEST_URL##*/}" ;;
    *)
      echo "${FEATURE_ID}: ${REPOSITORY} has no published release to resolve 'latest' to." >&2
      exit 1
      ;;
  esac
fi
MYTOOL_VERSION="${MYTOOL_VERSION#v}"

# The version ends up in a URL and in a file path below. Checked after resolving 'latest' so that an
# unexpected redirect target is caught too; rejecting '/' also rules out '..' path segments.
case "${MYTOOL_VERSION}" in
  '' | *[!0-9A-Za-z.+-]*)
    echo "${FEATURE_ID}: invalid version '${MYTOOL_VERSION}'; expected something like 1.2.3." >&2
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TMP_DIR}"
}
# The signal traps exit rather than clean up directly: exiting runs the EXIT trap, so cleanup
# happens exactly once and the script does not carry on with its temp directory gone.
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

ARCHIVE="mytool_${MYTOOL_VERSION}_linux_${ARCH}.tar.gz"
BASE_URL="https://github.com/${REPOSITORY}/releases/download/v${MYTOOL_VERSION}"

if ! curl -fsSL --retry 3 -o "${TMP_DIR}/${ARCHIVE}" "${BASE_URL}/${ARCHIVE}"; then
  echo "${FEATURE_ID}: failed to download ${ARCHIVE} (see curl's message above)." >&2
  echo "${FEATURE_ID}: if that was a 404, version '${MYTOOL_VERSION}' may not be published for ${ARCH}." >&2
  exit 1
fi
if ! curl -fsSL --retry 3 -o "${TMP_DIR}/checksums.txt" "${BASE_URL}/checksums.txt"; then
  echo "${FEATURE_ID}: failed to download checksums.txt (see curl's message above)." >&2
  exit 1
fi

# checksums.txt comes from the same release as the archive, so this detects corrupted downloads, not
# a compromised release; NOTES.md says so. The whole file-name field is compared: a substring match
# would also pick up entries such as "<archive>.sig", and sha256sum -c would then fail on files that
# were never downloaded. The "*" prefix is how sha256sum marks binary-mode entries.
awk -v f="${ARCHIVE}" '$2 == f || $2 == "*" f' "${TMP_DIR}/checksums.txt" > "${TMP_DIR}/expected.txt"
if [ ! -s "${TMP_DIR}/expected.txt" ]; then
  echo "${FEATURE_ID}: ${ARCHIVE} is not listed in checksums.txt." >&2
  exit 1
fi
if ! (cd "${TMP_DIR}" && sha256sum -c --status expected.txt); then
  echo "${FEATURE_ID}: checksum mismatch for ${ARCHIVE}." >&2
  exit 1
fi

tar -xzf "${TMP_DIR}/${ARCHIVE}" -C "${TMP_DIR}" 'mytool'

# Run it before installing: this fails the build when the binary cannot run on this image, and keeps
# a binary that fails the version check out of INSTALL_PATH. The assignment matters: inside
# 'echo "$(...)"' the substitution's exit status is discarded.
INSTALLED_VERSION="$("${TMP_DIR}/mytool" --version)"

if [ -n "${VERSION_PINNED}" ]; then
  case "${INSTALLED_VERSION}" in
    *"${MYTOOL_VERSION}"*) ;;
    *)
      echo "${FEATURE_ID}: ${ARCHIVE} reports '${INSTALLED_VERSION}', not the requested ${MYTOOL_VERSION}." >&2
      exit 1
      ;;
  esac
fi

install -o 'root' -g 'root' -m 755 "${TMP_DIR}/mytool" "${INSTALL_PATH}"

echo "${FEATURE_ID}: installed mytool ${MYTOOL_VERSION} at ${INSTALL_PATH}"
