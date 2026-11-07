# AGENTS.md: clean-gone

This repository records the standalone command's retirement. The maintained cleanup workflow lives in [plugins](https://github.com/hakula139/plugins/blob/main/plugins/hakula-workflow/skills/clean-gone/SKILL.md).

## Rules for every change

- Run `nix develop -c true` in each new checkout or worktree to install the pre-commit hooks. Run the hooks on every commit and fix failures without bypassing them.
- Wrap code and comments at 100 columns, counting the indent, and end section banners at column 100. Keep single-line string literals whole.
- Add accepted project words to `.cspell/words.txt`.
- Keep public issues, PRs, and documentation self-contained and link only public material.

## Verification

```bash
nix develop -c prek run --all-files
nix flake check --all-systems
```
