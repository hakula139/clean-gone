# Releasing

Follow [devkit's release procedure](https://github.com/hakula139/devkit/blob/61682dd34d15732234bac835f3603de8de5b86f1/docs/releasing.md#cut-a-release) with the contracts below.

## Compatibility

Before 1.0, a change to flags, apply-by-default behavior, exit codes, workflow-consumed output, cleanup and preservation semantics, or published flake outputs requires a minor version bump and a Breaking changes entry. Fixes to shipped behavior bump the patch version. After 1.0, use semantic versioning. A prerelease section lists changes since the previous tag.

The agent workflow skill has its own plugin version and is maintained in [plugins](https://github.com/hakula139/plugins/tree/main/plugins/hakula-workflow/skills/clean-gone). Update it when a CLI contract change affects the procedure.

## Release contract

- The package version in `flake.nix` is the version source.
- Notes come from `CHANGELOG.md`, drafted with the local `cliff.toml` and curated in the release PR.
- Run the [verification commands](AGENTS.md#verification). After publication, verify the release notes, package version, and a tagged `nix run` in a disposable checkout. Exercise a dry-run and an apply scenario, and confirm remote refs stay unchanged.
- A `vX.Y.Z` tag starts `.github/workflows/tag.yml`, which checks the package version and calls devkit's release workflow. It requires passing CI on the tagged commit, pins the package for `x86_64-linux` and `aarch64-darwin`, and publishes changelog-based GitHub notes. No binary archives or registry packages are published.

The reusable release workflow requires `CACHIX_AUTH_TOKEN` in repository secrets. Configure it through the hosting platform without copying its value into the repository.

To restore a published tag's cache pin, run `gh workflow run nix-cache.yml --ref vX.Y.Z`. Follow [devkit's republish procedure](https://github.com/hakula139/devkit/blob/61682dd34d15732234bac835f3603de8de5b86f1/docs/releasing.md#republish-release-notes) to refresh GitHub Release notes from a corrected changelog.
