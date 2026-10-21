<div align="center">

<img src="assets/banner.svg" alt="KALI SETUP" width="780">

**`// weaponize a clean Kali in one shot - keep every box in sync`**

[![Bash](https://img.shields.io/badge/shell-bash%20%7C%20zsh-121011?style=for-the-badge&logo=gnubash&logoColor=00ff41)](#)
[![Kali](https://img.shields.io/badge/Kali-rolling-367BF0?style=for-the-badge&logo=kalilinux&logoColor=white)](#)
[![Platform](https://img.shields.io/badge/platform-linux-00ff41?style=for-the-badge&logo=linux&logoColor=black)](#)
[![lint](https://github.com/SysK69/kali-setup/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/SysK69/kali-setup/actions/workflows/shellcheck.yml)

**🇬🇧 English** · [🇮🇹 Italiano](README.it.md)

</div>

---

## `> WHAT IT IS`

**kali-setup** automates the setup and upkeep of a Kali pentest box. Instead of configuring every machine by hand - and remembering what you installed, where, and with which package manager - **you declare it once** in this repo (tool lists + scripts).

Then on any Kali: clone, run one command, and get the **exact same environment** - clean, with every tool up to date. Add or change something and a single `git pull` brings **all your boxes** in line.

No more venv-polluted PATH, impacket installed three different ways, or `/opt` binaries you downloaded months ago and never updated.

```console
root@kali:~# git clone https://github.com/SysK69/kali-setup
root@kali:~# cd kali-setup && ./setup.sh
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

**Principles**

- **Declarative** - you describe *what* you want (lists), not the steps to install it
- **Idempotent** - safe to re-run; each step only does what's missing
- **Single source of truth** - one place per thing, no copies that drift apart
- **Multi-host** - the repo is the shared truth; every box aligns via `git pull`
- **Non-destructive** - nothing is removed without an explicit confirmation

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

One command, updates everything - and updates itself (step 1 is `git pull` of this repo).

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

**Good to know**

- **Source of truth:** the function lives in [`shell/update-all.zsh`](shell/update-all.zsh), sourced from `~/.zshrc`. Edits to it take effect in the **next shell** (or after `source ~/.zshrc`).
- **Summary:** a per-step result (ok / warn / skip) is printed at the end of every run.
- **Run a subset:** `update-all --only apt,npm` runs just those steps.
- **Preview:** `update-all --dry-run` shows what the system upgrade *would* do, changing nothing.
- **Release check:** the apt step flags a newer Kali release when one is out.
- Full help: `update-all --help`.

**Uninstall** - `./uninstall.sh` unwires `update-all` from `~/.zshrc` and removes the tool symlinks (add `--purge` to also delete `/opt/pentest-tools` and the local config). Your `~/.zshrc` is backed up first. It does **not** undo one-off system changes (apt purges, impacket).

---

## `> TOOL MANAGER` - `/opt/pentest-tools/`

External tools (not in apt) live in `/opt/pentest-tools/`. You list them in a **manifest** - a plain text file, one tool per line - and `tools-sync.sh` installs and updates them, identically on every Kali.

```bash
bin/tools-sync.sh                 # full sync (git + release · shared + local)
bin/tools-sync.sh --git-only      # git repos only
bin/tools-sync.sh --release-only  # GitHub Releases binaries only
bin/tools-sync.sh --import        # suggests found tools (moves nothing)
bin/tools-sync.sh --dedup         # scattered copies → keep/backup/trash/delete (asks)
bin/tools-sync.sh --prune         # removes undeclared tools (opt-in, asks)
```

| manifest | format | update |
|----------|--------|--------|
| `tools/git.list` | `name \| git_url` | `git clone` → then `git pull` |
| `tools/release.list` | `name \| owner/repo \| glob` | latest GitHub release (only if the tag changes) |

- **Shared** tools go in `tools/*.list` (committed) → propagate to all boxes on `update-all`.
- **Local / per-machine** entries go in `~/.config/kali-setup/local.*.list` → stay off git.
- Linux release binaries get a stable symlink `~/.local/bin/<name>` → run `chisel`, not `chisel_1.12.0_linux_amd64`.
- `--dedup` finds old scattered copies of a tool (by git remote or name), shows each version vs the canonical one, and asks (numbered menu) to **keep / backup / trash / delete** - never touching `/opt/pentest-tools` itself.

---

## `> MULTI-HOST SYNC` - *strategy B*

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

> ⚠️ **Per-user install** - this configures *your* user, not the whole system:
> - `update-all` is wired into **your** `~/.zshrc`
> - local manifests + `npm.list` / `pip.list` live in `~/.config/kali-setup/`
> - `/opt/pentest-tools` is owned by the user that ran `setup.sh`
>
> It's tied to your account: **recreate or switch the user and you lose it** - so back up `~/.config/kali-setup/` if the box matters. A shared, system-wide install isn't supported out of the box (it would wire into `/etc/zsh/zshrc` with a group-owned `/opt`).

---

## `> TREE`

```
kali-setup/
├── setup.sh              # orchestrator: audit → fix → tools → arm
├── uninstall.sh          # unwire update-all + remove symlinks (--purge to remove tools too)
├── bin/tools-sync.sh     # /opt/pentest-tools manager (git + release, dedup, prune, import)
├── tools/{git,release}.list   # SHARED manifests
├── shell/update-all.zsh  # update-all() · single source of truth
├── tests/tools-sync.bats # bats unit tests (pure helpers)
├── docs/index.html       # hacker landing page (GitHub Pages, optional)
├── .github/workflows/shellcheck.yml   # CI lint + bats
├── README.md · README.it.md · CHANGELOG.md · CONTRIBUTING.md · LICENSE
└── assets/banner.svg
```

Local, per-machine (outside the repo): `~/.config/kali-setup/{local.git.list,local.release.list,npm.list,pip.list}`

---

## `> CONTRIBUTING` · `> LICENSE`

See [CONTRIBUTING.md](CONTRIBUTING.md) - CI runs `shellcheck` + `zsh -n` on every push/PR.
Licensed under [MIT](LICENSE) © SysK69.

---

<div align="center">

`[ crafted for the terminal · no GUI required ]`

<sub>Built with the help of Claude (Anthropic).</sub>

</div>
