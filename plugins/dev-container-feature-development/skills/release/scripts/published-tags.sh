#!/usr/bin/env bash
# Lists the tags of a Feature published to ghcr.io, anonymously.
#
# Usage: published-tags.sh [--max-semver] <owner>/<repo>/<feature-id>
#
#   --max-semver  Print only the highest X.Y.Z tag (nothing when there is none).
#
# Exit status:
#   0  Tags were listed.
#   2  The package is private or has never been published; the registry answered DENIED.
#   1  Anything else: missing commands, network failure, or a response that could not be understood.
#
# Public packages can be read without credentials, so neither the devcontainer CLI nor a token with
# the read:packages scope is needed.
set -euo pipefail

for command in curl jq; do
  if ! command -v "${command}" >/dev/null 2>&1; then
    echo "published-tags.sh: '${command}' is required but not installed." >&2
    exit 1
  fi
done

max_semver=''
if [ "${1:-}" = '--max-semver' ]; then
  max_semver='1'
  shift
fi

if [ "$#" -ne 1 ] || [ -z "$1" ]; then
  echo 'usage: published-tags.sh [--max-semver] <owner>/<repo>/<feature-id>' >&2
  exit 1
fi

# OCI repository names are lowercase; devcontainers/action lowercases the namespace when publishing.
repo="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')"

# The name goes into a query string and a URL path below, so anything outside the OCI name grammar
# would change the request rather than name a repository.
case "${repo}" in
  */*) ;;
  *)
    echo "published-tags.sh: '$1' is not of the form <owner>/<repo>/<feature-id>." >&2
    exit 1
    ;;
esac
case "${repo}" in
  /* | */ | *//* | *[!a-z0-9._/-]*)
    echo "published-tags.sh: '$1' contains characters that are not valid in a registry name." >&2
    exit 1
    ;;
esac

# Responses are captured in variables rather than piped into jq: the exit status of a pipeline is
# that of jq, and jq succeeds on empty input, so a network failure would read as "no tags".
# curl runs without -f so that the body of a 403 DENIED stays readable; transfer errors still fail.
if ! token_response="$(curl -sS --retry 3 --max-time 30 "https://ghcr.io/token?service=ghcr.io&scope=repository:${repo}:pull")"; then
  echo 'published-tags.sh: could not reach the ghcr.io token endpoint.' >&2
  exit 1
fi
if ! printf '%s' "${token_response}" | jq -e . >/dev/null 2>&1; then
  printf 'published-tags.sh: the token endpoint did not return JSON: %s\n' "${token_response}" >&2
  exit 1
fi

token="$(printf '%s' "${token_response}" | jq -r '.token // empty')"
if [ -z "${token}" ]; then
  # Only DENIED means private or unpublished. An empty token also comes with rate limiting
  # (TOOMANYREQUESTS) and server errors, which must not be mistaken for "not published yet".
  if printf '%s' "${token_response}" | jq -e 'any(.errors[]?; .code == "DENIED")' >/dev/null; then
    printf 'published-tags.sh: private or not published: %s\n' "${token_response}" >&2
    exit 2
  fi
  printf 'published-tags.sh: unexpected response from the token endpoint: %s\n' "${token_response}" >&2
  exit 1
fi

if ! tags_response="$(curl -sS --retry 3 --max-time 30 -H "Authorization: Bearer ${token}" "https://ghcr.io/v2/${repo}/tags/list?n=10000")"; then
  echo 'published-tags.sh: could not reach the ghcr.io tags endpoint.' >&2
  exit 1
fi
if ! printf '%s' "${tags_response}" | jq -e '.tags | type == "array"' >/dev/null 2>&1; then
  printf 'published-tags.sh: could not read the tag list: %s\n' "${tags_response}" >&2
  exit 1
fi

if [ -n "${max_semver}" ]; then
  # Compared as arrays of numbers so that 0.10.0 sorts above 0.9.0. sort -V is avoided because it is
  # a GNU extension.
  printf '%s' "${tags_response}" |
    jq -r '[.tags[] | select(test("^[0-9]+[.][0-9]+[.][0-9]+$"))] | max_by(split(".") | map(tonumber)) // empty'
else
  printf '%s' "${tags_response}" | jq -r '.tags[]'
fi
