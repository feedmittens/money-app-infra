# money-app-infra

Deployment scripts for [money-app](https://github.com/feedmittens/money-app) on Proxmox. Creates a Debian 12 LXC container, installs Node.js and Nginx, builds and starts the app, and optionally provisions a Let's Encrypt SSL certificate — all in one command.

## Overview

```
Your machine                    Proxmox host
┌──────────────────┐            ┌─────────────────────────────────────┐
│ lxc-setup.sh     │  SSH ───▶  │  LXC container (Debian 12)          │
│ deploy.sh        │            │  ├── Nginx  (static files + proxy)   │
│ config.env       │            │  ├── Node.js API (port 3001)         │
└──────────────────┘            │  └── /opt/money-app (git clone)      │
                                └─────────────────────────────────────┘
```

`lxc-setup.sh` is a one-time setup. After that, use `deploy.sh` whenever you push changes to money-app.

**`config.env` contains your private server details and is gitignored — it stays on your machine only.** Never commit it.

## Prerequisites

- A Proxmox host accessible via SSH
- SSH key auth set up for the Proxmox root user
- `bash` and `scp` on your local machine (standard on Linux/macOS)

For SSL, you additionally need:
- A domain name with an A record pointing to your public IP
- Ports 80 and 443 forwarded from your router to the LXC container's IP

## Quick start

**1. Clone this repo**

```bash
git clone https://github.com/feedmittens/money-app-infra.git
cd money-app-infra
```

**2. Create your config**

```bash
cp config.env.example config.env
nano config.env   # fill in your Proxmox host IP, container settings, etc.
```

**3. Run setup**

```bash
bash lxc-setup.sh
```

Takes about 2 minutes. Prints the URL when done.

**To tear down and rebuild an existing container from scratch:**

```bash
bash lxc-setup.sh --recreate
```

This stops and destroys the existing container (CT_ID from config.env), then creates a fresh one. Useful after major infrastructure changes.

## config.env reference

| Variable | Required | Description |
|---|---|---|
| `PROXMOX_HOST` | Yes | IP or hostname of your Proxmox node |
| `PROXMOX_USER` | Yes | SSH user (usually `root`) |
| `PROXMOX_SSH_KEY` | No | Path to SSH key — leave blank to use ssh-agent default |
| `CT_ID` | Yes | LXC container ID — pick any unused number (check in Proxmox UI) |
| `CT_HOSTNAME` | Yes | Hostname shown in Proxmox UI |
| `CT_STORAGE` | Yes | Storage pool for the container rootfs (e.g. `local-lvm`, `local-zfs`) |
| `CT_BRIDGE` | Yes | Network bridge (almost always `vmbr0`) |
| `CT_CORES` | Yes | CPU cores to assign |
| `CT_MEMORY` | Yes | RAM in MB — 1024 recommended (Node.js runs in production) |
| `CT_IP` | Yes | `dhcp` for automatic, or a static IP like `192.168.1.200/24` |
| `CT_GW` | No | Gateway IP — only needed when `CT_IP` is static |
| `APP_REPO` | Yes | Git URL for money-app |
| `APP_PORT` | Yes | Port for plain HTTP (only used when `SSL_MODE=none`) |
| `SSL_MODE` | No | `selfsigned` (default), `letsencrypt`, or `none` |
| `DOMAIN` | No | Domain name — required for `letsencrypt`; optional CN for `selfsigned` |
| `CERTBOT_EMAIL` | No | Email for Let's Encrypt notifications — required for `letsencrypt` |

**Finding your CT_STORAGE value:** In the Proxmox web UI go to Datacenter → Storage. The name in the ID column is what to use. Common values: `local-lvm` (LVM-thin), `local-zfs` (ZFS), `local` (directory storage).

## SSL modes

### Self-signed (default)

Works on any network — no domain, no internet access required. Ideal for internal or air-gapped servers.

```bash
SSL_MODE=selfsigned   # this is already the default, no change needed
```

Setup generates a 10-year RSA certificate with the container's IP as a SAN. Nginx listens on 443 and redirects port 80 to HTTPS automatically. Your browser will show a one-time security warning — click through it, or add the certificate to your OS/browser trust store for a cleaner experience.

After setup, fetch the cert to import into your browser or OS:

```bash
ssh root@<PROXMOX_HOST> "pct exec <CT_ID> -- cat /etc/nginx/ssl/money-app.crt"
```

### Let's Encrypt

For servers with a public domain and internet access. Issues a fully trusted certificate with automatic renewal.

```bash
SSL_MODE=letsencrypt
DOMAIN=money.yourdomain.com
CERTBOT_EMAIL=you@yourdomain.com
```

**Router setup required:** Forward ports **80** and **443** from your router to the container's IP.

Certbot installs a systemd timer for automatic renewal every 60 days — no manual intervention needed.

### Plain HTTP

```bash
SSL_MODE=none
APP_PORT=8080
```

No HTTPS. Access via `http://<container-ip>:8080`.

## Deploying updates

After pushing changes to money-app:

```bash
cd money-app-infra
bash deploy.sh
```

This pulls the latest code, updates dependencies, rebuilds the frontend, restarts the API server, and reloads Nginx. Takes about 30 seconds.

## Cleaning up

To destroy the container and start fresh:

```bash
bash lxc-setup.sh --recreate
```

Or manually on the Proxmox host:

```bash
ssh root@<PROXMOX_HOST>
pct stop <CT_ID>
pct destroy <CT_ID> --purge
```

Then re-run `bash lxc-setup.sh`.

## What the scripts do

### `lxc-setup.sh` (one-time)

1. SSHes into Proxmox
2. Optionally destroys an existing container (`--recreate`)
3. Downloads a Debian 12 LXC template (cached after first use)
4. Creates and starts the container
5. Uploads `scripts/container-init.sh` into the container
6. Runs the init script, which:
   - Installs Nginx and Node.js 22
   - Clones money-app from GitHub
   - Installs client and server dependencies
   - Builds the React frontend
   - Starts the Express API server as a systemd service (port 3001)
   - Configures Nginx to serve static files and proxy `/api/` to the API server
   - (Optional) Runs certbot for Let's Encrypt SSL

### `deploy.sh` (run on each update)

1. Uploads `scripts/container-deploy.sh` into the running container
2. Runs it, which:
   - Pulls latest code from GitHub
   - Updates client and server dependencies
   - Rebuilds the frontend
   - Restarts the API server
   - Reloads Nginx

---

## FAQ

**Do I need a GitHub account or any tokens?**
No. Both repos are public. The scripts clone over HTTPS with no authentication required.

**Which Proxmox version does this support?**
Tested on Proxmox VE 7 and 8.

**Can I use a different container ID than 200?**
Yes — set `CT_ID` to any unused number. Check the Proxmox UI (or run `pct list` on the host) to see what's already in use.

**What if my storage isn't `local-lvm`?**
Change `CT_STORAGE` in `config.env` to match your setup. Run `pvesm status` on the Proxmox host to list available storage pools.

**Can I run multiple containers — e.g. staging and production?**
Yes. Use different `CT_ID` values and different `APP_PORT` values (if not using domains).

**How do I update the SSL certificate manually?**
For Let's Encrypt, certbot handles this automatically. To force renewal:
```bash
ssh root@<PROXMOX_HOST> "pct exec <CT_ID> -- certbot renew --force-renewal"
```
For self-signed, the cert is valid for 10 years. Regenerate with the `openssl req` command from `container-init.sh`, then `nginx -s reload`.

**The container got an IP via DHCP — how do I find it?**
```bash
ssh root@<PROXMOX_HOST> "pct exec <CT_ID> -- hostname -I"
```
Or check the Summary tab in the Proxmox UI.

**My browser doesn't trust the self-signed certificate — how do I fix it?**
Fetch the `.crt` file and import it into your OS/browser trust store:
- **Linux (Chrome/Firefox):** Import into your browser's certificate manager under Authorities
- **macOS:** Double-click the `.crt` → add to System keychain → set to "Always Trust"
- **Windows:** Double-click the `.crt` → Install Certificate → Local Machine → Trusted Root Certification Authorities

**Can I deploy this somewhere other than Proxmox?**
The container scripts are plain bash and run on any Debian 12 machine:
```bash
APP_PORT=8080 APP_REPO=https://github.com/feedmittens/money-app.git bash scripts/container-init.sh
```

**Why does my config.env not get committed to git?**
On purpose. `config.env` contains your private server IP and credentials. It's in `.gitignore` and should stay on your machine only. The `config.env.example` file in the repo shows the structure without any real values.
