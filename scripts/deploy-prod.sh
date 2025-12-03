#!/bin/bash

# Production Deployment Script (Image-based)
# This script deploys the application using pre-built images from GitHub Container Registry
#
# Usage:
#   ./deploy-prod.sh                    # Deploy without local MongoDB (use external Atlas)
#   ./deploy-prod.sh --profile local-db # Deploy with local MongoDB in Docker
#
# Prerequisites:
#   - Docker and Docker Compose installed
#   - Devops repository cloned to /opt/devops
#   - Environment file at /opt/backend/.env configured
#   - Images pushed to ghcr.io/awad-final-project/backend:main and frontend:main

set -e

echo "🚀 Starting production deployment (image-based)..."

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
ENV_FILE="/opt/backend/.env"
COMPOSE_FILE="$DEVOPS_DIR/docker-compose.prod.yml"

# Parse arguments
PROFILE_ARG=""
if [[ "$1" == "--profile" && "$2" == "local-db" ]]; then
    PROFILE_ARG="--profile local-db"
    echo "📦 Using local MongoDB in Docker"
else
    echo "🌐 Using external MongoDB (Atlas)"
fi

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

# Check prerequisites
echo "📋 Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    print_error "Docker is not installed. Run quick-setup.sh first!"
    exit 1
fi

if ! command -v docker compose &> /dev/null; then
    print_error "Docker Compose is not installed. Run quick-setup.sh first!"
    exit 1
fi

if [ ! -d "$DEVOPS_DIR" ]; then
    print_error "DevOps directory not found at $DEVOPS_DIR. Run quick-setup.sh first!"
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    print_error "Environment file not found at $ENV_FILE"
    print_info "Please copy and configure: cp $DEVOPS_DIR/config/env/backend.env.example $ENV_FILE"
    exit 1
fi

print_status "Prerequisites checked"

# Pull latest devops code
echo ""
echo "📥 Updating devops repository..."
cd "$DEVOPS_DIR"
git pull origin main
print_status "DevOps repository updated"

# Check Docker network
echo ""
echo "🌐 Setting up Docker network..."

if ! docker network inspect mail-app-network &> /dev/null; then
    docker network create mail-app-network
    print_status "Network created"
else
    print_status "Network already exists"
fi

# Check disk space
echo ""
echo "💾 Checking disk space..."
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
echo -e "${BLUE}Current disk usage: ${DISK_USAGE}%${NC}"

if [ "$DISK_USAGE" -gt 90 ]; then
    print_warning "Disk usage is high (${DISK_USAGE}%). Running cleanup..."
    docker system prune -af --volumes
    print_status "Cleanup completed"
fi

# Pull latest images from GitHub Container Registry
echo ""
echo "📦 Pulling latest images from GitHub Container Registry..."
print_info "Pulling ghcr.io/awad-final-project/backend:main"
print_info "Pulling ghcr.io/awad-final-project/frontend:main"

cd "$DEVOPS_DIR"

if docker compose $PROFILE_ARG -f "$COMPOSE_FILE" pull; then
    print_status "Images pulled successfully"
else
    print_error "Failed to pull images"
    print_warning "Make sure images are pushed to GitHub Container Registry"
    print_info "Check: https://github.com/orgs/awad-final-project/packages"
    exit 1
fi

# Stop old containers
echo ""
echo "🛑 Stopping old containers..."
docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true
print_status "Old containers stopped"

# Start new containers
echo ""
echo "🚀 Starting containers..."
docker compose $PROFILE_ARG -f "$COMPOSE_FILE" up -d --remove-orphans

# Wait for services to be healthy
echo ""
echo "⏳ Waiting for services to start..."
sleep 10

# Check container status
echo ""
echo "📊 Checking container status..."
docker compose $PROFILE_ARG -f "$COMPOSE_FILE" ps

RUNNING_CONTAINERS=$(docker compose $PROFILE_ARG -f "$COMPOSE_FILE" ps | grep -c "Up" || true)

if [ "$RUNNING_CONTAINERS" -ge 2 ]; then
    print_status "Containers are running ($RUNNING_CONTAINERS containers)"
else
    print_error "Some containers failed to start"
    echo ""
    echo "📋 Container logs:"
    docker compose $PROFILE_ARG -f "$COMPOSE_FILE" logs --tail=50
    exit 1
fi

# SSL Certificate Setup
echo ""
echo "🔐 Checking SSL certificate..."

if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    print_status "SSL certificate exists"
    
    # Check if certificate is expiring soon (within 30 days)
    if openssl x509 -checkend 2592000 -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" 2>/dev/null; then
        print_status "Certificate is valid"
    else
        print_warning "Certificate expiring soon. Renewing..."
        certbot renew --quiet
        docker exec mail-app-nginx nginx -s reload 2>/dev/null || true
        print_status "Certificate renewed"
    fi
else
    print_warning "No SSL certificate found"
    print_info "To setup SSL, run: ./scripts/setup-ssl.sh $DOMAIN"
fi

# Setup auto-renewal cron job
echo ""
echo "⏰ Setting up SSL auto-renewal..."
CRON_JOB="0 3 * * * certbot renew --quiet --deploy-hook 'docker exec mail-app-nginx nginx -s reload' 2>&1 | logger -t certbot"
(crontab -l 2>/dev/null | grep -F "certbot renew" || echo "$CRON_JOB") | crontab -
print_status "Auto-renewal configured"

# Clean up old images
echo ""
echo "🧹 Cleaning up old Docker images..."
docker image prune -f
print_status "Cleanup completed"

# Show final status
echo ""
echo "=============================================="
echo -e "${GREEN}✅ Deployment completed successfully!${NC}"
echo "=============================================="
echo ""

echo "📊 Container Status:"
docker compose -f "$COMPOSE_FILE" ps

echo ""
echo "🔗 Useful Commands:"
echo "   View logs:        docker compose -f $COMPOSE_FILE logs -f [service]"
echo "   Restart all:      docker compose -f $COMPOSE_FILE restart"
echo "   Restart service:  docker compose -f $COMPOSE_FILE restart [backend|frontend|nginx]"
echo "   Stop all:         docker compose -f $COMPOSE_FILE down"
echo "   Update & redeploy: cd $DEVOPS_DIR && ./scripts/deploy-prod.sh"
echo ""
echo "   Renew SSL:        certbot renew --force-renewal"
echo "   Reload nginx:     docker exec mail-app-nginx nginx -s reload"
echo ""

echo "🌐 Application URLs:"
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo "   ✓ HTTPS: https://$DOMAIN"
    echo "   ✓ HTTP:  http://$DOMAIN (redirects to HTTPS)"
else
    echo "   ⚠ HTTP:  http://$DOMAIN"
    echo "   ⚠ HTTPS: Not configured yet"
fi

echo ""
echo "📝 Server Info:"
echo "   IP:              $(hostname -I | awk '{print $1}')"
echo "   Disk usage:      $(df -h / | tail -1 | awk '{print $5}')"
echo "   Containers:      $(docker ps | wc -l) running"
echo "   Images:"
echo "     Backend:       $(docker images ghcr.io/awad-final-project/backend:main --format '{{.Repository}}:{{.Tag}} ({{.Size}})')"
echo "     Frontend:      $(docker images ghcr.io/awad-final-project/frontend:main --format '{{.Repository}}:{{.Tag}} ({{.Size}})')"
echo ""
