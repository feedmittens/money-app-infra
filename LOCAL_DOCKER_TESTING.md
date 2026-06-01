# Local Docker Compose Testing on macOS

## Quick Start

```bash
# Navigate to the infra repo
cd money-app-infra

# Create test config from example
cp docker/.env.example .env.docker

# Start everything
docker-compose up --build
```

Open **https://localhost:8080** in your browser

## Testing Workflow

### Frontend changes
```bash
docker-compose up --build
```

### API changes
```bash
docker-compose restart api
```

### Database changes
```bash
docker-compose down -v
docker-compose up --build
```

### View logs
```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f api
docker-compose logs -f postgres
```

## When you open a PR

1. GitHub Actions automatically builds the Docker image
2. Starts all services in a container
3. Runs health checks (API responds, database connects)
4. Posts results to your PR
5. Merge when passing!

## Environment Variables

Default values work for local testing. Edit `.env.docker` if needed:

| Variable | Default | Purpose |
|----------|---------|---------|
| `DB_PASSWORD` | `changeme` | PostgreSQL password |
| `NODE_ENV` | `production` | Node.js environment |
| `APP_PORT` | `8080` | Port to run app on |
| `SSL_MODE` | `selfsigned` | SSL type (selfsigned/letsencrypt/none) |
| `DOMAIN` | `localhost` | Domain for certificates |
| `SESSION_SECRET` | auto-generated | Session encryption key |
| `GOOGLE_CLIENT_ID` | empty | OAuth (optional) |
| `GOOGLE_CLIENT_SECRET` | empty | OAuth (optional) |

## Troubleshooting

### Port already in use?
```bash
APP_PORT=9000 docker-compose up
```

### Database error?
```bash
docker-compose restart postgres
```

### Full reset?
```bash
docker-compose down -v && docker-compose up --build
```

### SSL certificate warnings?
This is normal for self-signed certificates in development.

**macOS**: Add certificate to Keychain:
```bash
# Extract certificate
docker-compose exec api cat /etc/nginx/ssl/money-app.crt > /tmp/money-app.crt

# Add to Keychain
security add-certificates -k ~/Library/Keychains/login.keychain /tmp/money-app.crt
```

Or just click through the browser warning.

## Workflow Overview

1. **Local Testing** → `docker-compose up` on your Mac
2. **Push to Feature Branch** → Create PR
3. **GitHub Actions Tests** → Auto-validates in Ubuntu container
4. **Tests Pass** → Merge to main
5. **Production Deploy** → Later use `bash lxc-setup.sh` for Proxmox

## Next Steps

- ✅ Test locally: `docker-compose up --build`
- ✅ Push feature branch when ready
- ✅ Open PR → GitHub Actions validates automatically
- ✅ Merge when all checks pass
- ✅ Deploy to Proxmox later via existing scripts
