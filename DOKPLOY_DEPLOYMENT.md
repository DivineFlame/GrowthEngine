# GrowthEngine Dokploy Deployment Guide

## Overview
GrowthEngine is a multitenant SaaS application with:
- **API**: Node.js/Express backend (multitenant RLS, RBAC, leads/content management)
- **Frontend**: Nginx-based static SPA
- **Paperclip**: Python FastAPI service for content transformation (video/image/social media formats)
- **Hermes**: Node.js orchestrator for content approval/publishing workflow
- **CSV Handler**: Node.js service for lead CSV processing with deduplication & ClamAV scanning
- **Transformer Worker**: Redis-based queue worker for media processing
- **Database**: PostgreSQL 15 with RLS policies & audit logs
- **Redis**: Message queue & caching (7.0-alpine)
- **ClamAV**: Malware scanning for uploads

## Architecture for Dokploy

Dokploy excels at deploying containerized services. This guide configures GrowthEngine as a **multi-service application** with automatic builds, environment management, and deployment workflows.

---

## Step 1: Create Dokploy Project & Connect Repository

1. **Log in to Dokploy** → Dashboard
2. **Create New Project** → Select `DivineFlame/GrowthEngine` GitHub repo
   - Choose `main` branch
   - Set GitHub App permissions (read repo content, deploy on push)
3. **Project Settings**:
   - Name: `GrowthEngine`
   - Auto-deploy on push: ✓ enabled
   - Docker registry: Leave default (or configure private registry if needed)

---

## Step 2: Configure Services in dokploy.yml

Create a `dokploy.yml` file in the repository root:

```yaml
version: '3'

# Global dokploy configuration
dokploy:
  project: growthengine
  namespace: growthengine
  healthcheck_timeout: 30

services:
  # Database (PostgreSQL)
  postgres:
    image: postgres:15-alpine
    name: postgres
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-orgcomms}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB:-orgcomms_prod}
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./postgres/init-secure.sql:/docker-entrypoint-initdb.d/01-init.sql:ro
    networks:
      - backend
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U $POSTGRES_USER"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  # Redis Cache & Queue
  redis:
    image: redis:7-alpine
    name: redis
    command: >
      redis-server 
      --appendonly yes 
      --requirepass ${REDIS_PASSWORD}
      --bind 0.0.0.0
      --maxmemory 512mb 
      --maxmemory-policy allkeys-lru
    volumes:
      - redis_data:/data
    networks:
      - backend
    healthcheck:
      test: ["CMD", "redis-cli", "--raw", "incr", "ping"]
      interval: 10s
      timeout: 3s
      retries: 3
    restart: unless-stopped

  # ClamAV Antivirus
  clamav:
    image: clamav/clamav:latest
    name: clamav
    volumes:
      - clamav_data:/var/lib/clamav
    networks:
      - backend
    restart: unless-stopped

  # Node.js API Server
  api:
    build:
      context: ./api
      dockerfile: Dockerfile
    name: api
    environment:
      NODE_ENV: production
      DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      JWT_SECRET: ${JWT_SECRET}
      ENCRYPTION_KEY: ${ENCRYPTION_KEY}
      CLAMAV_HOST: clamav
      SARVAM_API_KEY: ${SARVAM_API_KEY}
      PAPERCLIP_SERVICE: paperclip-transformer:8000
      HERMES_MODE: premium_multiagent
      API_PORT: 3000
      WEBHOOK_PORT: 3001
    ports:
      - "3000:3000"
      - "3001:3001"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      clamav:
        condition: service_started
    networks:
      - frontend
      - backend
    healthcheck:
      test: ["CMD", "wget", "-qO-", "http://localhost:3000/health"]
      interval: 20s
      timeout: 5s
      retries: 3
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M

  # Python FastAPI Paperclip (Media Transformation)
  paperclip-transformer:
    build:
      context: ./paperclip
      dockerfile: Dockerfile
    name: paperclip-transformer
    environment:
      CLAMAV_HOST: clamav
    volumes:
      - recordings:/app/recordings
      - paperclip_cache:/app/cache
    depends_on:
      - clamav
    networks:
      - backend
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 4G
        reservations:
          cpus: '1'
          memory: 1G

  # Hermes Orchestrator (Content Publisher)
  hermes-orchestrator:
    build:
      context: ./hermes
      dockerfile: Dockerfile
    name: hermes-orchestrator
    environment:
      DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      PAPERCLIP_SERVICE: paperclip-transformer:8000
      HERMES_MODE: premium_multiagent
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks:
      - backend
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G
        reservations:
          cpus: '0.25'
          memory: 256M

  # CSV Handler (Lead Import)
  csv-handler:
    build:
      context: ./csv-handler
      dockerfile: Dockerfile
    name: csv-handler
    environment:
      DATABASE_URL: postgres://${POSTGRES_USER}:${POSTGRES_PASSWORD}@postgres:5432/${POSTGRES_DB}
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      CLAMAV_HOST: clamav
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      clamav:
        condition: service_started
    networks:
      - backend
    restart: unless-stopped

  # Transformer Worker (Media Queue Processing)
  transformer-worker:
    build:
      context: ./transformer
      dockerfile: Dockerfile
    name: transformer-worker
    environment:
      REDIS_URL: redis://:${REDIS_PASSWORD}@redis:6379
      PAPERCLIP_SERVICE: paperclip-transformer:8000
    depends_on:
      - redis
    networks:
      - backend
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M

  # Frontend SPA (Nginx)
  frontend:
    build:
      context: ./frontend
      dockerfile: Dockerfile
    name: frontend
    ports:
      - "3005:80"
    networks:
      - frontend
    restart: unless-stopped
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
        reservations:
          cpus: '0.25'
          memory: 128M

volumes:
  postgres_data:
  redis_data:
  clamav_data:
  recordings:
  paperclip_cache:

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: false  # Set to true if no external access needed
```

