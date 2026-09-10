# GrowthEngine Dokploy Setup Guide

Quick reference for deploying GrowthEngine using Dokploy.

## 📋 Prerequisites

- **Docker & Docker Compose** installed
- **Dokploy** instance running (self-hosted or cloud)
- **Domain name** with DNS access
- **OpenSSL** for generating secrets
- **Git** for version control

---

## 🚀 Quick Start (5 minutes)

### 1. Clone & Setup

```bash
git clone https://github.com/DivineFlame/GrowthEngine.git
cd GrowthEngine
chmod +x scripts/dokploy-deploy.sh
```

### 2. Run Auto-Setup Script

```bash
./scripts/dokploy-deploy.sh
```

The script will:
- ✓ Check dependencies
- ✓ Validate Dockerfiles
- ✓ Generate secure secrets
- ✓ Create `.env.dokploy` with auto-filled passwords
- ✓ Prompt for your domain
- ✓ Build all Docker images
- ✓ Start all services
- ✓ Wait for health checks

**Output**: Full deployment ready in 2-3 minutes

---

## 📝 Manual Setup

If you prefer manual control:

### Step 1: Create Environment File

```bash
cp .env.dokploy.example .env.dokploy
nano .env.dokploy
```

Generate secure passwords:
```bash
openssl rand -base64 48  # For POSTGRES_PASSWORD & REDIS_PASSWORD
openssl rand -base64 64  # For JWT_SECRET
openssl rand -base64 32  # For ENCRYPTION_KEY
```

### Step 2: Build Images

```bash
docker compose -f dokploy.yml --env-file .env.dokploy build
```

### Step 3: Start Services

```bash
docker compose -f dokploy.yml --env-file .env.dokploy up -d
```

### Step 4: Verify Services

```bash
docker compose -f dokploy.yml ps
docker compose -f dokploy.yml logs -f api  # Watch API logs
```

### Step 5: Test Health Endpoints

```bash
curl http://localhost:3000/health      # API
curl http://localhost:3005/             # Frontend
curl http://localhost:8000/health      # Paperclip
```

---

## 🔧 Configuration Files

### `dokploy.yml`
Main Docker Compose configuration defining all services, networks, and volumes.

**Key sections:**
- **PostgreSQL**: RLS-enabled database with init script
- **Redis**: Cache & message queue
- **API**: Node.js Express server (multitenant)
- **Paperclip**: Python FastAPI (media transformation)
- **Hermes**: Content orchestrator
- **CSV Handler**: Lead import service
- **Transformer Worker**: Queue processor
- **Frontend**: Nginx SPA server

### `.env.dokploy.example`
Template for environment variables. Copy to `.env.dokploy` and fill in:
- Database credentials
- JWT & encryption keys
- API keys (Sarvam, SendGrid, AWS)
- Domain names
- Feature flags

### `dokploy/nginx-ingress.conf`
Nginx reverse proxy configuration with:
- SSL/TLS termination
- Rate limiting (login, uploads, webhooks)
- Security headers (HSTS, CSP, X-Frame-Options)
- Gzip compression
- Load balancing

### `scripts/dokploy-deploy.sh`
Automated setup script that orchestrates the entire deployment process.

---

## 🌐 DNS & Networking

### DNS Records Required

Create A records pointing to your server IP:

```
api.yourdomain.com          A → YOUR_SERVER_IP
app.yourdomain.com          A → YOUR_SERVER_IP
webhook.yourdomain.com      A → YOUR_SERVER_IP (optional)
```

### Port Mapping

**External (Internet)**:
- Port 80 → HTTP redirect to HTTPS
- Port 443 → HTTPS (API, Frontend, Webhooks)

**Internal (Localhost only)**:
- 3000: API server
- 3001: Webhook server
- 3005: Frontend
- 8000: Paperclip
- 5432: PostgreSQL (localhost only)
- 6379: Redis (localhost only)

---

## 🔐 Security

### Best Practices Implemented

✓ Non-root container users  
✓ Read-only root filesystems  
✓ Capability dropping (CAP_DROP)  
✓ Network isolation (backend internal)  
✓ HTTPS/TLS 1.2+ only  
✓ HSTS headers  
✓ Rate limiting on sensitive endpoints  
✓ Security headers (CSP, X-Frame-Options)  
✓ Input validation (Zod schema)  
✓ SQL injection prevention (RLS policies)  

### Secret Rotation

Rotate secrets quarterly:

```bash
# Generate new secrets
NEW_JWT=$(openssl rand -base64 64)
NEW_ENCRYPTION=$(openssl rand -base64 32)

# Update .env.dokploy
nano .env.dokploy

# Restart API service
docker compose -f dokploy.yml --env-file .env.dokploy restart api
```

---

## 📊 Service Details

### PostgreSQL (Multitenant with RLS)

