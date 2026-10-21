# Update the whole Kali system - usage: update-all [--help] [--only <steps>]
update-all() {
  if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "update-all - update every tool installed on Kali"
    echo ""
    echo "Steps (name → what it updates):"
    echo "  self   → git pull of the config repo itself (\$KALI_SETUP_REPO)"
    echo "  tools  → /opt/pentest-tools from manifests (tools-sync: git + release)"
    echo "  apt    → system packages + full-upgrade (kept-back recovery, kernel purge/notice)"
    echo "  pipx   → isolated Python tools (impacket, netexec, bloodyad, dploot, git-dumper)"
    echo "  gem    → Ruby tools (evil-winrm and dependencies)"
    echo "  npm    → global Node.js tools (from ~/.config/kali-setup/npm.list)"
    echo "  pip    → personal Python libraries (from ~/.config/kali-setup/pip.list)"
    echo "  opt    → git pull of manual clones in /opt/pentest-tools/ (not in the manifests)"
    echo ""
    echo "Usage:"
    echo "  update-all                 run all steps, then print a summary"
    echo "  update-all --only apt      run only the apt step"
    echo "  update-all --only npm,pip  run only npm and pip (comma or space separated)"
    echo ""
    echo "Note: changes to update-all itself apply from the NEXT shell (or 'source ~/.zshrc'),"
    echo "      since the function is already loaded in memory."
    echo "Suggested frequency: weekly, or before every engagement/challenge"
    return 0
  fi

  # --only <steps>: restrict to a subset (comma/space separated step names)
  local only=""
  if [[ "$1" == "--only" ]]; then
    if [[ -z "${2:-}" ]]; then echo "update-all: --only needs step names (see --help)"; return 1; fi
    only=" ${2//,/ } "                 # pad with spaces for word matching
    local _w
    for _w in ${=2//,/ }; do
      [[ " self tools apt pipx gem npm pip opt " == *" $_w "* ]] || echo "update-all: unknown step '$_w' (ignored)"
    done
  elif [[ -n "${1:-}" ]]; then
    echo "update-all: unknown option '$1' (see --help)"; return 1
  fi

  # per-step status, printed as a summary at the end
  local -A _st
  local _order=(self tools apt pipx gem npm pip opt)
  _want(){ [[ -z "$only" || "$only" == *" $1 "* ]] }   # dynamic scope: sees $only
  _mark(){ _st[$1]="$2" }

  # ── self ──────────────────────────────────────────────────────────────────
  if _want self; then
    echo "[self] kali-setup repo (self-sync)..."
    if [[ -n "${KALI_SETUP_REPO:-}" && -d "$KALI_SETUP_REPO/.git" ]]; then
      if GIT_TERMINAL_PROMPT=0 git -C "$KALI_SETUP_REPO" pull --ff-only; then
        echo "  ✓ kali-setup (update-all changes take effect from the next shell)"; _mark self ok
      else
        echo "  ⚠ kali-setup: pull skipped"; _mark self warn
      fi
    else
      echo "  ⚠ \$KALI_SETUP_REPO not set or not a git repo - skip"; _mark self skip
    fi
  fi

  # ── tools ─────────────────────────────────────────────────────────────────
  if _want tools; then
    echo "[tools] tools-sync (/opt/pentest-tools from manifests)..."
    if [[ -n "${KALI_SETUP_REPO:-}" && -x "$KALI_SETUP_REPO/bin/tools-sync.sh" ]]; then
      if bash "$KALI_SETUP_REPO/bin/tools-sync.sh"; then _mark tools ok; else echo "  ⚠ tools-sync: errors (see above)"; _mark tools warn; fi
    else
      echo "  ⚠ tools-sync.sh not found in \$KALI_SETUP_REPO/bin - skip"; _mark tools skip
    fi
  fi

  # ── apt ───────────────────────────────────────────────────────────────────
  if _want apt; then
    echo "[apt] system packages..."
    _mark apt ok
    sudo apt update
    sudo apt full-upgrade -y
    # full-upgrade (apt 3.0 solver, conservative) keeps back packages whose upgrade
    # requires installing NEW packages or removing others. Recover them with an explicit
    # install, excluding manual holds (apt-mark hold) which must be respected.
    local _kept _held _toup
    _kept="$(apt list --upgradable 2>/dev/null | awk -F/ 'NR>1 && $1!="" {print $1}' | sort -u)"
    _held="$(apt-mark showhold 2>/dev/null | sort -u)"
    _toup="$(comm -23 <(echo "$_kept") <(echo "$_held"))"
    if [[ -n "$_toup" ]]; then
      echo "  kept-back → explicit install: ${_toup//$'\n'/ }"
      sudo apt install -y ${=_toup} || { echo "  ⚠ some kept-back packages unresolved (conflicts)"; _mark apt warn; }
    fi
    # --purge also removes config files of orphaned packages (old kernels/headers
    # included). apt always protects the running kernel: no risk to the running one.
    sudo apt autoremove --purge -y
    # Reboot notice: if the newest installed kernel != the running one. Never reboots.
    local _run_k _new_k
    _run_k="$(uname -r)"
    _new_k="$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V | tail -1)"
    if [[ -n "$_new_k" && "$_run_k" != "$_new_k" ]]; then
      echo "  ⚠ kernel: running $_run_k, installed $_new_k → REBOOT recommended"
    elif [[ -f /run/reboot-required ]]; then
      echo "  ⚠ reboot required (/run/reboot-required)"
    fi
  fi

  # ── pipx ──────────────────────────────────────────────────────────────────
  if _want pipx; then
    echo "[pipx]..."
    if command -v pipx >/dev/null 2>&1; then pipx upgrade-all; _mark pipx ok
    else echo "  ⚠ pipx not installed - skip"; _mark pipx skip; fi
  fi

  # ── gem ───────────────────────────────────────────────────────────────────
  if _want gem; then
    echo "[gem]..."
    if command -v gem >/dev/null 2>&1; then sudo gem update --no-document; _mark gem ok
    else echo "  ⚠ gem not installed - skip"; _mark gem skip; fi
  fi

  # PERSONAL per-machine lists (scaffolded by setup.sh). Outside the shared repo.
  local _ks_cfg="$HOME/.config/kali-setup"

  # ── npm ───────────────────────────────────────────────────────────────────
  if _want npm; then
    echo "[npm] globals (from $_ks_cfg/npm.list)..."
    if ! command -v npm >/dev/null 2>&1; then
      echo "  ⚠ npm not installed - skip"; _mark npm skip
    elif [[ ! -f "$_ks_cfg/npm.list" ]]; then
      echo "  ⚠ npm.list missing - skip (create $_ks_cfg/npm.list)"; _mark npm skip
    else
      # npm 11+ BLOCKS postinstall scripts by default (allow-scripts) → packages with a
      # native binary (e.g. @anthropic-ai/claude-code) stay broken stubs. Those packages
      # need: --include=optional (native binary from optionalDependencies) and
      # --allow-scripts=<pkg> (allows ONLY that package's script, not blanket).
      local _npm_major; _npm_major="$(npm --version 2>/dev/null | cut -d. -f1)"
      grep -vE '^\s*(#|$)' "$_ks_cfg/npm.list" | while read -r pkg; do
        [[ -n "$pkg" ]] || continue
        local -a _flags=(-g --include=optional)
        [[ "${_npm_major:-0}" -ge 11 ]] 2>/dev/null && _flags+=(--allow-scripts="$pkg")
        if npm install "${_flags[@]}" "$pkg" >/dev/null 2>&1; then echo "  ✓ $pkg"; else echo "  ⚠ $pkg: install failed"; fi
      done
      _mark npm ok
    fi
  fi

  # ── pip ───────────────────────────────────────────────────────────────────
  if _want pip; then
    echo "[pip] --user (from $_ks_cfg/pip.list)..."
    if ! command -v pip >/dev/null 2>&1; then
      echo "  ⚠ pip not installed - skip"; _mark pip skip
    elif [[ ! -f "$_ks_cfg/pip.list" ]]; then
      echo "  ⚠ pip.list missing - skip (create $_ks_cfg/pip.list)"; _mark pip skip
    else
      # Kali/Debian PEP 668: externally-managed env → pip --user needs --break-system-packages
      local -a _pipf=(install --upgrade --user --break-system-packages)
      grep -vE '^\s*(#|$)' "$_ks_cfg/pip.list" | while read -r pkg; do
        [[ -n "$pkg" ]] || continue
        pip "${_pipf[@]}" "$pkg" >/dev/null 2>&1 && echo "  ✓ $pkg" || echo "  ⚠ $pkg: skip"
      done
      _mark pip ok
    fi
  fi

  # ── opt ───────────────────────────────────────────────────────────────────
  if _want opt; then
    echo "[opt] manual git clones in /opt/pentest-tools/ (not in the manifests)..."
    _mark opt ok
    for repo in /opt/pentest-tools/*/; do
      [[ -d "$repo/.git" ]] || continue
      name=$(basename "$repo")
      GIT_TERMINAL_PROMPT=0 git -C "$repo" pull && echo "  ✓ $name" || echo "  ⚠ $name: skip"
    done
  fi

  # ── summary ─────────────────────────────────────────────────────────────────
  echo ""
  echo "=== summary ==="
  local s sym
  for s in $_order; do
    [[ -n "${_st[$s]}" ]] || continue
    case "${_st[$s]}" in
      ok)   sym="✓" ;;
      warn) sym="⚠" ;;
      *)    sym="-" ;;
    esac
    printf "  %s %-6s %s\n" "$sym" "$s" "${_st[$s]}"
  done
}