---

## Step 3: Configure Environment Variables

Create `.env.dokploy` in the repository root (never commit this file):

```bash
# PostgreSQL
POSTGRES_USER=orgcomms
POSTGRES_PASSWORD=<generate: openssl rand -base64 48>
POSTGRES_DB=orgcomms_prod

# Redis
REDIS_PASSWORD=<generate: openssl rand -base64 48>

# JWT & Encryption (for Node services)
JWT_SECRET=<generate: openssl rand -base64 64>
ENCRYPTION_KEY=<generate: openssl rand -base64 32>

# Third-party APIs
SARVAM_API_KEY=<your_sarvam_key>

# Email (optional)
EMAIL_SERVICE=sendgrid
SENDGRID_API_KEY=<if_using_sendgrid>

# Logging
LOG_LEVEL=info

# App URLs (replace with your actual domain)
API_DOMAIN=api.yourdomain.com
APP_DOMAIN=app.yourdomain.com
```

**Upload to Dokploy**:
1. In Dokploy Dashboard → Project → Environment Variables
2. Paste variables from `.env.dokploy`
3. Dokploy encrypts and stores them securely

---

## Step 4: Configure Ingress/Reverse Proxy

Dokploy supports multiple ingress options. Choose one:

### Option A: Dokploy's Built-in Nginx Ingress (Recommended)

In Dokploy Dashboard:

1. **Create Ingress**:
   - Name: `growthengine-ingress`
   - Type: Nginx

2. **Add Routes**:
   ```
   Route 1: api.yourdomain.com → Service: api:3000
   Route 2: app.yourdomain.com → Service: frontend:80
   Route 3: webhook.yourdomain.com → Service: api:3001
   ```

3. **SSL/TLS**:
   - Enable: ✓ LetsEncrypt Auto Certificate
   - Email: admin@yourdomain.com
   - Auto-renew: ✓ enabled

4. **Rate Limiting** (optional, via annotations):
   ```yaml
   nginx.ingress.kubernetes.io/limit-rps: "50"
   nginx.ingress.kubernetes.io/limit-connections: "20"
   ```

### Option B: Use Existing Nginx Config

Copy your `nginx/orgcomms-vps.conf` to:
```bash
/etc/nginx/sites-available/growthengine
```

Restart Nginx:
```bash
systemctl reload nginx
```

---

## Step 5: Volume & Persistence Setup

Dokploy automatically manages volumes. Verify:

1. **Database Persistence**: `postgres_data` volume
   - Location: Dokploy storage backend (Docker volume or NFS)
   - Backup strategy: Configure Dokploy backup policy

2. **Media Storage**:
   - `recordings/` - video/audio uploads
   - `paperclip_cache/` - transformed media cache

