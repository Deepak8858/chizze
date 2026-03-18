# Deploy Chizze Backend & Admin to Google VM
VM: `34.131.63.117` | User: `deepakupkgs` | OS: Ubuntu 24.04 | RAM: 8GB | Disk: 96GB
## Current State
* **Backend**: Go 1.24 (Gin) app with Dockerfile + docker-compose (API + Redis). Runs on port 8080.
* **Admin**: Next.js 16 app. Runs on port 3000.
* **API domain**: `api.devdeepak.me` (from `.env.example`)
* **VM**: Clean Ubuntu, nothing installed.
## Proposed Setup
### 1. VM System Setup
* Install Docker + Docker Compose
* Install Node.js 20 LTS + PM2 (for admin panel)
* Install Nginx (reverse proxy)
* Install Certbot (SSL via Let's Encrypt)
* Configure firewall (UFW: allow 22, 80, 443)
### 2. Backend Deployment
* Copy `backend/` to VM at `/home/deepakupkgs/chizze/backend`
* Copy existing `.env` from local backend to VM
* Run `docker compose up -d` (spins up Go API on :8080 + Redis on :6379)
* Verify health check at `localhost:8080/health`
### 3. Admin Panel Deployment
* Copy `admin/` (excluding `node_modules`, `.next`) to VM at `/home/deepakupkgs/chizze/admin`
* Copy `.env.local` to VM
* `npm install && npm run build` on VM
* Run with PM2: `pm2 start npm --name chizze-admin -- start`
* Verify at `localhost:3000`
### 4. Nginx Reverse Proxy
* Backend: `api.devdeepak.me` → `localhost:8080`
* Admin: `admin.devdeepak.me` (or IP-based) → `localhost:3000`
* Add SSL with Certbot once DNS is pointed to `34.131.63.117`
### 5. Verify
* Health checks for backend and admin
* Test API endpoint externally
