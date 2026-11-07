# Releasing

The package version in `flake.nix` is the version source. A `vX.Y.Z` tag starts the Tag Release workflow, which checks that version and uses [devkit's release procedure](https://github.com/hakula139/devkit/blob/v1.0.0-rc.3/docs/releasing.md#release-your-repository).

## Compatibility

Before 1.0, a change to flags, apply-by-default behavior, exit codes, workflow-consumed output, cleanup and preservation semantics, or published flake outputs requires a minor version bump and a Breaking changes entry. Fixes to shipped behavior bump the patch version. After 1.0, use semantic versioning. A prerelease section lists changes since the previous tag.

The agent workflow skill has its own plugin version and is maintained in [plugins](https://github.com/hakula139/plugins/tree/main/plugins/hakula-workflow/skills/clean-gone). Update it when a CLI contract change affects the procedure.

## Prepare and publish

1. Create a release branch from `main`, update the package version, and draft the next changelog section with `git cliff --unreleased --tag vX.Y.Z --prepend CHANGELOG.md`. For a prerelease, add `--tag-pattern '^v[0-9]+\.'` so its notes start at the previous tag.
2. Curate the section for users, keep every relevant PR link, and add its compare-link definition. Preserve existing curated sections. For the first release, describe the implemented behavior without inventing a previous release.
3. Run the [verification commands](AGENTS.md#verification), review the release PR, and merge it only after approval and passing CI.
4. Obtain separate approval to push the release tag. Tag the release PR's exact merge commit and push it. The workflow requires passing CI on that commit before publishing.
5. Verify the release notes, package version, and a tagged `nix run` in a disposable checkout. Exercise a dry-run and an apply scenario, and confirm remote refs stay unchanged.

The reusable release workflow requires `CACHIX_AUTH_TOKEN` in repository secrets. Configure it through the hosting platform without copying its value into the repository. No release is published by an ordinary branch push.

To restore a published tag's cache pin, run `gh workflow run nix-cache.yml --ref vX.Y.Z`. Follow [devkit's republish procedure](https://github.com/hakula139/devkit/blob/v1.0.0-rc.3/docs/releasing.md#republish-release-notes) to refresh GitHub Release notes from a corrected changelog.
