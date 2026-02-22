# Chizze — Deploy Directory

Production deployment configuration for the Chizze food delivery platform.

## Directory Structure

```
deploy/
├── docker-compose.prod.yml   # Production Docker Compose
├── .env.example              # Environment template (copy to .env.prod)
├── nginx/
│   ├── nginx.conf            # Nginx reverse proxy config
│   └── proxy_params.conf     # Shared proxy parameters
└── scripts/
    ├── setup.sh              # Initial server setup (run once)
    ├── ssl-setup.sh          # SSL certificate setup (Let's Encrypt)
    └── deploy.sh             # Manual deploy with rollback
```

## Quick Start

### 1. Server Setup (one-time)
```bash
scp -r deploy/ user@server:/opt/chizze/
ssh user@server "cd /opt/chizze && bash scripts/setup.sh"
```

### 2. SSL Certificate
```bash
ssh user@server "cd /opt/chizze && bash scripts/ssl-setup.sh api.devdeepak.me"
```

### 3. Configure Environment
```bash
ssh user@server "cd /opt/chizze && cp .env.example .env.prod && nano .env.prod"
```

### 4. Deploy
```bash
# Via CI/CD (recommended):
git push origin main

# Manual:
ssh user@server "cd /opt/chizze && bash scripts/deploy.sh latest"
```

### 5. Monitor
```bash
# View logs
ssh user@server "cd /opt/chizze && docker compose -f docker-compose.prod.yml logs -f"

# Check health
curl https://api.devdeepak.me/health/ready
```

## GitHub Secrets Required

| Secret | Description |
|---|---|
| `DEPLOY_HOST` | Server IP/hostname |
| `DEPLOY_USER` | SSH username (deploy) |
| `DEPLOY_SSH_KEY` | SSH private key |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded .jks keystore |
| `ANDROID_KEYSTORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_ALIAS` | Key alias (chizze) |
| `ANDROID_KEY_PASSWORD` | Key password |
