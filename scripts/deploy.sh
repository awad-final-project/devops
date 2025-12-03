#!/bin/bash

# Mail Application Deployment Script (Standalone Production Server)
# This script deploys the application to a dedicated production server
#
# Usage:
#   ./deploy.sh                    # Deploy without local MongoDB (use external Atlas)
#   ./deploy.sh --profile local-db # Deploy with local MongoDB in Docker
#
# Prerequisites:
#   - Docker and Docker Compose installed
#   - Git repositories cloned to /opt/{backend,frontend,devops}
#   - SSL certificates (or will be auto-generated via certbot)

set -e

echo "🚀 Starting standalone production deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DOMAIN="mail.nguyenanhhao.site"
EMAIL="anhhao012004@gmail.com"
BASE_DIR="/opt"
BACKEND_DIR="$BASE_DIR/backend"
FRONTEND_DIR="$BASE_DIR/frontend"
DEVOPS_DIR="$BASE_DIR/devops"
COMPOSE_FILE="$DEVOPS_DIR/docker-compose.prod.yml"
NGINX_CONFIG="$DEVOPS_DIR/nginx/nginx.prod.conf"

# Parse arguments
PROFILE_ARG=""
if [[ "$1" == "--profile" && "$2" == "local-db" ]]; then
    PROFILE_ARG="--profile local-db"
    echo "📦 Using local MongoDB in Docker"
else
    echo "🌐 Using external MongoDB (Atlas)"
fi

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

if ! command -v docker compose &> /dev/null; then
    print_error "Docker Compose is not installed"
    exit 1
fi

print_status "Prerequisites checked"

# Pull latest code
echo ""
echo "📥 Pulling latest code..."

if [ -d "$BACKEND_DIR" ]; then
    cd "$BACKEND_DIR"
    git pull origin main
    print_status "Backend updated"
else
    print_warning "Backend directory not found at $BACKEND_DIR"
fi

if [ -d "$FRONTEND_DIR" ]; then
    cd "$FRONTEND_DIR"
    git pull origin main
    print_status "Frontend updated"
else
    print_warning "Frontend directory not found at $FRONTEND_DIR"
fi

if [ -d "$DEVOPS_DIR" ]; then
    cd "$DEVOPS_DIR"
    git pull origin main
    print_status "DevOps updated"
else
    print_error "DevOps directory not found at $DEVOPS_DIR"
    exit 1
fi

# Check environment files
echo ""
echo "🔍 Checking environment configuration..."

if [ ! -f "$BACKEND_DIR/.env" ]; then
    print_error "Backend .env file not found. Please create $BACKEND_DIR/.env"
    exit 1
fi

if [ ! -f "$DEVOPS_DIR/.env" ]; then
    print_warning "DevOps .env file not found. Using defaults from docker-compose"
fi

print_status "Environment files checked"

# Check Docker network
echo ""
echo "🌐 Checking Docker network..."

if ! docker network inspect mail-app-network &> /dev/null; then
    echo "Creating Docker network 'mail-app-network'..."
    docker network create mail-app-network
    print_status "Network created"
else
    print_status "Network exists"
fi

# Check certbot installation
echo ""
echo "🔐 Checking certbot installation..."

if ! command -v certbot &> /dev/null; then
    print_warning "Certbot not installed. Installing..."
    apt-get update
    apt-get install -y certbot
    print_status "Certbot installed"
else
    print_status "Certbot is installed"
fi

# Create certbot webroot directory
mkdir -p /var/www/certbot
print_status "Certbot webroot created"

# Check disk space
echo ""
echo "💾 Checking disk space..."
DISK_USAGE=$(df -h / | tail -1 | awk '{print $5}' | sed 's/%//')
echo -e "${BLUE}Current disk usage: ${DISK_USAGE}%${NC}"

if [ "$DISK_USAGE" -gt 90 ]; then
    print_warning "Disk usage is high (${DISK_USAGE}%). Running cleanup..."
    
    # Aggressive cleanup
    docker container prune -f
    docker image prune -a -f
    docker volume prune -f
    docker builder prune -a -f
    docker network prune -f
    
    print_status "Cleanup completed"
fi

# Build and deploy
echo ""
echo "🔨 Building and deploying containers..."

cd "$DEVOPS_DIR"

# Check if we need to pull images or build locally
if docker compose $PROFILE_ARG -f "$COMPOSE_FILE" config | grep -q "ghcr.io"; then
    echo "📦 Detected GitHub Container Registry images..."
    echo "ℹ️  If images are private, make sure you're logged in:"
    echo "    echo YOUR_GITHUB_TOKEN | docker login ghcr.io -u YOUR_USERNAME --password-stdin"
    echo ""
    echo "🔄 Attempting to pull images..."
    
    # Try to pull, but continue if it fails (we can build locally)
    if ! docker compose $PROFILE_ARG -f "$COMPOSE_FILE" pull 2>/dev/null; then
        print_warning "Could not pull images from registry. Will build locally instead."
    else
        print_status "Images pulled successfully"
    fi
