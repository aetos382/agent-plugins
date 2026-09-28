## How it works

- Downloads `mytool_<version>_linux_<arch>.tar.gz` from the [mytool releases](https://github.com/example-org/mytool/releases), verifies it against the release's `checksums.txt`, and installs the binary to `/usr/local/bin/mytool` (owned by root, mode 755).
- mytool publishes checksums but no signatures, and `checksums.txt` comes from the same release as the archive. The check therefore catches corrupted or truncated downloads, but not a release that was tampered with at the source.
- When `version` names an exact version, the installed binary has to report that version or the install fails.
- `version: latest` is resolved by following the redirect of the releases/latest page rather than the GitHub API, so builds are not subject to the API's rate limit.

## Requirements

- `curl`, `ca-certificates`, `tar`, `gzip`, and `sha256sum` (coreutils). On images with `apt-get`, the missing ones are installed automatically.
- On images without `apt-get`, install them beforehand; the Feature fails with a message naming what is missing.

## Limitations

- Tested on Ubuntu 26.04, Ubuntu 24.04, Debian 13, and Debian 12. Other distributions are not tested.
- Linux only, for `amd64` and `arm64`.
- Pin an exact version for reproducible builds; `latest` changes whenever upstream releases.
