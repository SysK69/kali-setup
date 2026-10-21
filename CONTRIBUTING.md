# Contributing

Thanks for your interest in **kali-setup**. This is a small, focused project: a
reproducible pentest environment for Kali, driven by shell scripts and
declarative manifests.

## Scope

In scope: cleanup/config logic (`setup.sh`), the `update-all` updater, the
`/opt/pentest-tools` manager (`tools-sync.sh`), and the tool manifests.

Out of scope: non-pentest applications, GUI tooling, and anything that writes
outside `~/.zshrc`, `~/.config/kali-setup/`, and `/opt/pentest-tools/`.

## Language

Everything in the repo is **English** — code, comments, output strings, and
docs. The only exception is `README.it.md` (Italian translation of the README).
If you change `README.md`, keep `README.it.md` in sync (or note it in the PR).

## Dev requirements

- `zsh` (the project targets zsh; `setup.sh` writes only to `~/.zshrc`)
- `shellcheck` for linting the bash scripts
- `git`, `curl`, `python3`

## Before opening a PR

Run the same checks the CI runs:

```bash
shellcheck -x -s bash -S warning setup.sh bin/tools-sync.sh
zsh -n shell/update-all.zsh
bash -n setup.sh bin/tools-sync.sh
```

CI (`.github/workflows/shellcheck.yml`) runs these on every push to `main` and
on every PR. Keep it green.

## Conventions

- **Commits**: [Conventional Commits](https://www.conventionalcommits.org/)
  (`feat:`, `fix:`, `docs:`, `ci:`, `refactor:`…).
- **Idempotent**: scripts must be safe to re-run — guard every step, skip what's
  already done.
- **Non-destructive by default**: nothing is removed without explicit
  confirmation (`--prune` is opt-in and prompts per tool).
- **Shared vs local**: shared tools go in `tools/*.list` (committed); personal /
  per-machine entries go in `~/.config/kali-setup/local.*.list`, `npm.list`,
  `pip.list` (never committed).

## Adding a tool to the shared manifests

```bash
# git-based tool
echo "name | https://github.com/owner/repo.git" >> tools/git.list

# release binary
echo "name | owner/repo | asset_glob" >> tools/release.list

# apply locally to verify
bin/tools-sync.sh
```

Then commit the manifest change with a `feat(tools):` message.
