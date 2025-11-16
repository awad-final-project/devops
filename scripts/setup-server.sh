#!/bin/bash

# Server Initial Setup Script
# This script sets up a fresh server for deployment

set -e

echo "🔧 Setting up server for Mail Application..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root or with sudo${NC}"
    exit 1
fi

# Update system
echo "📦 Updating system packages..."
apt-get update
apt-get upgrade -y
print_status "System updated"

# Install dependencies
echo ""
echo "📦 Installing dependencies..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    git \
    ufw \
    certbot

print_status "Dependencies installed"

# Install Docker
echo ""
echo "🐳 Installing Docker..."

if command -v docker &> /dev/null; then
    print_status "Docker already installed"
else
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    print_status "Docker installed"
fi

# Start Docker service
systemctl start docker
systemctl enable docker
print_status "Docker service enabled"

# Install Docker Compose
echo ""
echo "🐳 Installing Docker Compose..."

if command -v docker compose &> /dev/null; then
    print_status "Docker Compose already installed"
else
    apt-get install -y docker-compose-plugin
    print_status "Docker Compose installed"
fi

# Setup firewall
echo ""
echo "🔥 Configuring firewall..."
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
print_status "Firewall configured (ports 22, 80, 443 open)"

# Create application directories
echo ""
echo "📁 Creating application directories..."
mkdir -p /opt/backend
mkdir -p /opt/frontend
mkdir -p /opt/devops
print_status "Directories created"

# Clone repositories
echo ""
echo "📥 Cloning repositories..."

read -p "Enter backend repository URL: " BACKEND_REPO
read -p "Enter frontend repository URL: " FRONTEND_REPO
read -p "Enter devops repository URL: " DEVOPS_REPO

if [ ! -z "$BACKEND_REPO" ]; then
    cd /opt
    git clone "$BACKEND_REPO" backend
    print_status "Backend cloned"
fi

if [ ! -z "$FRONTEND_REPO" ]; then
    cd /opt
    git clone "$FRONTEND_REPO" frontend
    print_status "Frontend cloned"
fi

if [ ! -z "$DEVOPS_REPO" ]; then
    cd /opt
    git clone "$DEVOPS_REPO" devops
    print_status "DevOps cloned"
fi

# Setup environment files
echo ""
echo "⚙️ Setting up environment files..."

if [ -f "/opt/devops/config/env/backend.env.example" ]; then
    cp /opt/devops/config/env/backend.env.example /opt/backend/.env
    print_status "Backend .env created - PLEASE EDIT THIS FILE!"
fi

if [ -f "/opt/devops/config/env/docker-compose.env.example" ]; then
    cp /opt/devops/config/env/docker-compose.env.example /opt/devops/.env
    print_status "DevOps .env created - PLEASE EDIT THIS FILE!"
fi

echo ""
echo "✅ Server setup completed!"
echo ""
echo "📝 Next steps:"
echo "1. Edit environment files:"
echo "   - nano /opt/backend/.env"
echo "   - nano /opt/devops/.env"
echo ""
echo "2. Setup SSL certificate:"
echo "   cd /opt/devops"
echo "   ./scripts/setup-ssl.sh your-domain.com"
echo ""
echo "3. Deploy application:"
echo "   cd /opt/devops"
echo "   ./scripts/deploy.sh"
