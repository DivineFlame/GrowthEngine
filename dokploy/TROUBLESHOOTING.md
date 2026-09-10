# GrowthEngine Dokploy Troubleshooting Guide

Comprehensive troubleshooting reference for common deployment issues.

## 🔍 Diagnostic Commands

### Check Overall Status

```bash
# View all services
docker compose -f dokploy.yml ps

# View resource usage
docker stats

# View system info
docker system info

# Check disk space
df -h /var/lib/docker

# Check network connectivity
docker network ls
docker network inspect growthengine_backend
```

### View Logs

```bash
# All services
docker compose -f dokploy.yml logs

# Specific service
docker compose -f dokploy.yml logs api
docker compose -f dokploy.yml logs postgres
docker compose -f dokploy.yml logs redis
docker compose -f dokploy.yml logs paperclip-transformer

# Real-time tail
docker compose -f dokploy.yml logs -f api

# Last N lines
docker compose -f dokploy.yml logs --tail=50 api

# With timestamps
docker compose -f dokploy.yml logs -f --timestamps api

# Since specific time
docker compose -f dokploy.yml logs --since 2026-09-10T10:00:00 api
```

---

## ❌ Service Won't Start

### Issue: Service crashes immediately

**Diagnosis:**
```bash
docker compose -f dokploy.yml logs api
docker compose -f dokploy.yml ps api  # Check STATUS
```

**Common causes & fixes:**

#### 1. Environment variables not set
```bash
# Check if .env.dokploy exists
ls -la .env.dokploy

# Verify variables are loaded
docker compose -f dokploy.yml exec api env | grep DATABASE_URL
```

**Fix:**
```bash
cp .env.dokploy.example .env.dokploy
# Fill in actual values
nano .env.dokploy
```

#### 2. Port already in use
```bash
# Check which process is using the port
lsof -i :3000
netstat -tulpn | grep 3000
```

**Fix:**
```bash
# Option A: Stop other process
kill -9 <PID>

# Option B: Change port in dokploy.yml
# Change: "127.0.0.1:3000:3000" to "127.0.0.1:3100:3000"
```

#### 3. Insufficient disk space
```bash
df -h /var/lib/docker
docker system df
```

**Fix:**
```bash
# Clean up unused images
docker image prune -a

# Clean up volumes
docker volume prune

# Remove old containers
docker container prune
```

#### 4. Image build failed
```bash
docker compose -f dokploy.yml logs postgres  # Check build logs
```

**Fix:**
```bash
# Rebuild with verbose output
docker compose -f dokploy.yml build --no-cache api
```

---

## 🔗 Database Connection Issues

### Issue: "Database connection refused"

**Diagnosis:**
```bash
# Check postgres is running
docker compose -f dokploy.yml ps postgres

# Check if postgres is healthy
docker compose -f dokploy.yml exec postgres pg_isready

# Check logs
docker compose -f dokploy.yml logs postgres
```

**Fix - PostgreSQL not starting:**

```bash
# 1. Check init script
ls -la postgres/init-secure.sql

# 2. Check postgres logs for SQL errors
docker compose -f dokploy.yml logs postgres | tail -50

# 3. Restart postgres
docker compose -f dokploy.yml restart postgres
docker compose -f dokploy.yml logs -f postgres

# 4. If still fails, reset data
docker compose -f dokploy.yml down -v postgres
docker compose -f dokploy.yml up -d postgres
```

### Issue: "Connection timeout"

**Diagnosis:**
```bash
# Test connectivity from API container
docker compose -f dokploy.yml exec api psql "$DATABASE_URL" -c "SELECT 1"

# Test postgres listening
docker compose -f dokploy.yml exec postgres netstat -tulpn | grep 5432
```

**Fix:**
```bash
# Check if postgres is listening on correct interface
docker compose -f dokploy.yml exec postgres pg_isready -h postgres -p 5432

# Restart postgres
docker compose -f dokploy.yml restart postgres

# Restart dependent services
docker compose -f dokploy.yml restart api
```

### Issue: "Authentication failed"

**Diagnosis:**
```bash
# Verify password in environment
docker compose -f dokploy.yml exec api env | grep POSTGRES_PASSWORD

# Check credentials in DATABASE_URL
docker compose -f dokploy.yml exec postgres psql -U orgcomms -d orgcomms_prod -c "SELECT 1"
```

**Fix:**
```bash
# Regenerate password
NEW_PASS=$(openssl rand -base64 48)
echo "POSTGRES_PASSWORD=$NEW_PASS" >> .env.dokploy

# Restart all services
docker compose -f dokploy.yml down
docker compose -f dokploy.yml up -d
```

