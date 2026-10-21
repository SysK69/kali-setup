<div align="center">

<img src="assets/banner.svg" alt="KALI SETUP" width="780">

**`// weaponize a clean Kali in one shot — keep every box in sync`**

[![Bash](https://img.shields.io/badge/shell-bash%20%7C%20zsh-121011?style=for-the-badge&logo=gnubash&logoColor=00ff41)](#)
[![Kali](https://img.shields.io/badge/Kali-rolling-367BF0?style=for-the-badge&logo=kalilinux&logoColor=white)](#)
[![Platform](https://img.shields.io/badge/platform-linux-00ff41?style=for-the-badge&logo=linux&logoColor=black)](#)
[![lint](https://github.com/SysK69/kali-setup/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/SysK69/kali-setup/actions/workflows/shellcheck.yml)

**🇬🇧 English** · [🇮🇹 Italiano](README.it.md)

</div>

---

## `> WHAT IT IS`

**kali-setup** is your pentest environment as **code**. It takes any Kali — fresh or already messy — brings it to a clean, reproducible state, and keeps it updated and **in sync** across all your machines.

You declare *what* you want once (scripts + manifests); any Kali becomes identical with one command, and stays that way. No more polluted PATH, impacket installed three ways, or `/opt` binaries you downloaded months ago and never updated.

```console
root@kali:~# git clone https://github.com/SysK69/kali-setup
root@kali:~# cd kali-setup && bash setup.sh
root@kali:~# source ~/.zshrc
root@kali:~# update-all        # keep it fresh, forever
```

---

## `> HOW IT WORKS`

| | component | does what | when |
|---|-----------|-----------|------|
| 🧹 | **`setup.sh`** | cleans up + configures a Kali (PATH, duplicates, impacket, deps, tools) | once, on a new box |
| 🔄 | **`update-all`** | updates *everything* (system + tools + the repo itself) in one command | weekly / pre-engagement |
| 📦 | **`tools-sync`** | manages `/opt/pentest-tools` from declarative manifests | inside update-all, or by hand |

**Principles:** declarative · idempotent (safe to re-run) · single source of truth · multi-host · non-destructive by default (nothing removed without confirmation).

<details>
<summary><code>setup.sh</code> steps</summary>

```diff
+ [1] AUDIT      PATH, pipx, apt pentest tools
+ [2] FIX PATH   removes venvs · ~/.local/bin before /usr/bin
- [3] PURGE      crackmapexec · dirbuster · zenmap · wfuzz
+ [4] IMPACKET   cleans real scripts · reinstalls via pipx (fortra/impacket)
- [5] LEGACY     removes old bloodhound pipx
+ [6] DEPS       libyaml-dev (fixes gem psych)
+ [7] TOOLS      creates /opt/pentest-tools · installs from manifests · scaffolds local lists
+ [8] ARM        wires update-all into ~/.zshrc
```
Every step is guarded and skips what's already fine. Safe to re-run.
</details>

---

## `> update-all()`

One command, updates everything — and updates itself (step 1 is `git pull` of this repo).

| # | target | what |
|---|--------|------|
| `1` | **kali-setup** | `git pull` of the repo → multi-host auto-sync |
| `2` | **tools-sync** | `/opt/pentest-tools` from the manifests |
| `3` | **apt** | full-upgrade · recovers "kept-back" · `autoremove --purge` old kernels · reboot notice |
| `4` | **pipx** | isolated Python tools (impacket, netexec, bloodyad…) |
| `5` | **gem** | Ruby tools (evil-winrm) |
| `6` | **npm** | global Node.js tools (from local `npm.list`) |
| `7` | **pip --user** | Python libraries (from local `pip.list`) |
| `8` | **/opt** | manual git clones in `/opt/pentest-tools/` |

> Single source: [`shell/update-all.zsh`](shell/update-all.zsh), sourced from `.zshrc`. Changes take effect from the **next shell** (or `source ~/.zshrc`). Run `update-all --help` for details.
>
> To back out: **`bash uninstall.sh`** unwires `update-all` from `~/.zshrc` and removes the symlinks (`--purge` also removes `/opt/pentest-tools` and the local config). It does not undo one-off system changes (apt purges, impacket); `~/.zshrc` is backed up first.

---

## `> TOOL MANAGER` — `/opt/pentest-tools/`

Declare *what* you want in a manifest; `tools-sync.sh` rebuilds it identically on every Kali.

```bash
bin/tools-sync.sh                 # full sync (git + release · shared + local)
bin/tools-sync.sh --git-only      # git repos only
bin/tools-sync.sh --release-only  # GitHub Releases binaries only
bin/tools-sync.sh --import        # suggests found tools (moves nothing)
bin/tools-sync.sh --dedup         # scattered copies → keep/trash/backup (asks)
bin/tools-sync.sh --prune         # removes undeclared tools (opt-in, asks)
```

| manifest | format | update |
|----------|--------|--------|
| `tools/git.list` | `name \| git_url` | `git clone` → then `git pull` |
| `tools/release.list` | `name \| owner/repo \| glob` | latest GitHub release (only if the tag changes) |

- **Shared** tools go in `tools/*.list` (committed) → propagate to all boxes on `update-all`.
- **Local / per-machine** entries go in `~/.config/kali-setup/local.*.list` → stay off git.
- Linux release binaries get a stable symlink `~/.local/bin/<name>` → run `chisel`, not `chisel_1.12.0_linux_amd64`.
- `--dedup` finds old scattered copies of a tool (by git remote or name), shows each version vs the canonical one, and asks to **keep / trash / backup** — never touching `/opt/pentest-tools` itself.

---

## `> MULTI-HOST SYNC` — *strategy B*

```
   KALI #1 ──git push──▶ github.com/SysK69/kali-setup
                                  │
                   update-all → git pull
          ┌──────────────┬───────┴───────┐
          ▼              ▼                ▼
       KALI #2        KALI #3    ...   KALI #n
```

Edit config/manifests on one box → push → every other Kali receives them on the next `update-all`. Shared config lives in the repo; local exceptions stay in `~/.config/kali-setup/`.

---

## `> REQUIREMENTS`

- **Shell: `zsh` only** (Kali default). `setup.sh` writes only to `~/.zshrc`; `update-all.zsh` uses zsh/bash syntax, not POSIX `sh`.
- Also needed: `git`, `curl`, `python3` (always on Kali); optional `gh` (higher GitHub rate-limit / private repos).

---

## `> TREE`

```
kali-setup/
├── setup.sh              # orchestrator: audit → fix → tools → arm
├── uninstall.sh          # unwire update-all + remove symlinks (--purge to remove tools too)
├── bin/tools-sync.sh     # /opt/pentest-tools manager (git + release, dedup, prune, import)
├── tools/{git,release}.list   # SHARED manifests
├── shell/update-all.zsh  # update-all() · single source of truth
├── docs/index.html       # hacker landing page (GitHub Pages, optional)
├── .github/workflows/shellcheck.yml   # CI lint
├── README.md · README.it.md · CHANGELOG.md · CONTRIBUTING.md · LICENSE
└── assets/banner.svg
```

Local, per-machine (outside the repo): `~/.config/kali-setup/{local.git.list,local.release.list,npm.list,pip.list}`

---

## `> CONTRIBUTING` · `> LICENSE`

See [CONTRIBUTING.md](CONTRIBUTING.md) — CI runs `shellcheck` + `zsh -n` on every push/PR.
Licensed under [MIT](LICENSE) © SysK69.

---

<div align="center">

`[ crafted for the terminal · no GUI required ]`

<sub>Built with the help of Claude (Anthropic).</sub>

</div>
