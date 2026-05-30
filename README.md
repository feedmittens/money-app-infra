# money-app-infra

Deployment scripts for [money-app](https://github.com/feedmittens/money-app) on Proxmox. Creates a Debian 12 LXC container, installs Node.js and Nginx, builds the app, and optionally provisions a Let's Encrypt SSL certificate — all in one command.

## Overview

```
Your machine                    Proxmox host
┌──────────────────┐            ┌─────────────────────────────────┐
│ lxc-setup.sh     │  SSH ───▶  │  LXC container (Debian 12)      │
│ deploy.sh        │            │  ├── Nginx  (serves the app)     │
│ config.env       │            │  ├── Node.js (builds the app)    │
└──────────────────┘            │  └── /opt/money-app (git clone)  │
                                └─────────────────────────────────┘
```

`lxc-setup.sh` is a one-time setup. After that, use `deploy.sh` whenever you push changes to money-app.

## Prerequisites

- A Proxmox host accessible via SSH
- SSH key auth set up for the Proxmox root user (password auth also works, you'll just be prompted)
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
| `CT_MEMORY` | Yes | RAM in MB (512 is plenty) |
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

**Router setup required:** Forward ports **80** and **443** from your router to the container's IP. If you're using `CT_IP=dhcp`, set a DHCP reservation in your router so the container always gets the same IP.

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

This pulls the latest code, rebuilds the frontend, and reloads Nginx. Takes about 30 seconds.

## Cleaning up a partial or broken deployment

If setup failed partway through, destroy the container on Proxmox and start fresh:

```bash
ssh root@<PROXMOX_HOST>

pct stop <CT_ID>      # stop it (if running)
pct destroy <CT_ID> --purge   # delete container and its disk
```

Then re-run `bash lxc-setup.sh` from your local machine.

## What the scripts do

### `lxc-setup.sh` (one-time)

1. SSHes into Proxmox
2. Downloads a Debian 12 LXC template (cached after first use)
3. Creates and starts the container
4. Uploads `scripts/container-init.sh` into the container
5. Runs the init script, which:
   - Installs Nginx and Node.js 22
   - Clones money-app from GitHub
   - Builds the React frontend
   - Writes an Nginx config and starts the service
   - (Optional) Runs certbot for Let's Encrypt SSL

### `deploy.sh` (run on each update)

1. Uploads `scripts/container-deploy.sh` into the running container
2. Runs it, which:
   - Pulls latest code from GitHub
   - Rebuilds the frontend
   - Reloads Nginx

---

## FAQ

**Do I need a GitHub account or any tokens?**
No. Both repos are public. The scripts clone over HTTPS with no authentication required.

**Which Proxmox version does this support?**
Tested on Proxmox VE 7 and 8. The scripts use standard `pct` commands that haven't changed across versions.

**Can I use a different container ID than 200?**
Yes — set `CT_ID` to any unused number. Check the Proxmox UI (or run `pct list` on the host) to see what's already in use.

**What if my storage isn't `local-lvm`?**
Change `CT_STORAGE` in `config.env` to match your setup. Run `pvesm status` on the Proxmox host to list available storage pools and their types.

**Can I run multiple containers — e.g. staging and production?**
Yes. Clone this repo twice (or copy `config.env`) with different `CT_ID` values, different `APP_PORT` values (if not using domains), and run `lxc-setup.sh` for each.

**How do I update the SSL certificate manually?**
For Let's Encrypt, certbot handles this automatically via a systemd timer. To force a renewal:
```bash
ssh root@<PROXMOX_HOST> "pct exec <CT_ID> -- certbot renew --force-renewal"
```
For self-signed, the cert is valid for 10 years. To regenerate it manually, run the same `openssl req` command from `container-init.sh` inside the container, then `nginx -s reload`.

**My browser doesn't trust the self-signed certificate — how do I fix it?**
Fetch the `.crt` file from the container and import it into your OS/browser trust store:
- **Linux (Chrome/Firefox):** Import into your browser's certificate manager under Authorities
- **macOS:** Double-click the `.crt` and add it to the System keychain, then set it to "Always Trust"
- **Windows:** Double-click the `.crt` → Install Certificate → Local Machine → Trusted Root Certification Authorities

**The container got an IP via DHCP — how do I find it?**
```bash
ssh root@<PROXMOX_HOST> "pct exec <CT_ID> -- hostname -I"
```
Or check the Proxmox web UI — it shows the container IP on the Summary tab once it's running.

**Can I deploy this somewhere other than Proxmox?**
The container-init and container-deploy scripts are plain bash and will run on any Debian 12 machine. You can run them directly (without `pct exec`) on any VPS or VM:
```bash
APP_PORT=8080 APP_REPO=https://github.com/feedmittens/money-app.git bash scripts/container-init.sh
```
