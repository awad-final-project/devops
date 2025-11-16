# DevOps Repository - Mail Application Deployment

Repository này chứa tất cả configurations và scripts để deploy mail application lên server production.

## 📁 Cấu trúc

```
devops/
├── ansible/              # Ansible playbooks cho automation
│   ├── playbook.yml     # Main deployment playbook
│   ├── inventory.ini    # Server inventory
│   └── roles/           # Ansible roles
├── config/              # Configuration files
│   ├── nginx/           # Nginx configs
│   └── env/             # Environment templates
├── scripts/             # Deployment scripts
│   ├── deploy.sh        # Main deployment script
│   ├── setup-server.sh  # Server initial setup
│   └── rollback.sh      # Rollback to previous version
├── docker-compose.prod.yml
└── README.md
```

## 🚀 Quick Start

### Yêu cầu

- Server với Ubuntu 20.04+ hoặc CentOS 7+
- Docker và Docker Compose đã cài
- Domain đã trỏ về server IP
- SSH access vào server

### 1. Clone các repositories

Trên server production, clone 3 repos:

```bash
cd /opt
sudo git clone https://github.com/awad-final-project/backend.git
sudo git clone https://github.com/awad-final-project/frontend.git
sudo git clone https://github.com/awad-final-project/devops.git
```

### 2. Setup với Ansible (Recommended)

```bash
cd devops/ansible

# Cập nhật inventory với IP server
nano inventory.ini

# Chạy playbook để setup tất cả
ansible-playbook -i inventory.ini playbook.yml

# Hoặc chỉ deploy app
ansible-playbook -i inventory.ini playbook.yml --tags deploy
```

### 3. Setup thủ công (Manual)

```bash
cd /opt/devops

# Initial server setup (lần đầu)
sudo ./scripts/setup-server.sh

# Deploy application
sudo ./scripts/deploy.sh
```

## 📝 Configuration

### Environment Variables

Copy và cập nhật các file environment:

```bash
# Backend
cp config/env/backend.env.example /opt/backend/.env
nano /opt/backend/.env

# Frontend build-time env
# Cập nhật trong docker-compose.prod.yml
```

### SSL Certificate

```bash
# Option 1: Let's Encrypt (Automatic)
./scripts/setup-ssl.sh mail.nguyenanhhao.site

# Option 2: Custom certificate
cp your-cert.pem config/nginx/ssl/fullchain.pem
cp your-key.pem config/nginx/ssl/privkey.pem
```

## 🔧 Ansible Automation

### Inventory Setup

Cập nhật `ansible/inventory.ini`:

```ini
[production]
mail_server ansible_host=YOUR_SERVER_IP ansible_user=YOUR_SSH_USER

[production:vars]
ansible_python_interpreter=/usr/bin/python3
domain_name=mail.nguyenanhhao.site
```

### Playbook Commands

```bash
# Full deployment
ansible-playbook -i inventory.ini playbook.yml

# Only update application
ansible-playbook -i inventory.ini playbook.yml --tags deploy

# Only update SSL
ansible-playbook -i inventory.ini playbook.yml --tags ssl

# Check configuration
ansible-playbook -i inventory.ini playbook.yml --check
```

## 📊 Monitoring & Logs

```bash
# View logs
docker compose -f docker-compose.prod.yml logs -f

# Specific service
docker compose -f docker-compose.prod.yml logs -f backend

# Container status
docker compose -f docker-compose.prod.yml ps

# Resource usage
docker stats
```

## 🔄 Updates & Rollback

### Update Application

```bash
cd /opt/devops
./scripts/deploy.sh
```

### Rollback

```bash
cd /opt/devops
./scripts/rollback.sh
```

## 🔐 Security

- [ ] SSL certificate configured
- [ ] Firewall rules (ports 80, 443, 22 only)
- [ ] Strong JWT_SECRET
- [ ] MongoDB authentication enabled
- [ ] Regular backups scheduled
- [ ] Docker containers run as non-root
- [ ] Rate limiting enabled

## 📦 Backup & Restore

### Backup

```bash
# Automated daily backup
ansible-playbook -i inventory.ini playbook.yml --tags backup

# Manual backup
docker exec mongo mongodump --out /backup
docker cp mongo:/backup ./backup-$(date +%Y%m%d)
```

### Restore

```bash
docker cp ./backup mongo:/backup
docker exec mongo mongorestore /backup
```

## 🆘 Troubleshooting

### Containers won't start

```bash
# Check logs
docker compose -f docker-compose.prod.yml logs

# Rebuild
docker compose -f docker-compose.prod.yml up --build -d
```

### SSL Certificate Issues

```bash
# Check certificate
openssl x509 -in config/nginx/ssl/fullchain.pem -text -noout

# Renew Let's Encrypt
certbot renew --force-renewal
```

### Database Connection Issues

```bash
# Check MongoDB
docker exec mongo mongosh --eval "db.adminCommand('ping')"

# Reset MongoDB
docker compose -f docker-compose.prod.yml restart mongo
```

## 📞 Support

- Backend repo: https://github.com/awad-final-project/backend
- Frontend repo: https://github.com/awad-final-project/frontend
- DevOps repo: https://github.com/awad-final-project/devops
