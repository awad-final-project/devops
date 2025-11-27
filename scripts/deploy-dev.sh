#!/bin/bash

# Mail Application Deployment Script (DEV Environment)
# This script deploys the application to the development environment
#
# Usage:
#   ./deploy-dev.sh

set -e

echo "🚀 Starting DEV deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DEVOPS_DIR="/opt/devops"
COMPOSE_FILE="$DEVOPS_DIR/docker-compose.dev.yml"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root or with sudo${NC}"
    exit 1
fi

# Function to print colored output
print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed"
    exit 1
fi

print_status "Prerequisites checked"

# Check environment files
echo ""
echo "🔍 Checking environment configuration..."

if [ ! -f "/opt/backend/.env.dev" ]; then
    print_error "Backend .env.dev file not found. Please create /opt/backend/.env.dev"
    exit 1
fi

print_status "Environment files checked"

# Build and deploy
echo ""
echo "🔨 Deploying DEV containers..."

cd "$DEVOPS_DIR"

# Pull latest dev images
echo "📥 Pulling latest dev images..."
docker compose -f "$COMPOSE_FILE" pull

# Restart dev containers
echo "🔄 Restarting dev containers..."
docker compose -f "$COMPOSE_FILE" up -d

# Reload Nginx to ensure it picks up any changes (though usually not needed for container restarts)
# But if we changed nginx config, we might need to restart nginx container or reload
# docker compose -f "$COMPOSE_FILE" exec nginx nginx -s reload
# For safety, let's just ensure nginx is running
if ! docker compose -f "$COMPOSE_FILE" ps | grep -q "mail-app-nginx"; then
    print_warning "Nginx is not running. Starting it..."
    docker compose -f "$COMPOSE_FILE" up -d nginx
fi

# Clean up old images
echo ""
echo "🧹 Cleaning up old Docker images..."
docker image prune -f

print_status "DEV Deployment completed successfully!"

echo ""
echo "📊 Container Status:"
docker compose -f "$COMPOSE_FILE" ps

echo ""
echo "✅ DEV Deployment finished!"
echo "🌐 Dev Application should be available at: https://mail-dev.nguyenanhhao.site"