### Issue: "RLS policy violation"

**Diagnosis:**
```bash
# Connect to postgres
docker compose -f dokploy.yml exec postgres psql -U orgcomms -d orgcomms_prod

# Check RLS is enabled
SELECT * FROM pg_policies;

# Check current tenant_id
SELECT current_setting('app.tenant_id');
```

**Fix:**
```bash
# Verify tenant_id is set in API before queries
# In API code:
SET app.tenant_id = '<tenant-uuid>';

# Or check RLS policies
SELECT * FROM pg_policies WHERE polname LIKE 'tenant%';
```

---

## 🔴 Redis Connection Issues

### Issue: "Redis connection refused"

**Diagnosis:**
```bash
# Check redis is running
docker compose -f dokploy.yml ps redis

# Test redis connectivity
docker compose -f dokploy.yml exec redis redis-cli ping

# Check with password
docker compose -f dokploy.yml exec redis redis-cli -a "$REDIS_PASSWORD" ping
```

**Fix:**
```bash
# Check redis logs
docker compose -f dokploy.yml logs redis

# Verify password in environment
docker compose -f dokploy.yml exec api env | grep REDIS_PASSWORD

# Restart redis
docker compose -f dokploy.yml restart redis
```

### Issue: "Redis out of memory"

**Diagnosis:**
```bash
docker compose -f dokploy.yml exec redis redis-cli INFO memory
```

**Output example:**
```
used_memory: 536870912  # 512MB used
maxmemory: 536870912    # 512MB limit
```

**Fix:**
```bash
# Option A: Increase maxmemory limit
# In dokploy.yml, redis command:
--maxmemory 1gb

# Option B: Clear old keys
docker compose -f dokploy.yml exec redis redis-cli FLUSHDB

# Option C: Check for memory leaks
docker compose -f dokploy.yml exec redis redis-cli --memkeys
```

---

## 📡 API Server Issues

### Issue: "API returns 500 Internal Server Error"

**Diagnosis:**
```bash
# Check API logs
docker compose -f dokploy.yml logs api | tail -50

# Check API health
curl http://localhost:3000/health

# Test database connection from API
docker compose -f dokploy.yml exec api psql "$DATABASE_URL" -c "SELECT 1"
```

**Common causes:**

```bash
# 1. Database not ready
docker compose -f dokploy.yml restart postgres
sleep 5
docker compose -f dokploy.yml restart api

# 2. Redis not ready
docker compose -f dokploy.yml restart redis
docker compose -f dokploy.yml restart api

# 3. Missing environment variables
docker compose -f dokploy.yml exec api env | grep JWT_SECRET
docker compose -f dokploy.yml exec api env | grep ENCRYPTION_KEY
```

### Issue: "API returns 502 Bad Gateway"

**Diagnosis:**
```bash
# Check if API container is running
docker compose -f dokploy.yml ps api

# Check if API is listening
docker compose -f dokploy.yml exec api netstat -tulpn | grep 3000

# Test API directly
curl http://localhost:3000/health
```

**Fix:**
```bash
# Restart API
docker compose -f dokploy.yml restart api

# Check logs
docker compose -f dokploy.yml logs api

# If nginx is reverse proxy, check upstream
curl -v http://api:3000/health
```

### Issue: "File upload fails"

**Diagnosis:**
```bash
# Check upload size limit in nginx
grep client_max_body_size dokploy/nginx-ingress.conf

# Check disk space
df -h /

# Check volume mount
docker compose -f dokploy.yml exec api ls -la /app/recordings
```

**Fix:**
```bash
# Increase upload limit in nginx config
client_max_body_size 500M;

# Increase disk space
df -h  # Check available space

# Check permissions
docker compose -f dokploy.yml exec api chmod 777 /app/recordings
```

### Issue: "Out of memory"

**Diagnosis:**
```bash
# Check Node.js heap usage
docker compose -f dokploy.yml exec api node -e "console.log(require('os').totalmem() / 1024 / 1024 + ' MB')"

# Check docker memory limit
docker inspect growthengine-api | grep -A 10 '"Memory"'
```

**Fix:**
```bash
# Edit dokploy.yml
deploy:
  resources:
    limits:
      memory: 4G  # Increase from 2G
      
# Restart
docker compose -f dokploy.yml up -d
```

---

## 🎬 Paperclip (Media Transformation) Issues

### Issue: "Paperclip returns 500 error"

