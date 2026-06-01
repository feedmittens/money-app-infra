# Local Docker Compose Testing on macOS

## Quick Start

```bash
# Clone the infra repo
cd money-app-infra

# Create test config
cp docker/.env.example .env.docker

# Start everything
docker-compose up --build
