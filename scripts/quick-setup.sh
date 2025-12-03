#!/bin/bash

# Quick Production Setup Script
# This script sets up the entire application from scratch with just the devops repository
#
# Prerequisites: Fresh Ubuntu/Debian server with root access
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/awad-final-project/devops/main/scripts/quick-setup.sh | sudo bash
#   OR
#   git clone https://github.com/awad-final-project/devops.git /opt/devops && cd /opt/devops && sudo ./scripts/quick-setup.sh

set -e

echo "🚀 Quick Production Setup for Mail Application"
echo "=============================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
DOMAIN="${DOMAIN:-mail.nguyenanhhao.site}"
EMAIL="${EMAIL:-anhhao012004@gmail.com}"
DEVOPS_DIR="/opt/devops"
ENV_FILE="$DEVOPS_DIR/config/env/backend.env"

# Functions
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root or with sudo"
    exit 1
fi

print_info "Starting server setup..."
echo ""

# Step 1: Update system
echo "📦 Step 1/7: Updating system packages..."
apt-get update -qq
apt-get upgrade -y -qq
print_status "System updated"

# Step 2: Install Docker
echo ""
echo "🐳 Step 2/7: Installing Docker..."

if command -v docker &> /dev/null; then
    print_status "Docker already installed ($(docker --version))"
else
    print_info "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh
    rm get-docker.sh
    systemctl start docker
    systemctl enable docker
    print_status "Docker installed successfully"
fi

# Step 3: Install Docker Compose
echo ""
echo "🐳 Step 3/7: Installing Docker Compose..."

if command -v docker compose &> /dev/null; then
    print_status "Docker Compose already installed"
else
    apt-get install -y docker-compose-plugin -qq
    print_status "Docker Compose installed"
fi

# Step 4: Install additional tools
echo ""
echo "🛠️ Step 4/7: Installing additional tools..."
apt-get install -y git curl ufw certbot -qq
print_status "Tools installed (git, curl, ufw, certbot)"

# Step 5: Setup firewall
echo ""
echo "🔥 Step 5/7: Configuring firewall..."
ufw --force enable
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 80/tcp
ufw allow 443/tcp
print_status "Firewall configured (SSH, HTTP, HTTPS allowed)"

# Step 6: Clone/Update devops repository
echo ""
echo "📥 Step 6/7: Setting up devops repository..."

if [ -d "$DEVOPS_DIR/.git" ]; then
    print_info "Devops repository already exists, updating..."
    cd "$DEVOPS_DIR"
    git pull origin main
    print_status "Repository updated"
else
    print_info "Cloning devops repository..."
    mkdir -p /opt
    cd /opt
    
    # Try to clone, if already exists but not a git repo, backup and clone
    if [ -d "$DEVOPS_DIR" ] && [ ! -d "$DEVOPS_DIR/.git" ]; then
        print_warning "Non-git directory exists, backing up..."
        mv "$DEVOPS_DIR" "${DEVOPS_DIR}.backup.$(date +%s)"
    fi
    
    git clone https://github.com/awad-final-project/devops.git devops
    print_status "Repository cloned"
fi

# Step 7: Setup environment file
echo ""
echo "⚙️ Step 7/7: Setting up environment configuration..."

mkdir -p /opt/backend

if [ -f "$ENV_FILE" ]; then
    print_warning "Environment file already exists at $ENV_FILE"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp "$DEVOPS_DIR/config/env/backend.env.example" "$ENV_FILE"
        print_status "Environment file created"
    else
        print_info "Keeping existing environment file"
    fi
else
    cp "$DEVOPS_DIR/config/env/backend.env.example" "$ENV_FILE"
    print_status "Environment file created at $ENV_FILE"
fi

# Create certbot webroot
mkdir -p /var/www/certbot
print_status "Certbot webroot created"

# Setup complete
echo ""
echo "=============================================="
echo -e "${GREEN}✅ Server setup completed successfully!${NC}"
echo "=============================================="
echo ""

print_info "Environment file location: $ENV_FILE"
print_warning "⚠️  IMPORTANT: You must edit the environment file before deploying!"
echo ""
echo "Required variables to configure:"
echo "  - MONGO_URI (MongoDB Atlas connection string)"
echo "  - JWT_SECRET (random secure string)"
echo "  - IMAP credentials (email account settings)"
echo ""
echo "📝 Edit environment file:"
echo "   nano $ENV_FILE"
echo ""
echo "🚀 After editing, deploy the application:"
echo "   cd $DEVOPS_DIR"
echo "   ./scripts/deploy-prod.sh"
echo ""
echo "📋 Server Info:"
echo "   IP: $(hostname -I | awk '{print $1}')"
echo "   Docker: $(docker --version)"
echo "   Firewall: Active (ports 22, 80, 443 open)"
echo ""
