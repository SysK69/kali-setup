# Changelog

All notable changes to this project are documented here.
Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
versioning follows [SemVer](https://semver.org/).

## [Unreleased]

### Added
- `tools-sync --dedup`: finds scattered copies of declared tools across `$HOME`/`/opt` (matched by git remote or name), shows each copy's version vs the canonical one, and asks to keep / trash (`gio trash`) / backup (`$KALI_SETUP_BACKUP`, default `~/.local/share/kali-setup/backup`). Never touches `/opt/pentest-tools`; default action is keep.
- `LICENSE` (MIT).
- GitHub Actions CI (`lint`): ShellCheck on `setup.sh` + `bin/tools-sync.sh`, `zsh -n` on `shell/update-all.zsh`.
- Local per-machine lists `~/.config/kali-setup/{npm,pip}.list` for personal packages (scaffolded by `setup.sh`).
- `tools-sync`: stable symlinks `~/.local/bin/<name>` → versioned release binary (`.binary` file for re-linking); `--prune` also removes the orphaned symlink.
- `update-all` recovers apt "kept back" packages via explicit install (manual holds excluded).
- `update-all` apt step: `autoremove --purge` (cleans old kernels/headers) + non-blocking reboot notice.

### Changed
- `update-all`: personal npm/pip packages no longer hardcoded → read from the local lists.
- `update-all` npm step: `--include=optional` + `--allow-scripts=<pkg>` (only on npm ≥11) to avoid leaving broken stubs (e.g. claude-code).
- `update-all` pip step: `--break-system-packages` (PEP 668).
- `update-all`: `command -v` guards on npm/pip/pipx/gem → clean skip when absent.
- Project language switched to English (code, comments, output, docs); Italian README kept as `README.it.md`.

### Fixed
- `setup.sh` sec.1: audit pipe `dpkg|grep|awk` aborted under `set -o pipefail` on no match → `|| true`.
- `setup.sh` sec.4: impacket reinstalled on every run → now idempotent (skip if pipx + `secretsdump.py` symlink).
- `update-all`: npm 11+ blocked postinstall scripts → `claude-code` broke on every update.
- `update-all`: pip `--user` failed silently on externally-managed Kali (PEP 668).

## [0.1.0] — 2026-10-10

### Added
- Repo structure: `setup.sh`, `bin/tools-sync.sh`, `tools/{git,release}.list`, `shell/update-all.zsh`, `assets/banner.svg`, `docs/index.html`, `README.md`.
- Declarative tool manager for `/opt/pentest-tools` (shared + local manifests, git + GitHub releases).
- 9-step `update-all` (self-sync → tools-sync → apt → pipx → gem → npm → pip → /opt → done).
- Multi-host strategy "B" (auto-sync via `git pull` of the repo itself).
