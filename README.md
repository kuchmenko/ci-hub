# ci-hub

Self-hosted CI + static analysis pipeline for the homelab. Target: SonarQube
Community Build with unified SARIF output across TypeScript, Python, Go,
and Rust, plus ephemeral GitHub Actions runners (DinD-isolated).

Full design and rationale: [kuchmenko/ci-hub#1](https://github.com/kuchmenko/ci-hub/issues/1).

## Status

| Component | State |
|---|---|
| One-shot installer (Docker + SonarQube + Postgres) | works |
| SonarQube on LAN (`http://<VM_IP>:9000`) | works |
| Trivy server + runners in `compose.yml` | defined; not yet usable (runner image missing) |
| Reusable CI workflow templates | not started |
| Claude feedback-loop tooling | not started |

The installer brings up SonarQube only. Everything else is scaffolded but
requires missing pieces.

## Install

On a fresh Debian 12 VM:

```
curl -fsSL https://raw.githubusercontent.com/kuchmenko/ci-hub/main/install.sh | sudo sh
```

~3 minutes. SonarQube on `http://<VM_IP>:9000`. First login is
`admin` / `admin` — rotate the password immediately.

Inspect first if you prefer:

```
curl -fsSL https://raw.githubusercontent.com/kuchmenko/ci-hub/main/install.sh -o install.sh
less install.sh
sudo sh install.sh
```

### What install.sh does

1. Installs Docker CE and git (idempotent; skipped if present).
2. Sets `vm.max_map_count=262144` for SonarQube's embedded Elasticsearch.
3. Clones this repo to `/opt/ci-hub`.
4. Generates a random Postgres password into `/opt/ci-hub/.env`.
5. `docker compose -f compose.minimal.yml up -d` — postgres + sonarqube.
6. Waits for SonarQube to report healthy.

### First-run setup in SonarQube UI

1. Rotate the admin password.
2. Generate an analysis token (used later by CI runners).

### Re-running

The installer is idempotent. Re-running on the same VM updates the repo
(`git pull --ff-only`), preserves the existing `.env`, and re-applies
`docker compose up -d`.

## Runners (not yet usable)

`compose.yml` references `ghcr.io/kuchmenko/gh-runner:latest`, which **does
not exist yet**. Before runners can come up, either:

- build the image from a dedicated `runner/Dockerfile` (planned), or
- substitute `myoung34/docker-github-actions-runner:latest` and adjust env
  variable names.

Once the image is available: add a GitHub PAT with `repo` + `workflow`
scopes to `/opt/ci-hub/.env`:

```
GITHUB_PAT=ghp_xxx
```

Then:

```
cd /opt/ci-hub
docker compose -f compose.yml up -d
```

This brings up Trivy + two ephemeral runners in DinD sidecars.

## Remote access (optional)

LAN-only out of the box. To reach SonarQube from outside the LAN, add one
of these — neither changes the compose topology:

- **Tailscale**: install on the VM and your devices; reach the VM via
  magic DNS. Simplest for personal use.
- **Cloudflare Tunnel**: run `cloudflared` alongside SQ, tunnel `:9000`
  to `https://sonar.<your-domain>`. Optionally gate with Cloudflare
  Access for SSO/email auth.

Both give TLS + external access without TLS work on this side.

## Layout

| Path | Purpose |
|---|---|
| `install.sh` | POSIX curl-installable entry point |
| `compose.minimal.yml` | Hub only: postgres + sonarqube |
| `compose.yml` | `include:`s minimal, adds trivy + 2× runner/dind |
| `.env` | Generated at install time; contains the Postgres password; gitignored |

## Reset

To wipe a VM back to pre-install state:

```
cd /opt/ci-hub
docker compose -f compose.yml down -v   # -v removes volumes (SQ data + PG data)
rm -rf /opt/ci-hub
```

Docker CE and the `vm.max_map_count` sysctl stay installed — remove those
manually if needed.

## Non-goals

Public-repo or fork-PR execution. HA. GHAS / CodeQL on private repos.
Registry caches (Verdaccio / devpi / Athens). TLS in MVP. Single Proxmox
node SPOF, accepted.
