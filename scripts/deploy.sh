#!/bin/bash

# Mail Application Deployment Script
# This script deploys the application to production
#
# Usage:
#   ./deploy.sh                    # Deploy without local MongoDB (use external)
#   ./deploy.sh --profile local-db # Deploy with local MongoDB in Docker

set -e

echo "🚀 Starting deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
DEVOPS_DIR="/opt/devops"
BACKEND_DIR="/opt/backend"
FRONTEND_DIR="/opt/frontend"
COMPOSE_FILE="$DEVOPS_DIR/docker-compose.prod.yml"

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

# Check SSL certificates
echo ""
echo "🔐 Checking SSL certificates..."

if [ ! -f "$DEVOPS_DIR/config/nginx/ssl/fullchain.pem" ] || [ ! -f "$DEVOPS_DIR/config/nginx/ssl/privkey.pem" ]; then
    print_error "SSL certificates not found. Please run setup-ssl.sh first"
    exit 1
fi

print_status "SSL certificates found"

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

# Build and start containers
docker compose $PROFILE_ARG -f "$COMPOSE_FILE" up -d --build

# Wait for services to be healthy
echo ""
echo "⏳ Waiting for services to be healthy..."
sleep 10

# Check container status
if docker compose $PROFILE_ARG -f "$COMPOSE_FILE" ps | grep -q "Up"; then
    print_status "Containers are running"
else
    print_error "Some containers failed to start"
    docker compose $PROFILE_ARG -f "$COMPOSE_FILE" ps
    exit 1
fi

# Clean up old images
echo ""
echo "🧹 Cleaning up old Docker images..."
docker image prune -f

print_status "Deployment completed successfully!"

echo ""
echo "📊 Container Status:"
docker compose -f "$COMPOSE_FILE" ps

echo ""
echo "📝 View logs with:"
echo "   docker compose -f $COMPOSE_FILE logs -f"

echo ""
echo "✅ Deployment finished!"
echo "🌐 Application should be available at: https://mail.nguyenanhhao.site"