```bash
# Connect to database
docker compose -f dokploy.yml exec postgres psql -U orgcomms -d orgcomms_prod

# View tables
\dt

# Check RLS policies
SELECT * FROM pg_policies;
```

**Features:**
- UUID primary keys
- Row-level security per tenant
- Immutable audit logs
- Automatic timestamps

### Redis (Cache & Queue)

```bash
# Connect to Redis CLI
docker compose -f dokploy.yml exec redis redis-cli -a "$REDIS_PASSWORD"

# Check memory usage
INFO memory

# Monitor commands in real-time
MONITOR
```

**Features:**
- AOF persistence
- LRU eviction (max 512MB)
- Password-protected

### API Server (Node.js/Express)

```bash
# View logs
docker compose -f dokploy.yml logs -f api

# Test endpoint
curl -H "Authorization: Bearer TOKEN" http://localhost:3000/users

# Health check
curl http://localhost:3000/health
```

**Features:**
- Multitenant isolation via tenant_id
- JWT authentication
- File upload (100MB+ content, 10MB CSV)
- ClamAV scanning for malware

### Paperclip (Python/FastAPI)

```bash
# View logs
docker compose -f dokploy.yml logs -f paperclip-transformer

# Test API
curl http://localhost:8000/docs  # Swagger UI
```

**Features:**
- Video transformation (YouTube, Shorts, TikTok, Reels, etc.)
- Image resizing & optimization
- Concurrent processing
- Cache for transformed media

### Hermes (Content Publisher)

```bash
# View logs
docker compose -f dokploy.yml logs -f hermes-orchestrator
```

**Features:**
- Approval workflow
- Multi-channel publishing
- Brand compliance checks
- 6 AI agents (premium_multiagent mode)

### CSV Handler (Lead Import)

```bash
# View logs
docker compose -f dokploy.yml logs -f csv-handler
```

**Features:**
- 5000 row limit per file
- Deduplication (email + phone)
- ClamAV malware scanning
- Phone/email regex validation

---

## 📈 Monitoring & Logs

### View All Logs

```bash
# Real-time tail
docker compose -f dokploy.yml logs -f

# Specific service
docker compose -f dokploy.yml logs -f api

# Last 100 lines
docker compose -f dokploy.yml logs --tail=100 api

# Follow with timestamps
docker compose -f dokploy.yml logs -f --timestamps api
```

### Service Health Status

```bash
docker compose -f dokploy.yml ps

# Expected output:
# NAME                          STATUS
# growthengine-postgres         Up (healthy)
# growthengine-redis            Up (healthy)
# growthengine-api              Up (healthy)
# growthengine-paperclip        Up
# growthengine-hermes           Up
# growthengine-csv-handler      Up
# growthengine-transformer-worker Up
# growthengine-frontend         Up
```

### Resource Usage

```bash
docker stats

# Shows CPU, memory, network I/O per container
```

---

## 🔄 Deployment & Updates

### Deploy to Dokploy (Automated)

1. **Connect GitHub repo to Dokploy**:
   - Dashboard → Projects → New Project
   - Select DivineFlame/GrowthEngine
   - Authorize GitHub App

2. **Configure webhook**:
   - Dokploy automatically deploys on git push to `main`

3. **Push changes**:
   ```bash
   git add .
   git commit -m "Update configuration"
   git push origin main
   ```

### Manual Deployment

```bash
# Pull latest changes
git pull origin main

# Rebuild images
docker compose -f dokploy.yml --env-file .env.dokploy build

# Restart services
docker compose -f dokploy.yml --env-file .env.dokploy up -d
```

### Blue-Green Deployment

For zero-downtime updates:

```bash
# Start new services with suffix
docker compose -f dokploy.yml --env-file .env.dokploy up -d api-v2

# Test new version
curl http://localhost:3000/health

# Switch traffic (via nginx config)
# Then stop old version
docker compose -f dokploy.yml stop api
docker compose -f dokploy.yml rm api
```

---

## 💾 Backups & Disaster Recovery

### Automated Backups

Dokploy handles automatic backups:

1. **Database backups** (PostgreSQL):
   - Frequency: Daily at 2 AM
   - Retention: 30 days
   - Location: Dokploy storage backend

2. **Volume backups** (Redis, media):
   - Configure in Dokploy dashboard
   - S3 or local storage

### Manual Database Backup

```bash
# Backup PostgreSQL
docker compose -f dokploy.yml exec postgres pg_dump -U orgcomms orgcomms_prod > backup-$(date +%Y%m%d).sql

# Compress
gzip backup-*.sql

# Verify
gunzip -t backup-*.sql.gz
```

### Manual Restore

```bash
# Stop services
docker compose -f dokploy.yml down

# Restore from backup
gunzip backup-*.sql.gz
docker compose -f dokploy.yml up -d postgres
sleep 10
docker compose -f dokploy.yml exec postgres psql -U orgcomms orgcomms_prod < backup-*.sql

# Restart all services
docker compose -f dokploy.yml up -d
```

