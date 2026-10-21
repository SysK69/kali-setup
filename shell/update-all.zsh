# Update the whole Kali system - usage: update-all [--help]
update-all() {
  if [[ "$1" == "--help" ]]; then
    echo "update-all - update every tool installed on Kali"
    echo ""
    echo "What it updates:"
    echo "  kali-setup   → git pull of the config repo itself (\$KALI_SETUP_REPO)"
    echo "  tools-sync   → /opt/pentest-tools from manifests (git.list + release.list, shared + local)"
    echo "  apt          → system packages (nmap, metasploit, hashcat, etc.)"
    echo "  pipx         → isolated Python tools (impacket, netexec, bloodyad, dploot, git-dumper)"
    echo "  gem          → Ruby tools (evil-winrm and dependencies)"
    echo "  npm          → global Node.js tools (from ~/.config/kali-setup/npm.list)"
    echo "  pip --user   → personal Python libraries (from ~/.config/kali-setup/pip.list)"
    echo "  git pull     → manual clones in /opt/pentest-tools/ (not in the manifests)"
    echo ""
    echo "Usage: update-all"
    echo "Note: changes to update-all itself apply from the NEXT shell"
    echo "      (or 'source ~/.zshrc'), since the function is already loaded in memory."
    echo "Suggested frequency: weekly, or before every engagement/challenge"
    return 0
  fi

  echo "[1/9] kali-setup repo (self-sync)..."
  if [[ -n "${KALI_SETUP_REPO:-}" && -d "$KALI_SETUP_REPO/.git" ]]; then
    GIT_TERMINAL_PROMPT=0 git -C "$KALI_SETUP_REPO" pull --ff-only && \
      echo "  ✓ kali-setup (update-all changes take effect from the next shell)" || \
      echo "  ⚠ kali-setup: pull skipped"
  else
    echo "  ⚠ \$KALI_SETUP_REPO not set or not a git repo - skip"
  fi

  echo "[2/9] tools-sync (/opt/pentest-tools from manifests)..."
  if [[ -n "${KALI_SETUP_REPO:-}" && -x "$KALI_SETUP_REPO/bin/tools-sync.sh" ]]; then
    bash "$KALI_SETUP_REPO/bin/tools-sync.sh" || echo "  ⚠ tools-sync: errors (see above)"
  else
    echo "  ⚠ tools-sync.sh not found in \$KALI_SETUP_REPO/bin - skip"
  fi

  echo "[3/9] apt..."
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
    sudo apt install -y ${=_toup} || echo "  ⚠ some kept-back packages unresolved (conflicts)"
  fi
  # --purge also removes config files of orphaned packages (old kernels/headers
  # included). apt always protects the running kernel: no risk to the running one.
  sudo apt autoremove --purge -y
  # Reboot notice: if the newest installed kernel ≠ the running one.
  # NEVER reboots on its own - notification only.
  local _run_k _new_k
  _run_k="$(uname -r)"
  _new_k="$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | sort -V | tail -1)"
  if [[ -n "$_new_k" && "$_run_k" != "$_new_k" ]]; then
    echo "  ⚠ kernel: running $_run_k, installed $_new_k → REBOOT recommended"
  elif [[ -f /run/reboot-required ]]; then
    echo "  ⚠ reboot required (/run/reboot-required)"
  fi

  echo "[4/9] pipx..."
  if command -v pipx >/dev/null 2>&1; then
    pipx upgrade-all
  else
    echo "  ⚠ pipx not installed - skip"
  fi

  echo "[5/9] gem..."
  if command -v gem >/dev/null 2>&1; then
    sudo gem update --no-document
  else
    echo "  ⚠ gem not installed - skip"
  fi

  # PERSONAL per-machine lists (scaffolded by setup.sh). Outside the shared repo.
  local _ks_cfg="$HOME/.config/kali-setup"

  echo "[6/9] npm globals (from $_ks_cfg/npm.list)..."
  if ! command -v npm >/dev/null 2>&1; then
    echo "  ⚠ npm not installed - skip"
  elif [[ ! -f "$_ks_cfg/npm.list" ]]; then
    echo "  ⚠ npm.list missing - skip (create $_ks_cfg/npm.list)"
  else
    # npm 11+ BLOCKS postinstall scripts by default (allow-scripts) → packages with a
    # native binary (e.g. @anthropic-ai/claude-code) stay broken stubs. Those packages
    # need: --include=optional (downloads the native binary from optionalDependencies)
    # and --allow-scripts=<pkg> (allows ONLY that package's script, not blanket).
    local _npm_major; _npm_major="$(npm --version 2>/dev/null | cut -d. -f1)"
    grep -vE '^\s*(#|$)' "$_ks_cfg/npm.list" | while read -r pkg; do
      [[ -n "$pkg" ]] || continue
      local -a _flags=(-g --include=optional)
      [[ "${_npm_major:-0}" -ge 11 ]] 2>/dev/null && _flags+=(--allow-scripts="$pkg")
      if npm install "${_flags[@]}" "$pkg" >/dev/null 2>&1; then
        echo "  ✓ $pkg"
      else
        echo "  ⚠ $pkg: install failed"
      fi
    done
  fi

  echo "[7/9] pip --user (from $_ks_cfg/pip.list)..."
  if ! command -v pip >/dev/null 2>&1; then
    echo "  ⚠ pip not installed - skip"
  elif [[ ! -f "$_ks_cfg/pip.list" ]]; then
    echo "  ⚠ pip.list missing - skip (create $_ks_cfg/pip.list)"
  else
    # Kali/Debian PEP 668: externally-managed environment → pip --user needs --break-system-packages
    local -a _pipf=(install --upgrade --user --break-system-packages)
    grep -vE '^\s*(#|$)' "$_ks_cfg/pip.list" | while read -r pkg; do
      [[ -n "$pkg" ]] || continue
      pip "${_pipf[@]}" "$pkg" >/dev/null 2>&1 && echo "  ✓ $pkg" || echo "  ⚠ $pkg: skip"
    done
  fi

  echo "[8/9] manual git clones in /opt/pentest-tools/ (not in the manifests)..."
  for repo in /opt/pentest-tools/*/; do
    [[ -d "$repo/.git" ]] || continue
    name=$(basename "$repo")
    GIT_TERMINAL_PROMPT=0 git -C "$repo" pull && \
      echo "  ✓ $name" || echo "  ⚠ $name: skip"
  done

  echo "[9/9] Done."
}
