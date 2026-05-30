# money-app-infra — Claude context

Deployment scripts for money-app on Proxmox LXC. Public repo: https://github.com/feedmittens/money-app-infra  
App repo: https://github.com/feedmittens/money-app (local: `/home/bvogel/money-app`)

## What lives here

```
lxc-setup.sh              One-time container creation (run from local machine via SSH)
deploy.sh                 Push updates to running container
scripts/container-init.sh Runs inside container on first setup
scripts/container-deploy.sh Runs inside container on each update
config.env.example        Template — commit this
config.env                PRIVATE — gitignored, never commit
```

## config.env (local only, never commit)

Contains the real Proxmox host IP, container ID, network config, and SSL settings.  
Location: `/home/bvogel/money-app-infra/config.env` — see `config.env.example` for the schema.

## What the container runs

- **Nginx** — serves `client/dist/` as static files; proxies `/api/` → `http://127.0.0.1:3001`
- **money-app-api** — systemd service running `node server/server.js` on port 3001
- App cloned to `/opt/money-app`

## Common operations

```bash
# First-time setup
bash lxc-setup.sh

# Destroy container 200 and rebuild from scratch
bash lxc-setup.sh --recreate

# Deploy after pushing to money-app
bash deploy.sh
```

## Rules

- **Public repo** — no IPs, credentials, tokens, or personal info in any committed file
- All private config belongs in `config.env` (gitignored)
- Any infra change must be reflected in both scripts AND the README
- Any change to `money-app` that affects deployment (nginx config, new services, deps) must also update the scripts here