**Diagnosis:**
```bash
# Check paperclip logs
docker compose -f dokploy.yml logs paperclip-transformer

# Test paperclip health
curl http://localhost:8000/health

# Check Swagger docs
curl http://localhost:8000/docs
```

**Common causes:**

```bash
# 1. ClamAV not ready
docker compose -f dokploy.yml ps clamav
docker compose -f dokploy.yml logs clamav

# 2. Insufficient disk space for cache
df -h /var/lib/docker/volumes/growthengine_paperclip_cache

# 3. FFmpeg or image processing library missing
docker compose -f dokploy.yml exec paperclip-transformer which ffmpeg
```

### Issue: "Media transformation too slow"

**Diagnosis:**
```bash
# Check CPU usage
docker stats paperclip-transformer

# Check cache hit rate
docker compose -f dokploy.yml exec paperclip-transformer du -sh /app/cache

# Check concurrent jobs
docker compose -f dokploy.yml logs paperclip-transformer | grep "processing"
```

**Fix:**
```bash
# Increase CPU limits in dokploy.yml
paperclip-transformer:
  deploy:
    resources:
      limits:
        cpus: '8'  # Increase from 4

# Or add more worker replicas
# Scale to 2 instances (if using orchestration)
```

---

## 📨 Hermes (Publisher) Issues

### Issue: "Publishing fails"

**Diagnosis:**
```bash
# Check hermes logs
docker compose -f dokploy.yml logs hermes-orchestrator

# Check if paperclip is accessible
docker compose -f dokploy.yml exec hermes-orchestrator curl http://paperclip-transformer:8000/health

# Check database connection
docker compose -f dokploy.yml exec hermes-orchestrator psql "$DATABASE_URL" -c "SELECT 1"
```

**Common causes:**

```bash
# 1. Paperclip not ready
docker compose -f dokploy.yml restart paperclip-transformer
docker compose -f dokploy.yml restart hermes-orchestrator

# 2. Missing API keys
docker compose -f dokploy.yml exec hermes-orchestrator env | grep SARVAM_API_KEY

# 3. Database tables not initialized
docker compose -f dokploy.yml exec postgres psql -U orgcomms -d orgcomms_prod -c "SELECT COUNT(*) FROM content_variants;"
```

---

## 📥 CSV Handler Issues

### Issue: "CSV import fails"

**Diagnosis:**
```bash
# Check csv-handler logs
docker compose -f dokploy.yml logs csv-handler

# Check ClamAV
docker compose -f dokploy.yml ps clamav
docker compose -f dokploy.yml logs clamav
```

**Common causes:**

```bash
# 1. ClamAV scanning failure
# Restart ClamAV
docker compose -f dokploy.yml restart clamav

# 2. Row count exceeded limit
# Check CSV row count
wc -l < input.csv

# 3. Invalid email/phone format
# Verify regex validation in code
```

---

## 🌐 Network & Connectivity Issues

### Issue: "Containers can't communicate"

**Diagnosis:**
```bash
# Check networks
docker network ls
docker network inspect growthengine_backend

# Test connectivity from API to postgres
docker compose -f dokploy.yml exec api ping postgres

# Test DNS resolution
docker compose -f dokploy.yml exec api nslookup postgres
```

**Fix:**
```bash
# Rebuild networks
docker compose -f dokploy.yml down
docker compose -f dokploy.yml up -d

# Check service names in /etc/hosts
docker compose -f dokploy.yml exec api cat /etc/hosts
```

### Issue: "External connections timeout"

**Diagnosis:**
```bash
# Check firewall
sudo ufw status

# Check listening ports
sudo netstat -tulpn | grep LISTEN

# Test external connectivity
docker compose -f dokploy.yml exec api curl https://api.google.com
```

**Fix:**
```bash
# Allow required ports
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3000/tcp

# Check DNS
docker compose -f dokploy.yml exec api cat /etc/resolv.conf
```

---

## 📊 Performance Issues

### Issue: "Application is slow"

**Diagnosis:**
```bash
# Check container resources
docker stats --no-stream

# Check database queries
docker compose -f dokploy.yml exec postgres psql -U orgcomms -d orgcomms_prod -c "SELECT * FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 10;"

# Check slow queries in API
docker compose -f dokploy.yml logs api | grep "slow query"

# Check Redis commands
docker compose -f dokploy.yml exec redis redis-cli --stat
```

**Fixes:**