---

## ⚙️ Performance Tuning

### PostgreSQL Optimization

Edit `dokploy.yml`, postgres service command:

```yaml
postgres:
  command: >
    -c shared_buffers=256MB
    -c effective_cache_size=1GB
    -c work_mem=16MB
    -c max_parallel_workers=4
```

### Redis Optimization

Already optimized:
- `maxmemory: 512MB` (adjust for your server)
- `maxmemory-policy: allkeys-lru` (evict least-used keys)
- `appendonly: yes` (AOF persistence)

### API Performance

Increase Node.js heap:

```yaml
api:
  environment:
    NODE_OPTIONS: --max-old-space-size=2048  # Increase from 1536
```

### Paperclip Performance

```yaml
paperclip-transformer:
  deploy:
    resources:
      limits:
        cpus: '4'        # Adjust for your server
        memory: 4G
```

---

## 🐛 Troubleshooting

### Service won't start

```bash
# Check service logs
docker compose -f dokploy.yml logs api

# Check docker events
docker events --filter type=container

# Manually inspect
docker compose -f dokploy.yml exec api sh
```

### Database connection fails

```bash
# Verify DATABASE_URL
docker compose -f dokploy.yml exec api env | grep DATABASE_URL

# Test connection
docker compose -f dokploy.yml exec api psql "$DATABASE_URL" -c "SELECT 1"

# Check postgres logs
docker compose -f dokploy.yml logs postgres
```

### Out of memory

```bash
# Check memory usage per service
docker stats

# Increase service limit in dokploy.yml
docker compose -f dokploy.yml --env-file .env.dokploy up -d
```

### Slow queries

```bash
# Enable slow query log
docker compose -f dokploy.yml exec postgres psql -c "
  ALTER SYSTEM SET log_min_duration_statement = 1000;
  SELECT pg_reload_conf();
"

# View slow queries
docker compose -f dokploy.yml logs postgres
```

### API returns 502 Bad Gateway

```bash
# Check if API is running
docker compose -f dokploy.yml ps api

# Check API logs
docker compose -f dokploy.yml logs api

# Test API health
curl http://localhost:3000/health

# If unhealthy, restart
docker compose -f dokploy.yml restart api
```

---

## 📚 Documentation Links

- **Dokploy Docs**: https://dokploy.com/docs
- **Docker Compose Spec**: https://github.com/compose-spec/compose-spec
- **PostgreSQL 15**: https://www.postgresql.org/docs/15/
- **Redis 7**: https://redis.io/docs/
- **FastAPI**: https://fastapi.tiangolo.com/
- **Express.js**: https://expressjs.com/
- **Nginx**: https://nginx.org/en/docs/

---

## 🆘 Getting Help

1. **Check logs**: `docker compose -f dokploy.yml logs -f`
2. **Read DOKPLOY_DEPLOYMENT.md** for detailed step-by-step guide
3. **Review environment variables**: `cat .env.dokploy`
4. **Test connectivity**: `docker compose -f dokploy.yml exec api ping postgres`
5. **Open GitHub issue**: https://github.com/DivineFlame/GrowthEngine/issues

---

## 🔄 Common Commands

| Task | Command |
|------|---------|
| **Build images** | `docker compose -f dokploy.yml --env-file .env.dokploy build` |
| **Start services** | `docker compose -f dokploy.yml --env-file .env.dokploy up -d` |
| **Stop services** | `docker compose -f dokploy.yml down` |
| **View logs** | `docker compose -f dokploy.yml logs -f` |
| **Restart service** | `docker compose -f dokploy.yml restart api` |
| **Execute command** | `docker compose -f dokploy.yml exec api npm test` |
| **SSH into container** | `docker compose -f dokploy.yml exec api sh` |
| **View resource usage** | `docker stats` |
| **Cleanup old images** | `docker image prune -a` |
| **Full cleanup** | `docker compose -f dokploy.yml down -v` |

---

## ✅ Deployment Checklist

- [ ] Git repository cloned locally
- [ ] `.env.dokploy` created with all secrets filled
- [ ] DNS A records configured (api.*, app.*)
- [ ] Docker & Docker Compose installed
- [ ] `scripts/dokploy-deploy.sh` executed successfully
- [ ] All services showing "Up (healthy)" status
- [ ] API `/health` endpoint returns 200
- [ ] Frontend loads at localhost:3005
- [ ] PostgreSQL & Redis accessible
- [ ] Dokploy project connected to GitHub
- [ ] SSL/TLS certificates ready (LetsEncrypt)
- [ ] Backups configured
- [ ] Monitoring/alerts set up (optional)
- [ ] Team documentation updated

---

**Version**: GrowthEngine 4.0-secure  
**Last Updated**: 2026-09-10  
**Maintainer**: DivineFlame
