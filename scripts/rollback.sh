#!/bin/bash

# Rollback Script
# Rolls back to previous deployment

set -e

echo "⏪ Rolling back deployment..."

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

DEVOPS_DIR="/opt/devops"
COMPOSE_FILE="$DEVOPS_DIR/docker-compose.prod.yml"

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}❌ Please run as root or with sudo${NC}"
    exit 1
fi

cd "$DEVOPS_DIR"

# List available commits
echo "📜 Recent deployments:"
git log --oneline -5

echo ""
read -p "Enter commit hash to rollback to (or 'HEAD~1' for previous): " COMMIT

if [ -z "$COMMIT" ]; then
    COMMIT="HEAD~1"
fi

# Confirm rollback
echo ""
echo -e "${YELLOW}⚠ Warning: This will rollback to commit: $COMMIT${NC}"
read -p "Continue? (y/N): " CONFIRM

if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Rollback cancelled"
    exit 0
fi

# Perform rollback
echo ""
echo "🔄 Rolling back..."

# Stop containers
docker compose -f "$COMPOSE_FILE" down

# Checkout previous version
cd /opt/devops && git checkout "$COMMIT"
cd /opt/backend && git checkout "$COMMIT" 2>/dev/null || true
cd /opt/frontend && git checkout "$COMMIT" 2>/dev/null || true

# Restart containers
cd "$DEVOPS_DIR"
docker compose -f "$COMPOSE_FILE" up -d --build

print_status "Rollback completed"

echo ""
echo "📊 Container Status:"
docker compose -f "$COMPOSE_FILE" ps

echo ""
echo "✅ Rollback finished!"
