#!/usr/bin/env bash
# uninstall.sh - kali-setup
# Reverses what setup.sh wired up, as far as it is safely reversible:
#   - unwires update-all from ~/.zshrc (removes the kali-setup block; backs up first)
#   - removes ~/.local/bin symlinks that point into /opt/pentest-tools
#   - with --purge: also removes /opt/pentest-tools and ~/.config/kali-setup (asks)
#
# NOTE: it does NOT undo the one-off system changes setup.sh made (apt purges,
# impacket reinstall, PATH line, libyaml-dev): those are not cleanly reversible.
# Your pre-setup ~/.zshrc backups are kept as ~/.zshrc.bak.* if you want them.
#
# Usage:
#   bash uninstall.sh            unwire update-all + remove symlinks (keeps /opt tools)
#   bash uninstall.sh --purge    also remove /opt/pentest-tools and ~/.config/kali-setup (asks)
#   bash uninstall.sh --help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; NC='\033[0m'
info(){ echo -e "${GRN}[+]${NC} $*"; }
warn(){ echo -e "${YLW}[!]${NC} $*"; }
error(){ echo -e "${RED}[x]${NC} $*"; }

ZSHRC="$HOME/.zshrc"
TOOLS_DIR="${TOOLS_DIR:-/opt/pentest-tools}"
LOCAL_DIR="${KALI_SETUP_LOCAL:-$HOME/.config/kali-setup}"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"

PURGE=0
case "${1:-}" in
  --help|-h) sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  --purge)   PURGE=1 ;;
  "")        : ;;
  *) error "unknown option: $1"; exit 1 ;;
esac

# ─── 1. UNWIRE update-all FROM .zshrc ──────────────────────────────────────
if grep -q "KALI_SETUP_REPO=" "$ZSHRC" 2>/dev/null; then
    cp "$ZSHRC" "$ZSHRC.bak.$(date +%Y%m%d%H%M%S)"
    info "Backed up $ZSHRC"
    # remove the 3 lines individually (dash-agnostic: matches old em dash or new hyphen)
    sed -i -E '/^# kali-setup .* update-all/d; /^export KALI_SETUP_REPO=/d; /source .*\/update-all\.zsh"?/d' "$ZSHRC"
    # drop a possible trailing blank line left behind at EOF
    sed -i -e :a -e '/^\n*$/{$d;N;ba}' "$ZSHRC"
    info "Unwired update-all from $ZSHRC"
else
    info "update-all not wired in $ZSHRC - nothing to unwire"
fi

# ─── 2. REMOVE ~/.local/bin SYMLINKS POINTING INTO /opt/pentest-tools ──────
removed=0
if [[ -d "$LOCAL_BIN" ]]; then
    for l in "$LOCAL_BIN"/*; do
        [[ -L "$l" ]] || continue
        tgt="$(readlink "$l")"
        if [[ "$tgt" == "$TOOLS_DIR"/* ]]; then
            rm -f "$l" && info "Removed symlink $(basename "$l")" && ((removed++))
        fi
    done
fi
[[ $removed -eq 0 ]] && info "No kali-setup symlinks in $LOCAL_BIN"

# ─── 3. OPTIONAL PURGE ─────────────────────────────────────────────────────
if [[ $PURGE -eq 1 ]]; then
    if [[ -d "$TOOLS_DIR" ]]; then
        read -r -p "Remove $TOOLS_DIR and all tools in it? [y/N] " a
        if [[ "$a" == "y" || "$a" == "Y" ]]; then
            sudo rm -rf "$TOOLS_DIR" && info "Removed $TOOLS_DIR"
        else
            info "Kept $TOOLS_DIR"
        fi
    fi
    if [[ -d "$LOCAL_DIR" ]]; then
        read -r -p "Remove local config $LOCAL_DIR (manifests, npm/pip lists)? [y/N] " a
        if [[ "$a" == "y" || "$a" == "Y" ]]; then
            rm -rf "$LOCAL_DIR" && info "Removed $LOCAL_DIR"
        else
            info "Kept $LOCAL_DIR"
        fi
    fi
else
    info "Kept $TOOLS_DIR and $LOCAL_DIR (use --purge to remove them)"
fi

echo ""
info "Done. Open a new shell (or 'source ~/.zshrc') - update-all is gone."
info "To also delete this cloned repo, run:  rm -rf \"$SCRIPT_DIR\""
warn "Note: apt purges, impacket reinstall and the PATH line from setup.sh were NOT reverted."
warn "      Pre-setup backups (if any): $(ls -1 "$ZSHRC".bak.* 2>/dev/null | tail -1 || echo 'none')"
