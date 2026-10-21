#!/usr/bin/env bash
# setup.sh - kali-setup
# Configures a clean Kali: removes duplicates, fixes PATH, installs up-to-date tools via pipx,
# and wires the update-all function into ~/.zshrc.
# Usage: bash setup.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GRN}[+]${NC} $*"; }
warn()  { echo -e "${YLW}[!]${NC} $*"; }
error() { echo -e "${RED}[x]${NC} $*"; }
section() { echo -e "\n${YLW}══════════════════════════════${NC}"; echo -e "${YLW} $*${NC}"; echo -e "${YLW}══════════════════════════════${NC}"; }

# ─── 1. INITIAL STATE AUDIT ────────────────────────────────────────────────
section "1. INITIAL STATE AUDIT"

info "System Python: $(which python3) - $(/usr/bin/python3 --version 2>/dev/null)"
info "Current PATH:"
echo "$PATH" | tr ':' '\n' | sed 's/^/    /'

echo ""
info "Installed pipx venvs:"
pipx list 2>/dev/null | grep "package " | sed 's/^/    /' || warn "pipx not found"

echo ""
info "Relevant pentest apt packages:"
# NB: grep with no match exits 1 → with `set -o pipefail` it would abort the script. `|| true` avoids it.
dpkg -l 2>/dev/null | grep -E "^ii.*(impacket|netexec|bloodhound|crackmapexec|certipy|evil-winrm|dirbuster|zenmap|wfuzz)" \
  | awk '{print "    "$2, $3}' || true

echo ""
info "Suspicious PATH entries (venvs in PATH):"
echo "$PATH" | tr ':' '\n' | grep -i "venv\|pipx/venvs" && warn "venv entries found in PATH - should be removed" || info "PATH clean"

# ─── 2. FIX PATH - remove venvs from PATH in .zshrc ──────────────────────
section "2. FIX PATH"

ZSHRC="$HOME/.zshrc"

if grep -q "pipx/venvs" "$ZSHRC" 2>/dev/null; then
    warn "venv entry found in PATH of $ZSHRC - removing..."
    sed -i '/pipx\/venvs/d' "$ZSHRC"
    info "Removed"
else
    info "PATH in $ZSHRC already clean"
fi

# Make sure ~/.local/bin comes before /usr/bin
if ! grep -q 'HOME/.local/bin' "$ZSHRC" 2>/dev/null; then
    warn "\$HOME/.local/bin not in PATH - adding..."
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$ZSHRC"
    info "Added \$HOME/.local/bin to PATH"
else
    info "\$HOME/.local/bin already in PATH"
fi

# ─── 3. REMOVE OBSOLETE APT TOOLS ─────────────────────────────────────────
section "3. REMOVE OBSOLETE APT TOOLS"

REMOVE_APT=(crackmapexec dirbuster zenmap wfuzz)
TO_REMOVE=()

for pkg in "${REMOVE_APT[@]}"; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii"; then
        TO_REMOVE+=("$pkg")
    fi
done

