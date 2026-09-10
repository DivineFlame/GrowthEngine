# OrgComms v4 REAL APP KIT - VPS - No Fake Images - Builds Locally

## FIXED FROM YOUR SCREENSHOT
BEFORE: docker-compose.vps.yml pulled ghcr.io/orgcomms/api:secure-v4-vps (does not exist) + hermes/paperclip/csv-handler/transformer had 4-line stub Dockerfiles no index.js
NOW: All services build from local source:
- api/src/server.js 19KB real Express API with multitenant RLS, RBAC HR 7d Sales 30d, leads, content upload 100MB, CSV upload 10MB 5000 rows sanitize = + - @, approval workflow, audit_logs immutable, webhooks 7 channels, Hermes+Paperclip integration
- hermes/orchestrator.js real orchestrator: scout fetches brief from Drive/Slack, transformer calls Paperclip, compliance checks brand/tone/CTA, publisher publishes after approval, lead_intake dedup enrich GSTIN
- paperclip/transformer.py real FastAPI: YouTube 1920x1080 thumb 1280x720 title<=100, Shorts 1080x1920 60s, IG Feed 1080x1080/1350, Reels 1080x1920, FB 1200x628, LinkedIn 1200x627 doc 1080x1350, WhatsApp 1:1, PIL resize, virus checks
- csv-handler/csv-handler.js real: 10MB max 5000 rows sanitize = + - @ email regex dedup phone+email ClamAV
- transformer/worker.js real queue worker 2 replicas Redis brPop -> Paperclip

## Deploy on Hostinger VPS KVM 8 (8 vCPU 16GB 200GB NVMe) Ubuntu 22.04

1. Upload: scp -r vps-real-app-kit root@YOUR_VPS_IP:/opt/orgcomms && cd /opt/orgcomms
2. cp .env.vps.example .env.production && nano .env.production (fill strong passwords openssl rand -base64 48, set API_DOMAIN=api.yourdomain.com APP_DOMAIN=app.yourdomain.com)
3. DNS: api + app A -> YOUR_VPS_IP
4. Setup VPS: sudo bash scripts/setup-vps.sh yourdomain.com admin@yourdomain.com (Docker, Nginx, UFW 22,80,443 only, Fail2ban, ClamAV, SSL LetsEncrypt, backup cron 2AM)
5. Build locally (no ghcr.io):
   docker compose -f docker-compose.vps.yml --env-file .env.production build
   docker compose -f docker-compose.vps.yml --env-file .env.production up -d
6. Check:
   https://app.yourdomain.com
   https://api.yourdomain.com/health
   docker logs orgcomms-api -f
   docker logs orgcomms-hermes -f
   docker logs orgcomms-paperclip -f

Content Studio: Upload raw -> Fetch team details -> Select channels -> Paperclip transforms per spec -> Pending Approval -> Approved -> Hermes Publisher publishes
Lead CSV: Drag-drop CSV/Excel -> mapping -> sanitize -> dedup -> ClamAV -> Inbox + Sarvam queue
Multitenant RLS tenant_id, Multiuser HR 7d Sales 30d, Premium Multiagent 6 agents 83% automated
