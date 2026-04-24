#!/usr/bin/env bash
# Idempotent bootstrap for the Proxmox VM hosting ci-hub.
#
# Installs Docker CE, sops/age, decrypts secrets/*.age, and brings up the
# minimal analysis hub (postgres + sonarqube). SonarQube is published on
# :9000 on the VM IP — access from the LAN via http://<VM_IP>:9000.
#
# Runs on: Debian 12 VM (this machine, as root).
# Prerequisites:
#   - age private key at /root/.age/key.txt (mode 0400)
#   - .sops.yaml updated with the matching public key
#   - secrets/postgres_password.age encrypted to that pubkey
#
# What this does NOT do:
#   - create or configure the Proxmox VM
#   - generate the age key (use `age-keygen`; back up to password manager)
#   - start the full stack with runners (`docker compose up -d`, Phase 4+)

set -euo pipefail

log()  { printf '[+] %s\n' "$*"; }
warn() { printf '[!] %s\n' "$*" >&2; }
die()  { warn "$*"; exit 1; }

[[ $EUID -eq 0 ]] || die "must run as root (sudo)"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

# ---- 1. Docker CE from docker.com (not Debian's outdated docker.io) ----

if command -v docker >/dev/null 2>&1; then
    log "Docker already installed: $(docker --version)"
else
    log "Installing Docker CE..."
    apt-get update -qq
    apt-get install -y -qq ca-certificates curl gnupg

    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/debian/gpg \
        | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    codename="$(. /etc/os-release && echo "$VERSION_CODENAME")"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/debian $codename stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update -qq
    apt-get install -y -qq docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
    systemctl enable --now docker
    log "Docker installed: $(docker --version)"
fi

# ---- 2. SonarQube kernel tunable ----
# SQ's embedded Elasticsearch refuses to start if vm.max_map_count < 262144.
if [[ "$(sysctl -n vm.max_map_count)" -lt 262144 ]]; then
    log "Setting vm.max_map_count=262144 (persistent)..."
    echo 'vm.max_map_count=262144' > /etc/sysctl.d/99-sonarqube.conf
    sysctl -p /etc/sysctl.d/99-sonarqube.conf >/dev/null
fi

# ---- 3. sops + age toolchain ----

if ! command -v age >/dev/null 2>&1; then
    log "Installing age..."
    apt-get install -y -qq age
fi

if ! command -v sops >/dev/null 2>&1; then
    sops_ver="v3.8.1"
    arch="$(dpkg --print-architecture)"
    log "Installing sops ${sops_ver} (${arch})..."
    curl -fsSL -o /usr/local/bin/sops \
        "https://github.com/getsops/sops/releases/download/${sops_ver}/sops-${sops_ver}.linux.${arch}"
    chmod +x /usr/local/bin/sops
fi

# ---- 4. Age key check ----

age_key="/root/.age/key.txt"
if [[ ! -f "$age_key" ]]; then
    cat <<EOF >&2

[!] ERROR: $age_key not found.

The age key is required to decrypt secrets in secrets/*.age.

Options:
  1. Restore from password-manager backup:
       install -m 0400 -o root -g root /path/to/key.txt $age_key

  2. Generate a new key on this host:
       mkdir -p /root/.age && chmod 0700 /root/.age
       age-keygen -o $age_key
       chmod 0400 $age_key
     Then, on a dev workstation, replace the recipient in .sops.yaml with
     the printed public key and re-encrypt every secret:
       sops updatekeys secrets/*.age

Aborting.
EOF
    exit 1
fi

if [[ "$(stat -c %a "$age_key")" != "400" ]]; then
    warn "$age_key has permissive mode; tightening to 0400"
    chmod 0400 "$age_key"
fi

export SOPS_AGE_KEY_FILE="$age_key"

# ---- 5. Decrypt all secrets/*.age into plain files ----

log "Decrypting secrets..."
shopt -s nullglob
found=0
for enc in secrets/*.age; do
    found=1
    plain="${enc%.age}"
    if sops -d "$enc" > "$plain" 2>/dev/null; then
        chmod 0400 "$plain"
        log "  ✓ $(basename "$plain")"
    else
        die "failed to decrypt $enc (check .sops.yaml recipient and age key)"
    fi
done
[[ $found -eq 1 ]] || die "no secrets/*.age files found — encrypt placeholders first"

# ---- 6. Bring up the minimal hub ----

log "Starting hub services from compose.minimal.yml..."
docker compose -f compose.minimal.yml up -d

log "Waiting for healthchecks (SonarQube takes ~2 minutes on first boot)..."
deadline=$(( $(date +%s) + 300 ))
while :; do
    if docker compose -f compose.minimal.yml ps | grep -q 'sonarqube.*(healthy)'; then
        log "sonarqube is healthy."
        break
    fi
    if [[ $(date +%s) -gt $deadline ]]; then
        warn "SonarQube did not reach healthy state within 5 minutes."
        docker compose -f compose.minimal.yml ps
        die "bootstrap incomplete"
    fi
    sleep 10
done

vm_ip="$(hostname -I | awk '{print $1}')"

cat <<EOF

[+] Bootstrap complete.

SonarQube is listening on http://${vm_ip}:9000

Next steps:
  1. From your LAN, open http://${vm_ip}:9000 in a browser.
  2. Log in as admin / admin, rotate the password immediately. Encrypt the
     new one into secrets/sq_admin_password.age and commit.
  3. In SQ UI: generate an analysis token. Encrypt into
     secrets/sq_analysis_token.age.
  4. Create and mark default the "homelab-default" quality gate
     (see issue #1 Phase 3).
  5. Once gh_runner_pat is provisioned: \`docker compose up -d\` brings up
     the full stack including runners (Phase 4+).

Remote access (optional, later):
  - Tailscale: install on VM + your laptop/phone, access via magic DNS.
  - Cloudflare Tunnel: cloudflared container alongside SQ, tunnels SQ:9000
    to https://sonar.<your-domain>, optionally gate with CF Access.

EOF