```bash
# 1. Increase resource limits
deploy:
  resources:
    limits:
      cpus: '4'
      memory: 4G

# 2. Enable database query caching
docker compose -f dokploy.yml exec postgres psql -U orgcomms -d orgcomms_prod -c "
  ALTER SYSTEM SET effective_cache_size = '2GB';
  SELECT pg_reload_conf();
"

# 3. Add indexes
docker compose -f dokploy.yml exec postgres psql -U orgcomms -d orgcomms_prod -c "
  CREATE INDEX idx_fast_query ON table_name(column_name);
"

# 4. Increase Redis memory
redis:
  command: redis-server --maxmemory 2gb

# 5. Scale services
# Add replicas in docker-compose or use orchestration
```

---

## 🔐 Security Issues

### Issue: "Secrets exposed in logs"

**Diagnosis:**
```bash
docker compose -f dokploy.yml logs | grep -i password
docker compose -f dokploy.yml logs | grep -i key
```

**Fix:**
```bash
# Redact logs from .env.dokploy
# Never commit .env.dokploy to git

# Rotate exposed secrets
openssl rand -base64 48 > /tmp/new_password
# Update in .env.dokploy and restart
```

### Issue: "Unauthorized access"

**Diagnosis:**
```bash
# Check JWT validation
curl -H "Authorization: Bearer invalid_token" http://localhost:3000/users

# Check if API is validating tokens
docker compose -f dokploy.yml logs api | grep "jwt"
```

**Fix:**
```bash
# Verify JWT_SECRET is set
docker compose -f dokploy.yml exec api env | grep JWT_SECRET

# Restart API
docker compose -f dokploy.yml restart api
```

---

## 🗂️ Backup & Recovery Issues

### Issue: "Backup failed"

**Diagnosis:**
```bash
# Check backup logs
docker compose -f dokploy.yml logs

# Check backup destination
ls -la /var/lib/docker/volumes/

# Check disk space
df -h
```

**Fix:**
```bash
# Manual backup
docker compose -f dokploy.yml exec postgres pg_dump -U orgcomms orgcomms_prod > backup.sql

# Compress
gzip backup.sql

# Verify
gunzip -t backup.sql.gz
```

### Issue: "Restore failed"

**Diagnosis:**
```bash
# Check postgres is running and empty
docker compose -f dokploy.yml exec postgres psql -U orgcomms -d orgcomms_prod -c "SELECT COUNT(*) FROM information_schema.tables;"

# Check backup file integrity
gunzip -t backup.sql.gz
```

**Fix:**
```bash
# Drop and recreate database
docker compose -f dokploy.yml exec postgres psql -U postgres -c "DROP DATABASE orgcomms_prod;"
docker compose -f dokploy.yml exec postgres psql -U postgres -c "CREATE DATABASE orgcomms_prod;"

# Restore
gunzip backup.sql.gz
cat backup.sql | docker compose -f dokploy.yml exec postgres psql -U orgcomms orgcomms_prod
```

---

## 🆘 Emergency Recovery

### Complete Reset (CAUTION: Data loss)

```bash
# Stop all services
docker compose -f dokploy.yml down

# Remove all volumes (DATA LOSS!)
docker compose -f dokploy.yml down -v

# Remove images
docker rmi growthengine-api growthengine-paperclip growthengine-hermes growthengine-csv-handler growthengine-transformer-worker growthengine-frontend

# Clean up
docker system prune -a

# Start fresh
docker compose -f dokploy.yml --env-file .env.dokploy build
docker compose -f dokploy.yml --env-file .env.dokploy up -d
```

### Selective Service Reset

```bash
# Reset only API
docker compose -f dokploy.yml down api
docker rmi growthengine-api
docker compose -f dokploy.yml build api
docker compose -f dokploy.yml up -d api
```

---

## 📞 Getting Help

1. **Check logs first**:
   ```bash
   docker compose -f dokploy.yml logs -f
   ```

2. **Review configuration**:
   ```bash
   cat dokploy.yml
   cat .env.dokploy
   ```

3. **Test components**:
   ```bash
   curl http://localhost:3000/health
   curl http://localhost:5432
   curl http://localhost:6379
   ```

4. **Consult documentation**:
   - `DOKPLOY_DEPLOYMENT.md` - Comprehensive guide
   - `dokploy/README.md` - Quick reference
   - Service-specific docs (FastAPI, Express, PostgreSQL)

5. **Open GitHub issue**:
   - Include error logs
   - Describe steps to reproduce
   - Attach `docker compose ps` output

---

**Last Updated**: 2026-09-10  
**Version**: GrowthEngine 4.0-secure