if [[ ${#TO_REMOVE[@]} -gt 0 ]]; then
    info "Removing: ${TO_REMOVE[*]}"
    sudo apt remove --purge "${TO_REMOVE[@]}" -y
    sudo apt autoremove -y
else
    info "No obsolete tools found"
fi

# ─── 4. FIX IMPACKET - remove real files, reinstall via pipx ───────────────
section "4. FIX IMPACKET"

# impacket scripts to KEEP (they are not part of impacket)
KEEP_SCRIPTS="dumppdf.py pdf2txt.py fetch_tles.py"

# Idempotency: if impacket is already installed via pipx AND secretsdump.py is a symlink
# (= clean install from the pipx venv), touch nothing. Avoids reinstalling on every run.
if pipx list 2>/dev/null | grep -q "impacket" && [[ -L "$HOME/.local/bin/secretsdump.py" ]]; then
    info "impacket already installed via pipx (secretsdump.py is a symlink) - skip reinstall"
else
    # Remove pipx impacket if present (with broken symlinks or real files)
    if pipx list 2>/dev/null | grep -q "impacket"; then
        info "Uninstalling pipx impacket (reinstall needed)..."
        pipx uninstall impacket
    fi

    # Remove real impacket files from ~/.local/bin (not symlinks)
    info "Cleaning real impacket scripts from ~/.local/bin..."
    removed=0
    for f in "$HOME/.local/bin/"*.py; do
        [[ -f "$f" ]] || continue
        name=$(basename "$f")
        # Skip the files to keep
        if echo "$KEEP_SCRIPTS" | grep -qw "$name"; then
            continue
        fi
        # Remove only real files (not symlinks) that import impacket
        if [[ ! -L "$f" ]] && grep -q "impacket" "$f" 2>/dev/null; then
            rm "$f"
            ((removed++))
        fi
    done
    info "Removed $removed real impacket scripts"

    # Reinstall impacket via pipx from git (most up-to-date dev version)
    info "Installing impacket from GitHub..."
    pipx install git+https://github.com/fortra/impacket.git
fi

info "Symlink check:"
ls -la "$HOME/.local/bin/secretsdump.py" 2>/dev/null && \
    readlink "$HOME/.local/bin/secretsdump.py" | sed 's/^/    → /' || \
    error "secretsdump.py not found"

# ─── 5. REMOVE LEGACY PIPX TOOLS ──────────────────────────────────────────
section "5. PIPX LEGACY"

# legacy bloodhound (for old BH, replaced by bloodhound-ce-python apt)
if pipx list 2>/dev/null | grep -q "^   package bloodhound "; then
    info "Removing legacy bloodhound pipx..."
    pipx uninstall bloodhound
else
    info "legacy bloodhound pipx not present"
fi

# ─── 6. SYSTEM DEPENDENCIES ───────────────────────────────────────────────
section "6. SYSTEM DEPENDENCIES"

# libyaml-dev required by the psych gem
if ! dpkg -l libyaml-dev 2>/dev/null | grep -q "^ii"; then
    info "Installing libyaml-dev..."
    sudo apt install libyaml-dev -y
    sudo gem update psych --no-document
else
    info "libyaml-dev already installed"
fi

# ─── 7. TOOL MANAGER /opt/pentest-tools ───────────────────────────────────
section "7. TOOL MANAGER (/opt/pentest-tools)"

LOCAL_DIR="$HOME/.config/kali-setup"
info "Scaffolding local manifests in $LOCAL_DIR..."
mkdir -p "$LOCAL_DIR"
if [[ ! -f "$LOCAL_DIR/local.git.list" ]]; then
    cat > "$LOCAL_DIR/local.git.list" <<'EOF'
# local.git.list - git repos ONLY on this machine (NOT synced to other Kali boxes)
# Format: name | git_url
EOF
    info "Created local.git.list"
fi
if [[ ! -f "$LOCAL_DIR/local.release.list" ]]; then
    cat > "$LOCAL_DIR/local.release.list" <<'EOF'
# local.release.list - release binaries ONLY on this machine (NOT synced)
# Format: name | owner/repo | glob_asset
EOF
    info "Created local.release.list"
fi
# Global npm / pip --user packages: PERSONAL and per-machine → local lists (not in the repo).
# update-all reads them from here. One package per line; '#' = comment.
if [[ ! -f "$LOCAL_DIR/npm.list" ]]; then
    cat > "$LOCAL_DIR/npm.list" <<'EOF'
# npm.list - global npm packages updated by update-all (local, per-machine)
# One package per line. Example:
# @anthropic-ai/claude-code
EOF
    info "Created npm.list"
fi
if [[ ! -f "$LOCAL_DIR/pip.list" ]]; then
    cat > "$LOCAL_DIR/pip.list" <<'EOF'
# pip.list - pip --user packages updated by update-all (local, per-machine)
# One package per line. Example:
# pycryptodome
EOF
    info "Created pip.list"
fi

TOOLS_SYNC="$SCRIPT_DIR/bin/tools-sync.sh"
if [[ -x "$TOOLS_SYNC" ]]; then
    info "Running tools-sync (creates /opt/pentest-tools + installs tools from manifests)..."
    bash "$TOOLS_SYNC" || warn "tools-sync reported errors (continuing)"
else
    warn "tools-sync.sh not found/executable - skip"
fi

# ─── 8. WIRE update-all INTO .zshrc ───────────────────────────────────────
section "8. update-all FUNCTION"

UPDATE_ALL_SRC="$SCRIPT_DIR/shell/update-all.zsh"

if [[ ! -f "$UPDATE_ALL_SRC" ]]; then
    error "File not found: $UPDATE_ALL_SRC"
elif grep -q "KALI_SETUP_REPO=" "$ZSHRC" 2>/dev/null; then
    info "update-all already wired in $ZSHRC (source-based)"
else
    # Strategy B: .zshrc sources the file from the repo → git pull propagates changes.
    # Remove any old inline update-all function copied in (migration from heredoc).
    if grep -q "^update-all()" "$ZSHRC" 2>/dev/null; then
        warn "Old inline update-all found in $ZSHRC - backup + removal..."
        cp "$ZSHRC" "$ZSHRC.bak.$(date +%Y%m%d%H%M%S)"
        # delete from the guide comment down to the function's closing brace
        sed -i '/^# Update the whole Kali system/,/^}$/d' "$ZSHRC"
        info "Old function removed (backup saved)"
    fi
    info "Wiring update-all via source (from $UPDATE_ALL_SRC)..."
    {
        echo ""
        echo "# kali-setup - update-all (source-based, auto-sync via git pull)"
        echo "export KALI_SETUP_REPO=\"$SCRIPT_DIR\""
        echo "source \"\$KALI_SETUP_REPO/shell/update-all.zsh\""
    } >> "$ZSHRC"
    info "Wired"
fi

# ─── 9. FINAL CHECK ───────────────────────────────────────────────────────
section "9. FINAL CHECK"

info "which python3: $(which python3)"
info "python3 version: $(python3 --version)"
info "which secretsdump.py: $(which secretsdump.py 2>/dev/null || echo 'NOT FOUND')"
info "secretsdump.py → $(readlink "$(which secretsdump.py 2>/dev/null)" 2>/dev/null || echo 'not a symlink')"

echo ""
info "Installed pipx tools:"
pipx list 2>/dev/null | grep "package " | sed 's/^/    /'

echo ""
info "Final PATH:"
grep "^export PATH" "$ZSHRC" | sed 's/^/    /'

echo ""
warn "PER-USER install: update-all is wired into ~/.zshrc, config in ~/.config/kali-setup,"
warn "and /opt/pentest-tools is owned by $USER. It is tied to THIS user account."
warn "Recreate/switch the user and you lose it → back up ~/.config/kali-setup/ if it matters."

echo ""
info "Setup complete. Reload your shell:"
echo "    source ~/.zshrc"
echo "    update-all --help"
