#!/bin/bash

# SSL Certificate Setup Script
# Uses Let's Encrypt to obtain SSL certificates

set -e

echo "🔐 Setting up SSL certificate with Let's Encrypt..."

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root or with sudo"
    exit 1
fi

# Get domain from argument or prompt
if [ -z "$1" ]; then
    read -p "Enter domain name: " DOMAIN
else
    DOMAIN=$1
fi

if [ -z "$DOMAIN" ]; then
    print_error "Domain name is required"
    exit 1
fi

# Get email for Let's Encrypt
read -p "Enter email for SSL notifications: " EMAIL

if [ -z "$EMAIL" ]; then
    print_error "Email is required"
    exit 1
fi

echo ""
echo "📋 Configuration:"
echo "   Domain: $DOMAIN"
echo "   Email: $EMAIL"
echo ""

# Check if certbot is installed
if ! command -v certbot &> /dev/null; then
    echo "Installing certbot..."
    apt-get update
    apt-get install -y certbot
fi

# Stop nginx if running (to free port 80)
if docker ps | grep -q mail-app-nginx; then
    echo "Stopping nginx container..."
    docker stop mail-app-nginx
fi

# Obtain certificate
echo ""
echo "🔐 Obtaining SSL certificate..."
certbot certonly --standalone \
    -d "$DOMAIN" \
    --email "$EMAIL" \
    --agree-tos \
    --non-interactive

# Create SSL directory
mkdir -p /opt/devops/config/nginx/ssl

# Copy certificates
echo ""
echo "📁 Copying certificates..."
cp /etc/letsencrypt/live/"$DOMAIN"/fullchain.pem /opt/devops/config/nginx/ssl/
cp /etc/letsencrypt/live/"$DOMAIN"/privkey.pem /opt/devops/config/nginx/ssl/
chmod 644 /opt/devops/config/nginx/ssl/*.pem

print_status "Certificates copied"

# Setup auto-renewal
echo ""
echo "⏰ Setting up auto-renewal..."

# Create renewal hook script
cat > /etc/letsencrypt/renewal-hooks/post/reload-nginx.sh << 'EOF'
#!/bin/bash
cp /etc/letsencrypt/live/*/fullchain.pem /opt/devops/config/nginx/ssl/
cp /etc/letsencrypt/live/*/privkey.pem /opt/devops/config/nginx/ssl/
chmod 644 /opt/devops/config/nginx/ssl/*.pem
docker restart mail-app-nginx
EOF

chmod +x /etc/letsencrypt/renewal-hooks/post/reload-nginx.sh

# Add cron job for auto-renewal
if ! crontab -l | grep -q "certbot renew"; then
    (crontab -l 2>/dev/null; echo "0 2 * * * certbot renew --quiet") | crontab -
    print_status "Auto-renewal cron job added"
fi

# Test renewal
echo ""
echo "🧪 Testing certificate renewal..."
certbot renew --dry-run

print_status "SSL setup completed successfully!"

echo ""
echo "✅ SSL certificate obtained and configured"
echo "🔄 Certificate will auto-renew every 90 days"
echo ""
echo "📝 Certificate files:"
echo "   - /opt/devops/config/nginx/ssl/fullchain.pem"
echo "   - /opt/devops/config/nginx/ssl/privkey.pem"
