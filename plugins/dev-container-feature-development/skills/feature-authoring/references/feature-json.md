# devcontainer-feature.json reference

Summary of the [Dev Container Features specification](https://containers.dev/implementors/features/). The JSON schema is at <https://raw.githubusercontent.com/devcontainers/spec/main/schemas/devContainerFeature.schema.json>.

## Properties

| Property | Type | Notes |
|---|---|---|
| `id` | string | **Required.** Lowercase; must equal the directory name under `src/`. |
| `version` | string | **Required.** SemVer. The publisher skips versions that already exist. |
| `name` | string | **Required.** Human-friendly display name. |
| `description` | string | One sentence; shown in the collection README and in tool UIs. |
| `documentationURL` | string | `https://github.com/<owner>/<repo>/tree/main/src/<id>`. |
| `licenseURL` | string | `https://github.com/<owner>/<repo>/blob/main/LICENSE`. |
| `keywords` | string[] | Search terms. |
| `options` | object | See below. |
| `containerEnv` | object | Name/value pairs set as `ENV` before `install.sh` runs. May reference `${PATH}`-style existing variables. |
| `privileged` | boolean | Runs the container privileged. Avoid unless unavoidable (e.g. Docker-in-Docker). |
| `init` | boolean | Adds the tini init process. |
| `capAdd` | string[] | Linux capabilities to add. |
| `securityOpt` | string[] | Security options such as a seccomp profile. |
| `entrypoint` | string | Absolute path to a script run at container start. The script must be installed to that path by `install.sh`, must `exec "$@"` at the end, and must not block. |
| `mounts` | object[] | Docker `--mount` style objects. `${devcontainerId}` may be used in `source` to scope a volume per dev container. |
| `customizations` | object | Tool-specific settings, e.g. `customizations.vscode.extensions` and `customizations.vscode.settings`. |
| `dependsOn` | object | Hard dependencies, same shape as `features` in `devcontainer.json`. They are installed first and pulled in automatically. |
| `installsAfter` | string[] | Soft ordering: only affects Features that are already being installed. IDs without version tags. |
| `legacyIds` | string[] | Previous IDs, for renaming within one namespace. |
| `deprecated` | boolean | Marks the Feature as deprecated. |
| `onCreateCommand`, `updateContentCommand`, `postCreateCommand`, `postStartCommand`, `postAttachCommand` | string, array, or object | Lifecycle hooks. Run from the workspace folder, before the user's own hooks of the same kind. |

## Options

```json
"options": {
  "version": {
    "type": "string",
    "proposals": ["latest", "1.2.3"],
    "default": "latest",
    "description": "Version to install, or 'latest'."
  },
  "installCompletions": {
    "type": "boolean",
    "default": true,
    "description": "Install shell completions for bash and zsh."
  }
}
```

- `type` is `string` or `boolean`. Boolean values arrive in the script as the strings `true` / `false`.
- `enum` accepts only the listed values; `proposals` suggests values but accepts anything. Use one or the other.
- The option ID becomes the environment variable: non-word characters are replaced with `_`, leading digits and underscores are replaced with `_`, and the result is upper-cased. `installCompletions` → `INSTALLCOMPLETIONS`.
- Every option is exported, with its default when the user did not set it.
- A user may write `"ghcr.io/<owner>/<repo>/<id>": "1.2"` as a shorthand for `{ "version": "1.2" }`. Name the version option `version` so this works.
- Never take secrets as options. Option values are committed in the user's `devcontainer.json`, appear in build logs, and are written to `devcontainer-features.env`, which can persist in an image layer depending on how the image is built.

## User variables available to install.sh

| Variable | Meaning |
|---|---|
| `_REMOTE_USER` | `remoteUser` from the configuration or image metadata; falls back to `_CONTAINER_USER`. |
| `_REMOTE_USER_HOME` | Home directory of `_REMOTE_USER`. |
| `_CONTAINER_USER` | The container's user (`containerUser`, `USER`, or the base image's user). |
| `_CONTAINER_USER_HOME` | Home directory of `_CONTAINER_USER`. |

## Install order

1. `dependsOn` is resolved recursively, and each dependency is installed before the dependent Feature. Dependencies with different options count as different Features.
2. `installsAfter` only reorders Features that are already queued. It never adds a Feature.
3. The user's `overrideFeatureInstallOrder` can pull Features forward but cannot violate the graph above.

Prefer `installsAfter` for "run after `common-utils` if it is there" relationships. Use `dependsOn` only when the Feature cannot work at all without the other Feature, and document it in `NOTES.md`, since it changes what gets installed.

## Versioning rules

Choose the bump from the effect on existing users:

- **Major**: an option removed or its meaning changed; a changed install path, volume name, or mount target; a new `dependsOn`; any change after which an existing configuration behaves differently or loses data.
- **Minor**: a new option, new supported platform, new warnings or detection, all backward-compatible.
- **Patch**: bug fixes and documentation-only changes.

Publishing `1.2.3` also moves the `1`, `1.2`, and `latest` tags.
