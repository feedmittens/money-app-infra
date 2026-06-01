# Local Docker Deployment Guide

This guide explains how to deploy the money-app stack locally using Docker Compose on macOS, Windows, or Linux.

## Prerequisites

- **Docker Desktop** installed ([Download](https://www.docker.com/products/docker-desktop))
- **Git** installed
- The `money-app` repository cloned in the expected location or configured via `APP_REPO`

## Quick Start

### 1. Clone or navigate to the money-app-infra repository

```bash
git clone https://github.com/feedmittens/money-app-infra.git
cd money-app-infra
```

### 2. Set up environment variables

```bash
cp docker/.env.example .env.docker
# Edit .env.docker with your desired settings
```

Key variables:
- `DB_PASSWORD`: PostgreSQL password for the `bvmoney` user
- `APP_PORT`: Port to run the app on (default: 8080)
- `SSL_MODE`: `selfsigned` (default), `letsencrypt`, or `none`
- `DOMAIN`: Domain name (for Let's Encrypt or self-signed cert)
- `GOOGLE_CLIENT_ID`, `GOOGLE_CLIENT_SECRET`: OAuth credentials (optional)

### 3. Start the stack

```bash
docker-compose up --build
```

This will:
- Build the Docker image from the Dockerfile
- Start PostgreSQL (port 5432)
- Apply the database schema
- Start the API server (port 3001)
- Start Nginx (ports 80, 443)

### 4. Access the application

- **HTTPS (self-signed)**: `https://localhost:8080`
- **HTTP redirect**: `http://localhost:8080` → `https://localhost:8080`
- **API**: `https://localhost:8080/api`

### 5. Stopping and cleaning up

```bash
# Stop containers (keeps volumes)
docker-compose down

# Remove everything (volumes, images, containers)
docker-compose down -v
```

## Development Workflow

### Live code changes

The Docker Compose setup mounts the `client` and `server` directories as volumes. For most changes:

1. **Frontend changes**: Will be picked up if you rebuild the image or restart the container
2. **API server changes**: Restart the container: `docker-compose restart api`

### Rebuilding after code changes

```bash
docker-compose up --build
```

### Viewing logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f api
docker-compose logs -f postgres
```

### Running database migrations or commands

```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U bvmoney -d bvmoney

# Run a specific SQL file
docker-compose exec postgres psql -U bvmoney -d bvmoney -f /path/to/file.sql
```

## SSL/TLS Configuration

### Self-Signed Certificate (Default)

The certificate is automatically generated on first run:
- Stored in `/etc/nginx/ssl/money-app.crt` (inside container)
- Valid for 10 years
- Includes localhost and the configured `DOMAIN` (if set)

Your browser will show a security warning. To trust it:
1. Click "Advanced" → "Proceed to localhost (unsafe)" in Chrome/Edge
2. Or add the certificate to your system keychain (macOS)

### Let's Encrypt

Set these in `.env.docker`:
```env
SSL_MODE=letsencrypt
DOMAIN=your-domain.com
CERTBOT_EMAIL=your-email@example.com
```

**Note**: Let's Encrypt requires your domain to be publicly accessible. This won't work for `localhost`.

### No SSL (HTTP only)

```env
SSL_MODE=none
APP_PORT=8080
```

## Troubleshooting

### Ports already in use

If port 8080, 5432, or 443 is already in use:

```bash
# Change APP_PORT in .env.docker
APP_PORT=9000
docker-compose up
```

Then access via `https://localhost:9000`.

### PostgreSQL connection errors

```bash
# Check if postgres is running and healthy
docker-compose ps
docker-compose logs postgres

# Restart postgres
docker-compose restart postgres
```

### Nginx configuration errors

```bash
docker-compose logs api | grep nginx
```

### Volume permission issues (Linux)

If you get permission denied errors:

```bash
# Run as root or adjust permissions
sudo chown -R $USER:$USER .
docker-compose up
```

## Comparing with Proxmox LXC Deployment

| Aspect | Docker Compose (Local) | Proxmox LXC (Production) |
|--------|------------------------|---------------------------|
| **Setup** | `docker-compose up` | `bash lxc-setup.sh` |
| **Database** | PostgreSQL in container | PostgreSQL in container |
| **API Server** | Node.js in container | Node.js in container |
| **Nginx** | In container | In container |
| **SSL Certs** | Auto-generated (self-signed or Let's Encrypt) | Self-signed or Let's Encrypt via certbot |
| **Deployment** | Local Docker Desktop | Remote Proxmox host via SSH |
| **Persistence** | Docker volumes | Container filesystem + Proxmox storage |
| **Updates** | `docker-compose up --build` | `bash deploy.sh` |

Both deployments run the **same initialization logic** from `container-init.sh`, adapted to their respective container runtimes.

## Next Steps

- **For production**: Use the Proxmox deployment (`lxc-setup.sh`)
- **For development**: Use this Docker Compose setup
- **For CI/CD**: Consider extending the Dockerfile for your pipeline

## Support

For issues or questions:
- Check the logs: `docker-compose logs -f`
- Open an issue: [feedmittens/money-app-infra](https://github.com/feedmittens/money-app-infra/issues)
