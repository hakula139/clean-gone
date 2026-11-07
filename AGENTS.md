# AGENTS.md: clean-gone

clean-gone is a Nushell command that removes finished local Git branches and stale linked worktrees while preserving ignored agent memory and plans.

## Rules for every change

- Run `nix develop -c true` in each new checkout or worktree to install the pre-commit hooks. Run the hooks on every commit and fix failures without bypassing them.
- Wrap code and comments at 100 columns, counting the indent, and end section banners at column 100. Keep single-line string literals whole.
- Export only commands consumed by another module or its tests. Dependencies flow from Git, activity, request, output, and agent-file helpers to cleanup, then to the CLI entry. Keep behavior tests beside their modules and shared test helpers under `src/tests/`.
- Keep `.stub.nu` files beside the tests that use them because devkit discovers stubs in each test file's directory.
- Preserve cleanup decisions, output, exit codes, dry-run behavior, and preservation-before-removal ordering when refactoring. Compare old and new behavior with disposable Git repositories.
- Keep forge CLIs on the caller's PATH so host authentication wrappers remain effective. Never include tokens or host configuration in the package.
- Add accepted project words to `.cspell/words.txt`.
- Keep public issues, PRs, and documentation self-contained and link only public material.

General Nushell conventions live in the [Nushell skill](https://github.com/hakula139/plugins/blob/main/plugins/hakula-languages/skills/nushell/SKILL.md). Read [devkit's CI guide](https://github.com/hakula139/devkit/blob/61682dd34d15732234bac835f3603de8de5b86f1/README.md#adopt-the-ci-workflow-and-the-gate) before changing CI and [RELEASING.md](RELEASING.md) before a release.

## Verification

```bash
nix flake check --all-systems
nix build
nix develop -c nu-test src/*.test.nu
nix run . -- --help
```

Use disposable repositories for cleanup tests. The command applies changes by default.
