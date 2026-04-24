#!/usr/bin/env bash
# One-shot installer for ci-hub. Intended for `curl | sudo bash` on a fresh
# Debian 12 VM.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/kuchmenko/ci-hub/main/install.sh \
#     | sudo bash
#
# With overrides:
#   curl -fsSL https://raw.githubusercontent.com/kuchmenko/ci-hub/main/install.sh \
#     | sudo INSTALL_DIR=/opt/ci-hub BRANCH=main bash
#
# What this does:
#   1. Installs git if missing.
#   2. Clones the ci-hub repo at $INSTALL_DIR (default: /opt/ci-hub).
#   3. Hands off to scripts/bootstrap-vm.sh, which installs Docker CE,
#      sops, age; decrypts secrets/*.age; brings up compose.minimal.yml.
#
# What it does NOT do (prerequisites you must provide):
#   - An age private key at /root/.age/key.txt (mode 0400), and the matching
#     public key pasted into .sops.yaml so secrets/*.age can be decrypted.
#   - The initial secrets/postgres_password.age (encrypted with sops/age).
#
# Safety note:
#   Piping an unreviewed script into sudo bash is a real footgun. If you do
#   not trust this repo, download install.sh first, read it, then run it:
#     curl -fsSL https://raw.githubusercontent.com/kuchmenko/ci-hub/main/install.sh -o install.sh
#     less install.sh
#     sudo bash install.sh

set -euo pipefail

: "${INSTALL_DIR:=/opt/ci-hub}"
: "${BRANCH:=main}"
: "${REPO_URL:=https://github.com/kuchmenko/ci-hub.git}"

log()  { printf '[install] %s\n' "$*"; }
warn() { printf '[install] %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root: pipe into 'sudo bash'"

if [[ ! -f /etc/os-release ]]; then
    die "/etc/os-release not found — cannot determine OS"
fi
# shellcheck source=/dev/null
. /etc/os-release
if [[ "${ID:-}" != "debian" || "${VERSION_CODENAME:-}" != "bookworm" ]]; then
    warn "tested only on Debian 12 (bookworm); detected ${ID:-?} ${VERSION_CODENAME:-?}"
fi

if ! command -v git >/dev/null 2>&1; then
    log "Installing git..."
    apt-get update -qq
    apt-get install -y -qq git
fi

if [[ -d "$INSTALL_DIR/.git" ]]; then
    log "Updating existing checkout at $INSTALL_DIR (branch: $BRANCH)..."
    git -C "$INSTALL_DIR" fetch --quiet origin "$BRANCH"
    git -C "$INSTALL_DIR" checkout --quiet "$BRANCH"
    git -C "$INSTALL_DIR" pull --ff-only --quiet origin "$BRANCH"
elif [[ -e "$INSTALL_DIR" ]]; then
    die "$INSTALL_DIR exists but is not a git repo — move it aside first"
else
    log "Cloning $REPO_URL into $INSTALL_DIR (branch: $BRANCH)..."
    git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"
log "Handing off to scripts/bootstrap-vm.sh..."
exec ./scripts/bootstrap-vm.sh