else
    print_status "Using local build configuration"
fi

# Stop old containers if running
echo ""
echo "🛑 Stopping old containers (if any)..."
docker compose -f "$COMPOSE_FILE" down 2>/dev/null || true

# Build and start containers
echo ""
echo "🔨 Building and starting containers..."
docker compose $PROFILE_ARG -f "$COMPOSE_FILE" up -d --build --remove-orphans

# Wait for services to be healthy
echo ""
echo "⏳ Waiting for services to be healthy..."
sleep 15

# Check container status
echo ""
echo "📊 Checking container status..."
docker compose $PROFILE_ARG -f "$COMPOSE_FILE" ps

if docker compose $PROFILE_ARG -f "$COMPOSE_FILE" ps | grep -q "Up"; then
    print_status "Containers are running"
else
    print_error "Some containers failed to start"
    echo ""
    echo "📋 Container logs:"
    docker compose $PROFILE_ARG -f "$COMPOSE_FILE" logs --tail=100
    exit 1
fi

# SSL Certificate Setup
echo ""
echo "🔐 Setting up SSL certificate..."

# Check if certificate already exists
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    print_status "SSL certificate already exists"
    
    # Check if certificate is expiring soon (within 30 days)
    if openssl x509 -checkend 2592000 -noout -in "/etc/letsencrypt/live/$DOMAIN/fullchain.pem"; then
        print_status "Certificate is valid (not expiring soon)"
    else
        print_warning "Certificate is expiring soon. Renewing..."
        certbot renew --quiet
        docker exec mail-app-nginx nginx -s reload
        print_status "Certificate renewed and nginx reloaded"
    fi
else
    echo "📝 Obtaining SSL certificate for $DOMAIN..."
    
    # Stop nginx temporarily to free port 80
    echo "Stopping nginx container temporarily..."
    docker stop mail-app-nginx 2>/dev/null || true
    
    # Obtain certificate using standalone mode
    if certbot certonly --standalone \
        -d "$DOMAIN" \
        --email "$EMAIL" \
        --agree-tos \
        --non-interactive; then
        
        print_status "SSL certificate obtained successfully"
        
        # Start nginx again
        echo "Starting nginx container..."
        docker start mail-app-nginx
        sleep 3
        
        print_status "Nginx restarted with SSL"
    else
        print_error "Failed to obtain SSL certificate"
        print_warning "Trying to start nginx anyway..."
        docker start mail-app-nginx 2>/dev/null || true
        print_warning "Application is accessible via HTTP only"
    fi
fi

# Clean up old images
echo ""
echo "🧹 Cleaning up old Docker images..."
docker image prune -f

# Setup auto-renewal for SSL certificate
echo ""
echo "⏰ Setting up SSL auto-renewal..."

# Add cron job for auto-renewal if not exists
CRON_JOB="0 3 * * * certbot renew --quiet --deploy-hook 'docker exec mail-app-nginx nginx -s reload'"
(crontab -l 2>/dev/null | grep -v "certbot renew") || true
(crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
print_status "SSL auto-renewal cron job configured"

print_status "Deployment completed successfully!"

echo ""
echo "📊 Container Status:"
docker compose -f "$COMPOSE_FILE" ps

echo ""
echo "🔗 Useful Commands:"
echo "   View logs:        docker compose -f $COMPOSE_FILE logs -f"
echo "   Restart:          docker compose -f $COMPOSE_FILE restart"
echo "   Stop:             docker compose -f $COMPOSE_FILE down"
echo "   Rebuild:          docker compose -f $COMPOSE_FILE up -d --build"
echo ""
echo "   Renew SSL:        certbot renew --force-renewal"
echo "   Reload nginx:     docker exec mail-app-nginx nginx -s reload"

echo ""
echo "✅ Deployment finished successfully!"
echo ""
echo "🌐 Application is available at:"
if [ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
    echo "   ✓ HTTPS: https://$DOMAIN (SSL enabled)"
    echo "   ✓ HTTP:  http://$DOMAIN (redirects to HTTPS)"
else
    echo "   ⚠ HTTP only: http://$DOMAIN"
fi
echo ""
echo "📝 Server: $(hostname -I | awk '{print $1}')"
echo "💾 Disk usage: $(df -h / | tail -1 | awk '{print $5}')"
echo "🐳 Docker containers: $(docker ps | wc -l) running"