**Backup Strategy**:
- Enable Dokploy's automated backups for `postgres_data`
- Frequency: Daily at 2 AM (configure in Dokploy)
- Retention: 30 days

---

## Step 6: Build & Deploy

### Automatic Deployment (GitHub Push)

1. Push changes to `main` branch:
   ```bash
   git add dokploy.yml .env.dokploy
   git commit -m "Add dokploy configuration"
   git push origin main
   ```

2. Dokploy webhook triggers automatically:
   - Builds all services from Dockerfile
   - Runs `docker compose build`
   - Starts services with health checks
   - Monitors logs in real-time

### Manual Deployment

In Dokploy Dashboard → Project:
1. Click **Deploy**
2. Select branch: `main`
3. Click **Build & Deploy**
4. Monitor logs in real-time

---

## Step 7: Health Checks & Monitoring

Dokploy monitors service health:

```bash
# Check all services status
dokploy status

# View logs for specific service
dokploy logs api
dokploy logs paperclip-transformer
dokploy logs postgres

# Tail live logs
dokploy logs -f api
```

**Critical Health Endpoints**:
- API: `https://api.yourdomain.com/health` (should return 200)
- Frontend: `https://app.yourdomain.com/` (should load)
- Webhook: `https://api.yourdomain.com/webhooks/health`

---

## Step 8: Database Migrations & Initialization

The `postgres/init-secure.sql` runs automatically on first startup via `docker-entrypoint-initdb.d/`.

For subsequent migrations:

```bash
# Connect to running postgres container
dokploy exec postgres psql -U orgcomms -d orgcomms_prod

# Run custom SQL
\i migration.sql
```

Or use a migration tool (e.g., Flyway, Liquibase) by adding:
```yaml
services:
  migrations:
    image: flyway/flyway:latest
    command: -url=jdbc:postgresql://postgres:5432/orgcomms_prod -user=orgcomms -password=${POSTGRES_PASSWORD} migrate
    depends_on:
      - postgres
```

---

## Step 9: Scaling Services

Dokploy supports horizontal scaling:

1. **API Server**:
   ```yaml
   deploy:
     replicas: 3  # Run 3 instances with load balancing
   ```

2. **Paperclip Transformer** (CPU-intensive):
   ```yaml
   deploy:
     replicas: 2
     resources:
       limits:
         cpus: '4'
         memory: 4G
   ```

3. **Transformer Worker** (Queue processing):
   ```yaml
   deploy:
     replicas: 2
   ```

Update `dokploy.yml` and redeploy.

---

## Step 10: Backup & Disaster Recovery

### Automated Backups (Dokploy)

1. In Dokploy Dashboard → Project → Backups:
   - Enable: ✓ Automated backups
   - Frequency: Daily
   - Retention: 30 days
   - Destination: S3 (or local storage)

### Manual Backup

```bash
# Backup PostgreSQL
dokploy exec postgres pg_dump -U orgcomms -d orgcomms_prod > backup.sql

# Backup Redis
dokploy exec redis redis-cli BGSAVE
docker cp growthengine_redis_1:/data/dump.rdb ./redis-backup.rdb

# Backup volumes
tar -czf recordings-backup.tar.gz /var/lib/docker/volumes/growthengine_recordings/_data
```

### Restore from Backup

```bash
# Restore PostgreSQL
cat backup.sql | dokploy exec postgres psql -U orgcomms -d orgcomms_prod

# Restore Redis
docker cp redis-backup.rdb growthengine_redis_1:/data/dump.rdb
dokploy exec redis redis-cli BGREWRITEAOF
```

---

## Step 11: Performance Tuning

### PostgreSQL Optimization

Add to `docker-compose` postgres service:

```yaml
postgres:
  command: >
    -c shared_buffers=256MB
    -c effective_cache_size=1GB
    -c work_mem=16MB
    -c max_parallel_workers=4
    -c max_parallel_workers_per_gather=2
```

### Redis Optimization

Already configured in dokploy.yml:
- `maxmemory: 512MB` with LRU eviction
- `appendonly: yes` for AOF persistence

### Node.js API Performance

Update `api/Dockerfile`:

```dockerfile
ENV NODE_OPTIONS="--max-old-space-size=1536"
```

### Paperclip (Python/FastAPI) Workers

