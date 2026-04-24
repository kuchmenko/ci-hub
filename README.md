# ci-hub

Self-hosted CI + static analysis pipeline for the homelab. SonarQube
Community Build with unified SARIF output across TypeScript, Python, Go,
and Rust, plus two ephemeral GitHub Actions runners (DinD-isolated).

Full design and rationale: [kuchmenko/ci-hub#1](https://github.com/kuchmenko/ci-hub/issues/1).

## Install

On a fresh Debian 12 VM:

```
curl -fsSL https://raw.githubusercontent.com/kuchmenko/ci-hub/main/install.sh | sudo sh
```

Takes ~3 minutes. SonarQube comes up on `http://<VM_IP>:9000`. First login
is `admin` / `admin` — rotate the password immediately.

Want to inspect before running:

```
curl -fsSL https://raw.githubusercontent.com/kuchmenko/ci-hub/main/install.sh -o install.sh
less install.sh
sudo sh install.sh
```

## What install.sh does

1. Installs Docker CE and git (idempotent).
2. Sets `vm.max_map_count=262144` for SonarQube's embedded Elasticsearch.
3. Clones this repo to `/opt/ci-hub`.
4. Generates a random Postgres password into `/opt/ci-hub/.env`.
5. `docker compose -f compose.minimal.yml up -d` — postgres + sonarqube.

## Runners (Phase 4+)

Edit `/opt/ci-hub/.env`, add a GitHub PAT with `repo` and `workflow` scopes:

```
GITHUB_PAT=ghp_xxx
```

Then:

```
cd /opt/ci-hub
docker compose -f compose.yml up -d
```

This brings up Trivy + 2× GitHub Actions runners in DinD sidecars.

## Remote access (optional)

Not needed for LAN access. For remote, add one of these later without
touching the compose topology:

- **Tailscale**: install on VM and your devices. Access via magic DNS.
- **Cloudflare Tunnel**: run `cloudflared` alongside SQ, tunnel `:9000` to
  `https://sonar.<your-domain>`. Optionally gate with Cloudflare Access.

Either gives TLS + external access.

## Layout

| Path | Purpose |
|---|---|
| `install.sh` | Curl-installable entry point |
| `compose.minimal.yml` | Hub only: postgres + sonarqube |
| `compose.yml` | `include:`s minimal, adds trivy + 2× runner/dind |
| `.env` | Generated at install time; contains passwords; gitignored |

## Non-goals

Public-repo / fork-PR execution. HA. GHAS / CodeQL on private repos.
Registry caches. TLS in MVP. Single Proxmox node is a SPOF, accepted.
