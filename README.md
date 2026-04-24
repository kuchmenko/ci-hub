# ci-hub

Self-hosted CI + static analysis pipeline for the homelab. Two ephemeral
GitHub Actions runners (DinD-isolated) plus SonarQube Community Build with
unified SARIF output across TypeScript, Python, Go, and Rust.

Full design and rationale: [kuchmenko/ci-hub#1](https://github.com/kuchmenko/ci-hub/issues/1).

## Architecture (short form)

Single Debian 12 VM on Proxmox. **VM over LXC by choice** — supply-chain
threat model (malicious `build.rs`, `postinstall`, `setup.py`) wants a
hypervisor boundary, not a shared kernel. See issue #1 Subsystem 1 for the
attack-surface reasoning.

Everything runs on the default Docker bridge inside the VM. SonarQube
publishes `:9000` on the VM IP — access from the LAN via
`http://<VM_IP>:9000`. Runners reach SQ internally over Docker DNS
(`http://sonarqube:9000`).

**No TLS in the MVP.** Access is LAN-only to a machine you control.
HTTPS/remote access is additive: drop in a Tailscale daemon or a Cloudflare
Tunnel later without touching the hub topology.

Runners use a DinD sidecar per runner, not a host-socket bind. A compromised
job can harm the sidecar namespace only; the sibling hub is unreachable from
the job's kernel perspective, though they share the Docker bridge at the
network layer.

## Status

Phase 2 (compose scaffold) in progress. Later phases track issue #1 checklist.

| Phase | State |
|---|---|
| 0 Defaults sign-off | pending |
| 1 VM bootstrap | VM created, Docker not yet installed |
| 2 Compose scaffold | **in progress** |
| 3 Analysis hub online | blocked on Phase 2 |
| 4–9 | blocked |

## Quickstart

On the Proxmox VM (Debian 12, root shell):

```bash
# Install the age private key (restored from password-manager backup)
install -m 0400 -o root -g root /path/to/age-key.txt /root/.age/key.txt

# Clone the repo (secrets must already be encrypted to the matching pubkey)
git clone git@github.com:kuchmenko/ci-hub.git /opt/ci-hub
cd /opt/ci-hub

# Install Docker CE, decrypt secrets, bring up the analysis hub.
sudo ./scripts/bootstrap-vm.sh
```

After SonarQube reports healthy, open `http://<VM_IP>:9000` from your LAN:

1. Log in as `admin` / `admin`, rotate the password. Encrypt the new one
   into `secrets/sq_admin_password.age` and commit.
2. Generate a scoped analysis token in the SQ UI; encrypt into
   `secrets/sq_analysis_token.age`.
3. Define the `homelab-default` quality gate (issue #1 Phase 3) and mark it
   as the instance default.

Runners, Trivy server, and the full stack are Phase 4+
(`docker compose up -d` on `compose.yml` once `gh_runner_pat` is provisioned).

## Remote access (optional, later)

Nothing in this repo blocks it — add whichever of these fits:

- **Tailscale**: install on the VM and your laptop/phone. Access SQ on the
  VM's tailnet IP. No port changes.
- **Cloudflare Tunnel**: add a `cloudflared` service alongside SQ, tunnels
  `sonarqube:9000` out to `https://sonar.<your-domain>`. Optionally gate
  with Cloudflare Access for email/SSO auth.

Either gives you TLS + external access. Neither requires rethinking the
compose topology.

## Secrets

Encrypted with SOPS + age. The age private key lives on the Proxmox VM only,
at `/root/.age/key.txt` (mode 0400); back it up to a password manager.
Losing both the host and the backup means re-provisioning every secret.

| File | Purpose |
|---|---|
| `secrets/postgres_password.age` | SonarQube → Postgres auth |
| `secrets/sq_admin_password.age` | SonarQube UI admin login (post-rotation) |
| `secrets/sq_analysis_token.age` | `sonar-scanner` CLI auth (project-scoped) |
| `secrets/gh_runner_pat.age` | GitHub PAT (`repo`, `workflow`) for runner registration |

Encrypt a new secret:

```bash
printf 'value' | sops --encrypt --input-type binary --output-type binary \
    --output secrets/postgres_password.age /dev/stdin
```

## Layout

| Path | Purpose |
|---|---|
| `compose.minimal.yml` | Hub only: postgres + sonarqube. Phase 3 bootstrap target. |
| `compose.yml` | `include:`s minimal, adds trivy + 2× runner/dind. Phase 4+. |
| `.sops.yaml` | SOPS/age config. Placeholder recipient until `age-keygen` is run. |
| `scripts/bootstrap-vm.sh` | Install Docker CE, decrypt secrets, bring up minimal hub |

## Non-goals

Public-repo / fork-PR execution. HA. GHAS / CodeQL on private repos.
Registry caches (Verdaccio / devpi / Athens). TLS in the MVP. Single
Proxmox node is a SPOF, accepted.