```yaml
paperclip-transformer:
  environment:
    WORKERS: 4  # Gunicorn workers
    THREADS: 2
```

---

## Step 12: Monitoring & Logging

### Dokploy Built-in Monitoring

1. Dashboard → Project → Metrics:
   - CPU usage per service
   - Memory usage
   - Network I/O
   - Container restarts

2. **Alerts** (if available):
   - CPU > 80%
   - Memory > 90%
   - Service restart loop

### External Logging (Optional)

For centralized logging (Datadog, New Relic, ELK):

```yaml
services:
  api:
    logging:
      driver: json-file
      options:
        labels: service=api
        tag: "{{.ImageName}}|{{.Name}}"
```

Then configure log forwarding to your monitoring platform.

---

## Step 13: Security Hardening

### Network Policies

1. Restrict backend access:
   ```yaml
   networks:
     backend:
       internal: true  # No external access to backend services
   ```

2. Only API and Frontend expose to frontend network.

### Image Security

1. Use minimal base images:
   - Node: `node:20-alpine`
   - Python: `python:3.11-slim`
   - Nginx: `nginx:alpine`

2. Run as non-root user (already configured in Dockerfiles)

3. Sign container images (Dokploy → Registry Settings)

### Secrets Management

1. Dokploy encrypts all env variables
2. Never commit `.env.dokploy`
3. Rotate JWT/ENCRYPTION_KEY quarterly:
   ```bash
   openssl rand -base64 64 > /tmp/new_jwt_secret
   # Update in Dokploy Dashboard
   ```

---

## Step 14: Troubleshooting

### Service Won't Start

```bash
# Check service status
dokploy status

# View error logs
dokploy logs api  # See specific service logs
dokploy logs -f postgres

# Check Docker health
docker ps --filter "label=dokploy.project=growthengine"

# Test connectivity between services
dokploy exec api ping postgres
```

### Database Connection Fails

```bash
# Verify DATABASE_URL env var
dokploy exec api printenv | grep DATABASE_URL

# Test postgres connectivity
dokploy exec api psql "$DATABASE_URL" -c "SELECT 1"

# Check postgres logs
dokploy logs postgres
```

### Out of Memory

```bash
# Check memory usage
dokploy stats

# Increase memory limit for service
# Edit dokploy.yml:
deploy:
  resources:
    limits:
      memory: 4G
```

### Performance Degradation

```bash
# Check CPU & disk usage
dokploy stats

# View slow queries (PostgreSQL)
dokploy exec postgres psql -c "SELECT * FROM pg_stat_statements ORDER BY mean_time DESC LIMIT 10;"

# Check Redis memory
dokploy exec redis redis-cli INFO memory
```

---

## Deployment Checklist

- [ ] Create GitHub project in Dokploy
- [ ] Set environment variables in Dokploy dashboard
- [ ] Commit `dokploy.yml` to repository
- [ ] Configure DNS records (A records pointing to Dokploy server)
- [ ] Enable LetsEncrypt SSL in Dokploy ingress
- [ ] Run first deployment (manual or via git push)
- [ ] Verify health checks: `/health` endpoints
- [ ] Test API: `curl https://api.yourdomain.com/health`
- [ ] Test Frontend: Open `https://app.yourdomain.com` in browser
- [ ] Configure database backups
- [ ] Set up monitoring/alerts
- [ ] Document deployment in team wiki
- [ ] Set up CI/CD notifications (optional)

---

## Quick Start Commands

```bash
# Deploy
dokploy deploy main

# View status
dokploy status

# Tail all logs
dokploy logs -f

# Restart specific service
dokploy restart api

# Stop all services
dokploy stop

# Start all services
dokploy start

# Clean up (remove stopped containers, dangling images)
dokploy prune
```

---

## Resources

- **Dokploy Docs**: https://dokploy.com/docs
- **Docker Compose Spec**: https://github.com/compose-spec/compose-spec
- **PostgreSQL 15 Docs**: https://www.postgresql.org/docs/15/
- **Redis 7 Docs**: https://redis.io/docs/
- **FastAPI Docs**: https://fastapi.tiangolo.com/
- **Express.js Docs**: https://expressjs.com/

---

**Last Updated**: 2026-09-10  
**Maintainer**: DivineFlame  
**Version**: GrowthEngine 4.0-secure
