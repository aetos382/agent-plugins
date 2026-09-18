#!/usr/bin/env bash
# Checks the supported distributions of the dev-container-feature-development plugin against its
# source of truth, skills/feature-authoring/references/supported-distributions.md.
#
# Usage: check-supported-distributions.sh consistency
#        check-supported-distributions.sh upstream [--new-ubuntu-releases <file>]
#
#   consistency  Every release number and image name in the plugin agrees with the source of truth.
#                Needs no network access; run on every pull request.
#   upstream     The source of truth lists the releases that are current upstream: the latest two
#                Ubuntu LTS releases and Debian stable and oldstable. With --new-ubuntu-releases,
#                also writes the upstream Ubuntu releases missing from the source of truth to <file>,
#                one per line, so that the caller can ask for the matching
#                mcr.microsoft.com/devcontainers/base variants to be checked. Those images are not
#                looked up here: a new Ubuntu release reaches that registry weeks later, and whether
#                a variant is ready to adopt is a human decision.
#
# Exit status: 0 when everything agrees, 1 when differences were found (reported on stdout as
# Markdown, so that the output can become an issue body as is), 2 on any other error.
#
# Backquotes in single-quoted strings below are Markdown code spans and sed patterns, not command
# substitutions, which is what SC2016 warns about.
# shellcheck disable=SC2016
set -euo pipefail

die() {
  echo "check-supported-distributions.sh: $*" >&2
  exit 2
}

for command in git curl awk; do
  command -v "${command}" >/dev/null 2>&1 || die "'${command}' is required but not installed."
done

usage='usage: check-supported-distributions.sh consistency | upstream [--new-ubuntu-releases <file>]'
mode="${1:-}"
new_ubuntu_file=''
case "${mode}" in
  consistency)
    [ "$#" -eq 1 ] || die "${usage}"
    ;;
  upstream)
    if [ "$#" -eq 3 ] && [ "$2" = '--new-ubuntu-releases' ]; then
      new_ubuntu_file="$3"
    elif [ "$#" -ne 1 ]; then
      die "${usage}"
    fi
    ;;
  *) die "${usage}" ;;
esac
repo_root="$(git rev-parse --show-toplevel)"
plugin_dir="${repo_root}/plugins/dev-container-feature-development"
source_file="${plugin_dir}/skills/feature-authoring/references/supported-distributions.md"
workflow_template="${plugin_dir}/skills/init-repository/assets/workflows/test.yaml"
rules_file="${repo_root}/.claude/rules/dev-container-feature-development.md"
source_display="${source_file#"${repo_root}/"}"

[ -f "${source_file}" ] || die "source of truth not found: ${source_file}"

# Checked up front: a missing template would otherwise make cat fail after the report has started,
# and set -e would turn that into exit status 1, which means "update needed".
issue_template="${repo_root}/.github/scripts/issue-templates/distributions-outdated.md"
[ -f "${issue_template}" ] || die "issue template not found: ${issue_template}"

# --- Source of truth -------------------------------------------------------------------------------

