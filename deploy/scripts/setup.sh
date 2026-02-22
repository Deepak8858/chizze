#!/bin/bash
# ══════════════════════════════════════════
# Chizze — Initial Server Setup Script
# ══════════════════════════════════════════
# Run on a fresh Ubuntu 22.04+ VPS
# Usage: bash setup.sh
# ══════════════════════════════════════════

set -euo pipefail

echo "═══════════════════════════════════════"
echo "  Chizze Server Setup"
echo "═══════════════════════════════════════"

# ─── 1. System Updates ───
echo "→ Updating system packages..."
apt-get update && apt-get upgrade -y

# ─── 2. Install Docker ───
echo "→ Installing Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    echo "  ✓ Docker installed"
else
    echo "  ✓ Docker already installed"
fi

# ─── 3. Install Docker Compose ───
echo "→ Installing Docker Compose..."
if ! command -v docker compose &> /dev/null; then
    apt-get install -y docker-compose-plugin
    echo "  ✓ Docker Compose installed"
else
    echo "  ✓ Docker Compose already installed"
fi

# ─── 4. Create application directory ───
echo "→ Setting up application directory..."
mkdir -p /opt/chizze
cd /opt/chizze

# ─── 5. Firewall ───
echo "→ Configuring firewall..."
if command -v ufw &> /dev/null; then
    ufw allow 22/tcp    # SSH
    ufw allow 80/tcp    # HTTP
    ufw allow 443/tcp   # HTTPS
    ufw --force enable
    echo "  ✓ Firewall configured (22, 80, 443)"
fi

# ─── 6. Fail2ban ───
echo "→ Installing fail2ban..."
apt-get install -y fail2ban
systemctl enable fail2ban
systemctl start fail2ban
echo "  ✓ fail2ban installed"

# ─── 7. Swap (for low-memory VPS) ───
if [ ! -f /swapfile ]; then
    echo "→ Creating 2GB swap..."
    fallocate -l 2G /swapfile
    chmod 600 /swapfile
    mkswap /swapfile
    swapon /swapfile
    echo '/swapfile none swap sw 0 0' >> /etc/fstab
    echo "  ✓ Swap created"
fi

# ─── 8. Sysctl tuning ───
echo "→ Applying sysctl optimizations..."
cat >> /etc/sysctl.conf << 'EOF'
# Chizze production tuning
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.core.rmem_max = 16777216
net.core.wmem_max = 16777216
vm.overcommit_memory = 1
fs.file-max = 65535
EOF
sysctl -p
echo "  ✓ Sysctl tuned"

# ─── 9. Create deploy user ───
echo "→ Creating deploy user..."
if ! id "deploy" &>/dev/null; then
    useradd -m -s /bin/bash deploy
    usermod -aG docker deploy
    mkdir -p /home/deploy/.ssh
    cp /root/.ssh/authorized_keys /home/deploy/.ssh/ 2>/dev/null || true
    chown -R deploy:deploy /home/deploy/.ssh
    chown -R deploy:deploy /opt/chizze
    echo "  ✓ Deploy user created"
else
    echo "  ✓ Deploy user already exists"
fi

echo ""
echo "═══════════════════════════════════════"
echo "  ✅ Server setup complete!"
echo "═══════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. Copy deploy/ directory to /opt/chizze/"
echo "  2. Copy .env.example to .env.prod and fill in values"
echo "  3. Set up SSL: ./ssl-setup.sh"
echo "  4. Start: docker compose -f docker-compose.prod.yml up -d"
