# ci-hub

Self-hosted SonarQube Community Build for the homelab. Native install (no
Docker) so it runs cleanly inside an unprivileged Proxmox LXC.

Full design and rationale: [kuchmenko/ci-hub#1](https://github.com/kuchmenko/ci-hub/issues/1).

## Install

On a fresh Debian 12 LXC or VM, as root:

```
curl -fsSL https://raw.githubusercontent.com/kuchmenko/ci-hub/main/install.sh | sh
```

~5 minutes. SonarQube on `http://<HOST_IP>:9000`. First login is
`admin` / `admin` — rotate immediately.

### Prereq for LXC

`vm.max_map_count` must be ≥ 262144 on the **Proxmox host** (LXC inherits it
from the host kernel; you cannot set it from inside the container):

```
echo 'vm.max_map_count=262144' > /etc/sysctl.d/99-sonarqube.conf
sysctl --system
```

## What install.sh does

1. `apt install postgresql-15 openjdk-17-jre-headless unzip wget curl`.
2. Generates a random Postgres password into `/opt/ci-hub/.env`.
3. Creates `sonarqube` PG role + DB.
4. Downloads SonarQube Community Build to `/opt/sonarqube`.
5. Creates the `sonarqube` system user.
6. Writes `/opt/sonarqube/conf/sonar.properties` (JDBC, web host/port).
7. Writes `/etc/systemd/system/sonarqube.service`.
8. `systemctl enable --now sonarqube`.
9. Polls `/api/system/status` until UP (or warns at 10 min).

## Operations

| Action | Command |
|---|---|
| Status | `systemctl status sonarqube` |
| Logs (live) | `journalctl -u sonarqube -f` |
| App logs | `tail -f /opt/sonarqube/logs/web.log` |
| Restart | `systemctl restart sonarqube` |
| Re-run installer (idempotent) | `curl ... \| sh` again |

## Connecting a GitHub Actions runner

Self-hosted runner sends scan results to SQ via the analysis token:

1. SQ UI → your avatar → My Account → Security → Generate Tokens → type
   `Project Analysis Token`. Copy the token.
2. GitHub repo → Settings → Secrets and variables → Actions → New repo secret:
   - `SONAR_TOKEN` = the token
3. Workflow step:
   ```yaml
   - uses: sonarsource/sonarqube-scan-action@v3
     env:
       SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
       SONAR_HOST_URL: http://<HOST_IP>:9000
   ```

## Remote access (optional)

LAN-only out of the box. To reach from outside the LAN, add one of these —
neither requires touching the install:

- **Tailscale** — install on this host and your devices; reach via magic DNS.
- **Cloudflare Tunnel** — run `cloudflared` pointing at `:9000`, expose at
  `https://sonar.<your-domain>`. Optionally gate with Cloudflare Access.

## Layout

| Path | Purpose |
|---|---|
| `install.sh` | One-shot installer (POSIX sh) |
| `/opt/ci-hub/.env` | Generated Postgres password (gitignored if ever committed back) |
| `/opt/sonarqube/` | SonarQube install root |
| `/etc/systemd/system/sonarqube.service` | Systemd unit |

## Reset

```
systemctl disable --now sonarqube postgresql
rm -rf /opt/sonarqube /opt/ci-hub /etc/systemd/system/sonarqube.service
sudo -u postgres dropdb sonarqube
sudo -u postgres dropuser sonarqube
apt purge -y postgresql-15 openjdk-17-jre-headless
```