# Rows of the "Current releases" table as "<Distribution> <Release> <Codename> <image>".
source_rows="$(awk -F'|' '
  /^\| (Ubuntu|Debian) \|/ {
    for (i = 2; i <= 5; i++) { gsub(/[ `]/, "", $i) }
    print $2, $3, $4, $5
  }' "${source_file}")"
[ -n "${source_rows}" ] || die "no release rows found in ${source_display}"

# The bullet list under "## Non-root test images", one image per line.
non_root_images="$(awk '
  /^## / { section = ($0 == "## Non-root test images"); next }
  section && /^- `[^`]*`$/ { gsub(/^- `|`$/, ""); print }
' "${source_file}")"
[ -n "${non_root_images}" ] || die "no non-root test images found in ${source_display}"

# The code block under "## CI base images", one image per line.
ci_images="$(awk '
  /^## CI base images/ { section = 1; next }
  section && /^```/ { if (fence) exit; fence = 1; next }
  section && fence && NF { print }
' "${source_file}")"
[ -n "${ci_images}" ] || die "no CI base images found in ${source_display}"

table_images="$(printf '%s\n' "${source_rows}" | awk '{ print $4 }')"
ubuntu_releases="$(printf '%s\n' "${source_rows}" | awk '$1 == "Ubuntu" { print $2 }')"
debian_releases="$(printf '%s\n' "${source_rows}" | awk '$1 == "Debian" { print $2 }')"

# $1: newline-separated list, $2: value. Succeeds when the value is an element of the list.
contains() {
  printf '%s\n' "$1" | grep -qxF -- "$2"
}

# --- consistency ---------------------------------------------------------------------------------

check_consistency() {
  local problems=''
  add_problem() {
    problems="${problems}- $1"$'\n'
  }

  # Each row's image must be derived from its distribution and release.
  while read -r distribution release _codename image; do
    expected="$(printf '%s' "${distribution}" | tr '[:upper:]' '[:lower:]'):${release}"
    if [ "${image}" != "${expected}" ]; then
      add_problem "\`${source_display}\`: the ${distribution} ${release} row names \`${image}\`, expected \`${expected}\`."
    fi
  done <<< "${source_rows}"

  # Each non-root image is a base image variant of a supported Ubuntu release.
  while IFS= read -r image; do
    release="${image##*-ubuntu}"
    case "${image}" in
      mcr.microsoft.com/devcontainers/base:[0-9]*-ubuntu*) ;;
      *) release='' ;;
    esac
    if [ -z "${release}" ] || ! contains "${ubuntu_releases}" "${release}"; then
      add_problem "\`${source_display}\`: the non-root test image \`${image}\` is not a devcontainers/base variant of a supported Ubuntu release."
    fi
  done <<< "${non_root_images}"

  # The CI list is exactly the table's images plus the non-root images.
  expected_ci="$(printf '%s\n%s\n' "${table_images}" "${non_root_images}" | sort)"
  if [ "$(printf '%s\n' "${ci_images}" | sort)" != "${expected_ci}" ]; then
    add_problem "\`${source_display}\`: the CI base images differ from the release table plus the non-root test images."
  fi

  # The workflow template's matrix equals the CI list, in the same order.
  template_images="$(awk '
    /^ *baseImage:/ { section = 1; next }
    section && /^ *- / { sub(/^ *- /, ""); print; next }
    section && /^ *#/ { next }
    section { exit }
  ' "${workflow_template}")"
  if [ "${template_images}" != "${ci_images}" ]; then
    add_problem "\`${workflow_template#"${repo_root}/"}\`: the \`baseImage\` matrix differs from the CI base images in \`${source_display}\`."
  fi

  # Every release number or image named anywhere else must be a supported one.
  local files
  files="$(
    git -C "${repo_root}" ls-files --cached --others --exclude-standard -- "${plugin_dir}" "${rules_file}" |
      grep -vxF "${source_display}" || true
  )"
  while IFS= read -r file; do
    [ -n "${file}" ] || continue
    path="${repo_root}/${file}"
    [ -f "${path}" ] || continue

    while IFS=: read -r line match; do
      contains "${table_images}" "${match}" ||
        add_problem "\`${file}:${line}\`: \`${match}\` is not a supported image."
    done < <(grep -noE '\b(ubuntu:[0-9]{2}\.[0-9]{2}|debian:[0-9]+)\b' "${path}" || true)

    while IFS=: read -r line match; do
      contains "${non_root_images}" "${match}" ||
        add_problem "\`${file}:${line}\`: \`${match}\` is not one of the non-root test images."
    done < <(grep -noE 'mcr\.microsoft\.com/devcontainers/base:[A-Za-z0-9._-]+' "${path}" || true)

    while IFS=: read -r line match; do
      contains "${ubuntu_releases}" "${match#Ubuntu }" ||
        add_problem "\`${file}:${line}\`: \`${match}\` is not a supported Ubuntu release."
    done < <(grep -noE '\bUbuntu [0-9]{2}\.[0-9]{2}\b' "${path}" || true)

    while IFS=: read -r line match; do
      contains "${debian_releases}" "${match#Debian }" ||
        add_problem "\`${file}:${line}\`: \`${match}\` is not a supported Debian release."
    done < <(grep -noE '\bDebian [0-9]{1,2}\b' "${path}" || true)
  done <<< "${files}"

  if [ -n "${problems}" ]; then
    printf '## Supported distributions are inconsistent\n\n%s' "${problems}"
    return 1
  fi
  echo "Supported distributions are consistent with ${source_display}."
}

# --- upstream --------------------------------------------------------------------------------------

# $1: URL. Prints the body; exits 2 on any transfer or HTTP error.
fetch() {
  local body
  body="$(curl -fsSL --retry 3 --max-time 30 "$1")" || die "could not fetch $1"
  printf '%s\n' "${body}"
}

capitalize() {
  awk '{ print toupper(substr($0, 1, 1)) substr($0, 2) }'
}

check_upstream() {
  local expected_rows='' ubuntu debian

  # meta-release-lts lists every LTS release oldest first, as blocks of "Key: value" lines. Its
  # "Supported" field says whether upgrades to a release are offered, not whether it is released,
  # so it is not used here.
  ubuntu="$(fetch 'https://changelogs.ubuntu.com/meta-release-lts' | awk '
    /^Dist:/ { dist = $2 }
    /^Version:/ && /LTS/ { split($2, parts, "."); print parts[1] "." parts[2], dist }
  ' | tail -n 2)"
  [ "$(printf '%s\n' "${ubuntu}" | grep -c .)" -eq 2 ] || die 'could not find two Ubuntu LTS releases.'
  while read -r version codename; do
    expected_rows="${expected_rows}Ubuntu ${version} $(printf '%s' "${codename}" | capitalize) ubuntu:${version}"$'\n'
  done < <(printf '%s\n' "${ubuntu}" | sort -r)

  for suite in stable oldstable; do
    debian="$(fetch "https://deb.debian.org/debian/dists/${suite}/Release" | awk '
      /^Version:/ { split($2, parts, "."); version = parts[1] }
      /^Codename:/ { codename = $2 }
      END { print version, codename }
    ')"
    read -r version codename <<< "${debian}"
    [ -n "${version}" ] && [ -n "${codename}" ] || die "could not read the Debian ${suite} release."
    expected_rows="${expected_rows}Debian ${version} $(printf '%s' "${codename}" | capitalize) debian:${version}"$'\n'
  done
  expected_rows="${expected_rows%$'\n'}"

  if [ -n "${new_ubuntu_file}" ]; then
    printf '%s\n' "${ubuntu}" | awk '{ print $1 }' | while IFS= read -r version; do
      contains "${ubuntu_releases}" "${version}" || printf '%s\n' "${version}"
    done > "${new_ubuntu_file}"
  fi

  if [ "${expected_rows}" = "${source_rows}" ]; then
    echo "${source_display} lists the current releases."
    return 0
  fi

  to_table() {
    printf '| Distribution | Release | Codename | Image |\n|---|---|---|---|\n'
    awk '{ printf "| %s | %s | %s | `%s` |\n", $1, $2, $3, $4 }'
  }
  # $1, $2: newline-separated rows. Prints the images of $1 that are not in $2 as a Markdown list.
  images_only_in() {
    local rows_a="$1" rows_b="$2" image
    while read -r _ _ _ image; do
      printf '%s\n' "${rows_b}" | awk '{ print $4 }' | grep -qxF -- "${image}" || printf -- '- `%s`\n' "${image}"
    done <<< "${rows_a}"
  }

  local added removed
  added="$(images_only_in "${expected_rows}" "${source_rows}")"
  removed="$(images_only_in "${source_rows}" "${expected_rows}")"

  # The issue body is in Japanese for the maintainers of this repository; the procedure that follows
  # the tables lives in a template so that it can be edited without touching this script.
  printf '上流のリリース情報が、正本 `%s` と一致しなくなった。この issue は `check-distributions.yml` ワークフローが自動で作成・更新している。\n\n' "${source_display}"
  printf '## 変更点\n\n'
  printf '新しく対象になるリリース:\n\n%s\n\n' "${added:-（なし）}"
  printf '対象から外れるリリース:\n\n%s\n\n' "${removed:-（なし）}"
  printf '## 正本の現在の表\n\n'
  printf '%s\n' "${source_rows}" | to_table
  printf '\n## 上流の最新\n\n'
  printf '%s\n' "${expected_rows}" | to_table
  printf '\n'
  cat "${issue_template}"
  return 1
}

"check_${mode}"
