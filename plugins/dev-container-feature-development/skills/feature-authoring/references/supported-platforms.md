# Supported platforms

This file is the single source of truth for the distributions, images, and architectures that Features must support and that CI tests. Every other file in this plugin that names a supported release, test image, or architecture must agree with it.

## Policy

- **Ubuntu**: the latest LTS release and the one before it.
- **Debian**: the current stable and oldstable releases.
- **Non-root test images**: `mcr.microsoft.com/devcontainers/base` in the variant for each supported Ubuntu LTS release, each at the newest major version that has that variant. These images have a non-root `vscode` user, which exercises the `_REMOTE_USER` path, and are what most dev containers are built on. The variant for a new Ubuntu release appears weeks after the release; until it does, the list covers only the supported releases that have one.
- Other distributions are supported only when doing so costs no more than a package-manager branch, and are not tested.
- **Architectures**: every architecture in the "Architectures" table, each tested in CI on a native runner of that architecture. A Feature may leave one out only when the upstream publishes no build for it. Architectures missing from the table are not supported, because CI cannot test them.
- A platform counts as tested only when the CI test workflow runs it. A local run on the developer's machine does not count, because it covers only that machine's architecture and is not repeated on every pull request.

## Current releases

Last checked against upstream release information: 2026-09-18.

| Distribution | Release | Codename | Image |
|---|---|---|---|
| Ubuntu | 26.04 | Resolute | `ubuntu:26.04` |
| Ubuntu | 24.04 | Noble | `ubuntu:24.04` |
| Debian | 13 | Trixie | `debian:13` |
| Debian | 12 | Bookworm | `debian:12` |

## Non-root test images

- `mcr.microsoft.com/devcontainers/base:3-ubuntu26.04`
- `mcr.microsoft.com/devcontainers/base:3-ubuntu24.04`

## CI base images

The test workflow's `baseImage` matrix lists every image above, in this order:

```
debian:12
debian:13
ubuntu:24.04
ubuntu:26.04
mcr.microsoft.com/devcontainers/base:3-ubuntu24.04
mcr.microsoft.com/devcontainers/base:3-ubuntu26.04
```

## Architectures

Each Feature lists the architectures it supports in `test/<id>/architectures`, and the global scenarios in `test/_global/architectures`, using the names in the first column. The test workflow runs each of them on the runner in the last column.

| Architecture | `uname -m` | CI runner |
|---|---|---|
| amd64 | `x86_64` | `ubuntu-latest` |
| arm64 | `aarch64` | `ubuntu-24.04-arm` |
