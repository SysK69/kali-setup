#!/usr/bin/env bash
# tools-sync.sh - manages the tools in /opt/pentest-tools/ from declarative manifests.
#
# SHARED manifests (versioned in the repo):    tools/git.list   tools/release.list
# LOCAL manifests (per-machine, not in git):   ~/.config/kali-setup/local.git.list
#                                              ~/.config/kali-setup/local.release.list
#
# Usage:
#   tools-sync.sh                 full sync (git + release, shared + local)
#   tools-sync.sh --git-only      git repos only
#   tools-sync.sh --release-only  release binaries only
#   tools-sync.sh --import        scan the system and suggest lines for git.list
#   tools-sync.sh --prune         remove tools in /opt/pentest-tools NOT in the manifests (asks)
#   tools-sync.sh --dedup         find scattered copies of declared tools, keep/trash/backup (asks)
#   tools-sync.sh --help

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TOOLS_DIR="${TOOLS_DIR:-/opt/pentest-tools}"
LOCAL_DIR="${KALI_SETUP_LOCAL:-$HOME/.config/kali-setup}"
LOCAL_BIN="${LOCAL_BIN:-$HOME/.local/bin}"   # already in PATH (setup.sh) → stable symlinks here
BACKUP_DIR="${KALI_SETUP_BACKUP:-$HOME/.local/share/kali-setup/backup}"   # --dedup backup target

SHARED_GIT="$REPO_DIR/tools/git.list"
SHARED_REL="$REPO_DIR/tools/release.list"
LOCAL_GIT="$LOCAL_DIR/local.git.list"
LOCAL_REL="$LOCAL_DIR/local.release.list"

GRN='\033[0;32m'; YLW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info(){ echo -e "${GRN}[+]${NC} $*"; }
warn(){ echo -e "${YLW}[!]${NC} $*"; }
err(){  echo -e "${RED}[x]${NC} $*"; }

