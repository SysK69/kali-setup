#!/usr/bin/env bats
# Unit tests for the pure helpers in bin/tools-sync.sh.
# Sourcing is safe: the script's main runs only when executed directly.

setup() {
  source "${BATS_TEST_DIRNAME}/../bin/tools-sync.sh"
}

# ─── normalize_url ───────────────────────────────────────────────────────────
@test "normalize_url: https + .git → owner/repo lowercase" {
  run normalize_url "https://github.com/Akamai/BadSuccessor.git"
  [ "$status" -eq 0 ]
  [ "$output" = "akamai/badsuccessor" ]
}

@test "normalize_url: git@ ssh form → owner/repo" {
  run normalize_url "git@github.com:Akamai/BadSuccessor.git"
  [ "$output" = "akamai/badsuccessor" ]
}

@test "normalize_url: no .git suffix still works" {
  run normalize_url "https://github.com/dirkjanm/PKINITtools"
  [ "$output" = "dirkjanm/pkinittools" ]
}

@test "normalize_url: https and ssh of the same repo match" {
  a="$(normalize_url 'https://github.com/micahvandeusen/gMSADumper.git')"
  b="$(normalize_url 'git@github.com:micahvandeusen/gMSADumper.git')"
  [ "$a" = "$b" ]
}

# ─── is_linux_bin ────────────────────────────────────────────────────────────
@test "is_linux_bin: linux binary → true" {
  run is_linux_bin "chisel_1.12.0_linux_amd64"
  [ "$status" -eq 0 ]
}

@test "is_linux_bin: shell script → true" {
  run is_linux_bin "linpeas.sh"
  [ "$status" -eq 0 ]
}

@test "is_linux_bin: .exe → false" {
  run is_linux_bin "winPEASx64.exe"
  [ "$status" -eq 1 ]
}

@test "is_linux_bin: .ps1 → false" {
  run is_linux_bin "Invoke-Thing.ps1"
  [ "$status" -eq 1 ]
}

# ─── trim ────────────────────────────────────────────────────────────────────
@test "trim: strips surrounding whitespace" {
  run trim "   hello world   "
  [ "$output" = "hello world" ]
}

@test "trim: no-op on already-trimmed string" {
  run trim "tool"
  [ "$output" = "tool" ]
}