# ─── util ──────────────────────────────────────────────────────────────────
trim(){ local s="$*"; s="${s#"${s%%[![:space:]]*}"}"; s="${s%"${s##*[![:space:]]}"}"; printf '%s' "$s"; }

# Reads a manifest, emits cleaned "field1|field2|field3" lines (skips empty/#).
read_manifest(){
  local f="$1"
  [[ -f "$f" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    printf '%s\n' "$line"
  done < "$f"
}

ensure_tools_dir(){
  if [[ -d "$TOOLS_DIR" && -w "$TOOLS_DIR" ]]; then return 0; fi
  if [[ ! -d "$TOOLS_DIR" ]]; then
    warn "Creating $TOOLS_DIR (needs sudo once)..."
    sudo mkdir -p "$TOOLS_DIR"
  fi
  if [[ ! -w "$TOOLS_DIR" ]]; then
    warn "Giving ownership of $TOOLS_DIR to $USER (needs sudo)..."
    sudo chown -R "$USER:$USER" "$TOOLS_DIR"
  fi
}

# GitHub token (from gh if logged in, or $GITHUB_TOKEN) for higher rate-limit + private repos
gh_token(){ gh auth token 2>/dev/null || printf '%s' "${GITHUB_TOKEN:-}"; }

# true if the file is a native linux executable (worth linking into PATH)
is_linux_bin(){
  case "$1" in
    *.exe|*.dll|*.ps1|*.txt|*.zip|*.md|*.bat) return 1 ;;
    *) return 0 ;;
  esac
}

# stable symlink ~/.local/bin/<name> → <target> (version-less name, usable in PATH)
link_bin(){
  local name="$1" target="$2"
  mkdir -p "$LOCAL_BIN"
  ln -sfn "$target" "$LOCAL_BIN/$name"
}

# normalize a git url to "owner/repo" (lowercase, no .git, host/scheme stripped) for matching
normalize_url(){
  local u="${1%.git}"
  u="${u%/}"
  u="$(printf '%s' "$u" | tr ':A-Z' '/a-z')"   # scheme/host separators → '/', lowercase
  # keep the last two path components (owner/repo)
  printf '%s' "$u" | awk -F/ '{ if (NF>=2) print $(NF-1)"/"$NF; else print $NF }'
}

# short version string of a git repo: "<short-hash> (<date>)", or "no-git" if not a repo
git_ver(){
  local d="$1"
  [[ -d "$d/.git" ]] || { printf 'no-git'; return; }
  git -C "$d" log -1 --format='%h (%cs)' 2>/dev/null || printf 'unknown'
}

# ─── GIT SYNC ────────────────────────────────────────────────────────────────
sync_git(){
  info "Sync git repos → $TOOLS_DIR"
  local any=0
  while IFS='|' read -r name url _; do
    name="$(trim "$name")"; url="$(trim "$url")"
    [[ -z "$name" || -z "$url" ]] && continue
    any=1
    local dest="$TOOLS_DIR/$name"
    if [[ -d "$dest/.git" ]]; then
      # align the remote to the manifest url (handles renamed/moved repos)
      git -C "$dest" remote set-url origin "$url" 2>/dev/null || true
      if GIT_TERMINAL_PROMPT=0 git -C "$dest" pull --ff-only >/dev/null 2>&1; then
        info "  ✓ $name (pull)"
      else
        warn "  ⚠ $name: pull failed (skip)"
      fi
    else
      if GIT_TERMINAL_PROMPT=0 git clone --depth 1 "$url" "$dest" >/dev/null 2>&1; then
        info "  ✓ $name (clone)"
      else
        err "  ✗ $name: clone failed"
      fi
    fi
  done < <(cat <(read_manifest "$SHARED_GIT") <(read_manifest "$LOCAL_GIT"))
  [[ $any -eq 0 ]] && warn "  no git repos in the manifests"
}

# ─── RELEASE SYNC ────────────────────────────────────────────────────────────
# fetches "tag<TAB>asset_url" given owner/repo + glob
release_info(){
  local repo="$1" glob="$2" token json
  token="$(gh_token)"
  local -a hdr=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
  [[ -n "$token" ]] && hdr+=(-H "Authorization: Bearer $token")
  json="$(curl -fsSL "${hdr[@]}" "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)" || return 1
  printf '%s' "$json" | python3 -I -c '
import sys, json, fnmatch
d = json.load(sys.stdin)
tag = d.get("tag_name", "")
glob = sys.argv[1]
url = next((a["browser_download_url"] for a in d.get("assets", []) if fnmatch.fnmatch(a["name"], glob)), "")
print(f"{tag}\t{url}")
' "$glob"
}

# download url of the first release asset matching a glob (empty if none)
release_asset_url(){
  local repo="$1" glob="$2" token json
  token="$(gh_token)"
  local -a hdr=(-H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28")
  [[ -n "$token" ]] && hdr+=(-H "Authorization: Bearer $token")
  json="$(curl -fsSL "${hdr[@]}" "https://api.github.com/repos/$repo/releases/latest" 2>/dev/null)" || return 1
  printf '%s' "$json" | python3 -I -c '
import sys, json, fnmatch
d = json.load(sys.stdin)
print(next((a["browser_download_url"] for a in d.get("assets", []) if fnmatch.fnmatch(a["name"], sys.argv[1])), ""))
' "$glob"
}

# verify sha256 of a downloaded asset against a checksum published in the release.
#   args: file repo [sha_glob]
#   returns: 0 verified · 1 MISMATCH · 2 no checksum available (can't verify)
verify_sha(){
  local file="$1" repo="$2" sha_glob="$3"
  command -v sha256sum >/dev/null 2>&1 || { warn "    sha256sum missing - cannot verify"; return 2; }
  local base actual; base="$(basename "$file")"
  actual="$(sha256sum "$file" | awk '{print $1}')"
  # candidate checksum assets: manifest-provided first, then common conventions
  local -a cands=()
  [[ -n "$sha_glob" ]] && cands+=("$sha_glob")
  cands+=("${base}.sha256" "${base}.sha256sum" "checksums.txt" "SHA256SUMS" "sha256sum.txt" "*_checksums.txt" "*checksums*.txt" "*.sha256")
  local g aurl tmp expected
  for g in "${cands[@]}"; do
    aurl="$(release_asset_url "$repo" "$g")" || continue
    [[ -z "$aurl" ]] && continue
    tmp="$(mktemp)" || continue
    if ! curl -fsSL -o "$tmp" "$aurl" 2>/dev/null; then rm -f "$tmp"; continue; fi
    # line listing our file, else a bare single hash (per-file .sha256)
    expected="$(grep -F "$base" "$tmp" 2>/dev/null | grep -oiE '[0-9a-f]{64}' | head -1)"
    [[ -z "$expected" ]] && expected="$(grep -oiE '[0-9a-f]{64}' "$tmp" | head -1)"
    rm -f "$tmp"
    [[ -z "$expected" ]] && continue
    if [[ "${actual,,}" == "${expected,,}" ]]; then
      info "    sha256 verified ($g)"; return 0
    fi
    err "    sha256 MISMATCH - expected ${expected:0:12}… got ${actual:0:12}…"; return 1
  done
  return 2
}

sync_release(){
  info "Sync binaries from GitHub Releases → $TOOLS_DIR"
  command -v curl  >/dev/null || { err "curl missing"; return 1; }
  command -v python3 >/dev/null || { err "python3 missing"; return 1; }
  local any=0
  while IFS='|' read -r name repo glob sha_glob; do
    name="$(trim "$name")"; repo="$(trim "$repo")"; glob="$(trim "$glob")"; sha_glob="$(trim "$sha_glob")"
    [[ -z "$name" || -z "$repo" || -z "$glob" ]] && continue
    any=1
    local dest="$TOOLS_DIR/$name"
    local info_line tag url
    info_line="$(release_info "$repo" "$glob")" || { warn "  ⚠ $name: API failed (skip)"; continue; }
    tag="${info_line%%$'\t'*}"; url="${info_line#*$'\t'}"
    if [[ -z "$tag" ]]; then warn "  ⚠ $name: no release (skip)"; continue; fi
    if [[ -z "$url" ]]; then warn "  ⚠ $name: no asset matches '$glob' (skip)"; continue; fi
    local cur=""; [[ -f "$dest/.version" ]] && cur="$(cat "$dest/.version")"
    if [[ "$tag" == "$cur" ]]; then
      info "  = $name already at $tag"
      # ensure the symlink even if already up to date (e.g. ~/.local/bin cleaned by hand)
      if [[ -f "$dest/.binary" ]]; then
        local bf; bf="$(cat "$dest/.binary")"
        if [[ -f "$dest/$bf" ]] && is_linux_bin "$bf"; then link_bin "$name" "$dest/$bf"; fi
      fi
      continue
    fi
    mkdir -p "$dest"
    local fname; fname="$(basename "$url")"
    if curl -fsSL -o "$dest/$fname" "$url"; then
      # integrity check on the raw downloaded asset (before decompressing)
      local rc; verify_sha "$dest/$fname" "$repo" "$sha_glob"; rc=$?
      if [[ $rc -eq 1 ]]; then
        err "  ✗ $name: checksum mismatch → NOT installing"; rm -f "$dest/$fname"; continue
      elif [[ $rc -eq 2 ]]; then
        if [[ "${KALI_SETUP_STRICT_SHA:-0}" == "1" ]]; then
          err "  ✗ $name: no published checksum + STRICT mode → skip"; rm -f "$dest/$fname"; continue
        fi
        warn "  ⚠ $name: no published checksum - installed UNVERIFIED"
      fi
      # decompress .gz
      if [[ "$fname" == *.gz ]]; then gunzip -f "$dest/$fname" && fname="${fname%.gz}"; fi
      # make linux scripts/binaries executable (not .exe/.dll/.ps1)
      if is_linux_bin "$fname"; then
        chmod +x "$dest/$fname" 2>/dev/null || true
        link_bin "$name" "$dest/$fname"   # ~/.local/bin/<name> → versioned binary
      fi
      printf '%s' "$tag" > "$dest/.version"
      printf '%s' "$fname" > "$dest/.binary"   # remember the binary for future re-links
      info "  ✓ $name → $tag ($fname)"
    else
      err "  ✗ $name: download failed"
    fi
  done < <(cat <(read_manifest "$SHARED_REL") <(read_manifest "$LOCAL_REL"))
  [[ $any -eq 0 ]] && warn "  no binaries in the manifests"
}

# ─── IMPORT (suggests, does not move) ────────────────────────────────────────
do_import(){
  info "Scanning git repos (/opt/pentest-tools ~ \$HOME ~ /usr/share) - SUGGESTIONS ONLY:"
  echo ""
  local found=0
  while IFS= read -r gitdir; do
    local d name url
    d="$(dirname "$gitdir")"
    [[ "$d" == "$REPO_DIR" ]] && continue   # skip the kali-setup repo itself
    name="$(basename "$d")"
    url="$(git -C "$d" remote get-url origin 2>/dev/null)"
    [[ -z "$url" ]] && continue
    # skip if already in the manifest
    if read_manifest "$SHARED_GIT" | grep -q "| *$url\| $url"; then continue; fi
    printf '%-28s | %s\n' "$name" "$url"
    found=1
  # scan only the dedicated pentest dir under /opt (not all of /opt → skips normal apps like Obsidian)
  done < <(find /opt/pentest-tools "$HOME" /usr/share -maxdepth 4 -type d -name .git 2>/dev/null)
  [[ $found -eq 0 ]] && warn "no new git repos found"
  echo ""
  info "Copy the useful lines into tools/git.list (shared) or ~/.config/kali-setup/local.git.list (local only)"
}

# ─── PRUNE (destructive, asks for confirmation) ──────────────────────────────
do_prune(){
  [[ -d "$TOOLS_DIR" ]] || { warn "$TOOLS_DIR does not exist"; return 0; }
  # names declared in all manifests
  local declared
  declared="$( { read_manifest "$SHARED_GIT"; read_manifest "$LOCAL_GIT"; read_manifest "$SHARED_REL"; read_manifest "$LOCAL_REL"; } \
               | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$1); if($1!="") print $1}' | sort -u)"
  warn "PRUNE - removes tools in $TOOLS_DIR NOT present in the manifests."
  local removed=0
  for dir in "$TOOLS_DIR"/*/; do
    [[ -d "$dir" ]] || continue
    local name; name="$(basename "$dir")"
    if printf '%s\n' "$declared" | grep -qx "$name"; then continue; fi
    read -r -p "  Remove '$name'? [y/N] " ans
    if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
      # also remove the PATH symlink if it points into this dir
      if [[ -L "$LOCAL_BIN/$name" && "$(readlink "$LOCAL_BIN/$name")" == "$dir"* ]]; then
        rm -f "$LOCAL_BIN/$name"
      fi
      rm -rf "$dir" && info "    removed $name" && removed=1
    else
      info "    kept $name"
    fi
  done
  [[ $removed -eq 0 ]] && info "Nothing to remove (or everything kept)"
}

# ─── DEDUP (find scattered copies of declared tools; keep/trash/backup) ───────
do_dedup(){
  info "Scanning for scattered copies of declared tools (\$HOME ~ /opt, excl. $TOOLS_DIR)..."
  # declared git tools: parallel arrays name[] + normalized url[]
  local -a names=() urls=()
  while IFS='|' read -r name url _; do
    name="$(trim "$name")"; url="$(trim "$url")"
    [[ -z "$name" ]] && continue
    names+=("$name"); urls+=("$(normalize_url "$url")")
  done < <(cat <(read_manifest "$SHARED_GIT") <(read_manifest "$LOCAL_GIT"))
  [[ ${#names[@]} -eq 0 ]] && { warn "no git tools declared - nothing to dedup"; return 0; }

  # collect candidates as "name<TAB>path", unique by path
  local found="" gitdir d url norm i
  # pass A - git repos matched by remote url
  while IFS= read -r gitdir; do
    d="$(dirname "$gitdir")"
    case "$d/" in "$TOOLS_DIR"/*|"$REPO_DIR"/*) continue;; esac
    url="$(git -C "$d" remote get-url origin 2>/dev/null)" || continue
    norm="$(normalize_url "$url")"
    [[ -z "$norm" ]] && continue
    for i in "${!names[@]}"; do
      if [[ "$norm" == "${urls[$i]}" ]]; then found+="${names[$i]}"$'\t'"$d"$'\n'; break; fi
    done
  done < <(find "$HOME" /opt -maxdepth 6 -type d -name .git 2>/dev/null)
  # pass B - dirs matched by basename (catches non-git copies)
  for i in "${!names[@]}"; do
    while IFS= read -r d; do
      case "$d/" in "$TOOLS_DIR"/*|"$REPO_DIR"/*) continue;; esac
      [[ "$found" == *$'\t'"$d"$'\n'* ]] && continue   # already collected
      found+="${names[$i]}"$'\t'"$d"$'\n'
    done < <(find "$HOME" /opt -maxdepth 6 -type d -iname "${names[$i]}" 2>/dev/null)
  done

  found="$(printf '%s' "$found" | awk 'NF' | sort -u)"
  if [[ -z "$found" ]]; then info "No scattered copies found. Clean."; return 0; fi

  echo ""
  warn "Scattered copies found. For each: keep / trash / backup."
  echo "  Note: you don't need to keep these old copies, but instead of trashing them"
  echo "  you can move them to the backup folder - at the cost of disk space."
  echo "  Backup folder: $BACKUP_DIR"
  echo ""

  local name path canon canon_ver found_ver ans="" ts=""
  while IFS=$'\t' read -r name path; do
    [[ -z "$name" || -z "$path" || ! -d "$path" ]] && continue
    canon="$TOOLS_DIR/$name"
    found_ver="$(git_ver "$path")"
    if [[ -d "$canon" ]]; then canon_ver="$(git_ver "$canon")"; else canon_ver="(not installed yet)"; fi
    echo "▸ $name"
    printf '    found:     %-44s @ %s\n' "$path" "$found_ver"
    printf '    canonical: %-44s @ %s\n' "$canon" "$canon_ver"
    # read from the terminal (not the here-string on stdin); no tty → default to keep
    ans=""
    read -r -p "    keep / trash / backup ? [K/t/b] " ans </dev/tty 2>/dev/null || ans=""
    ts="$(date +%Y%m%d%H%M%S)"
    case "$ans" in
      t|T)
        if command -v gio >/dev/null 2>&1; then
          gio trash "$path" && info "    trashed $path" || err "    trash failed"
        else
          warn "    gio not available → moving to backup instead"
          mkdir -p "$BACKUP_DIR" && mv "$path" "$BACKUP_DIR/${name}-${ts}" && info "    backed up to $BACKUP_DIR/${name}-${ts}"
        fi ;;
      b|B)
        mkdir -p "$BACKUP_DIR" && mv "$path" "$BACKUP_DIR/${name}-${ts}" \
          && info "    moved to $BACKUP_DIR/${name}-${ts}" || err "    move failed" ;;
      *) info "    kept $path" ;;
    esac
  done <<< "$found"
}

usage(){ awk 'NR>1{ if($0 ~ /^#/){sub(/^# ?/,"");print} else exit }' "$0"; }

# ─── MAIN ────────────────────────────────────────────────────────────────────
case "${1:-}" in
  --help|-h) usage; exit 0 ;;
  --import)  do_import; exit 0 ;;
  --prune)   ensure_tools_dir; do_prune; exit 0 ;;
  --dedup)   do_dedup; exit 0 ;;
  --git-only)     ensure_tools_dir; sync_git; exit 0 ;;
  --release-only) ensure_tools_dir; sync_release; exit 0 ;;
  "")        ensure_tools_dir; sync_git; sync_release; exit 0 ;;
  *) err "unknown option: $1"; usage; exit 1 ;;
esac
