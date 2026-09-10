#!/bin/bash
set -e

# GrowthEngine Dokploy Quick Start Script
# This script automates the initial deployment setup

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Functions
print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

# Check dependencies
check_dependencies() {
    print_info "Checking dependencies..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    print_success "Docker found"
    
    if ! command -v docker compose &> /dev/null; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    print_success "Docker Compose found"
    
    if ! command -v openssl &> /dev/null; then
        print_error "OpenSSL is not installed. Please install OpenSSL first."
        exit 1
    fi
    print_success "OpenSSL found"
}

# Generate secure passwords
generate_secrets() {
    print_info "Generating secure secrets..."
    
    POSTGRES_PASSWORD=$(openssl rand -base64 48)
    REDIS_PASSWORD=$(openssl rand -base64 48)
    JWT_SECRET=$(openssl rand -base64 64)
    ENCRYPTION_KEY=$(openssl rand -base64 32)
    
    print_success "Secrets generated"
}

# Create environment file
create_env_file() {
    print_info "Creating .env.dokploy file..."
    
    if [ -f "$SCRIPT_DIR/.env.dokploy" ]; then
        print_error ".env.dokploy already exists. Backup and remove it first."
        exit 1
    fi
    
    cp "$SCRIPT_DIR/.env.dokploy.example" "$SCRIPT_DIR/.env.dokploy"
    
    # Replace placeholders with generated secrets
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s|YOUR_STRONG_POSTGRES_PASSWORD_HERE|$POSTGRES_PASSWORD|g" "$SCRIPT_DIR/.env.dokploy"
        sed -i '' "s|YOUR_STRONG_REDIS_PASSWORD_HERE|$REDIS_PASSWORD|g" "$SCRIPT_DIR/.env.dokploy"
        sed -i '' "s|YOUR_JWT_SECRET_KEY_HERE|$JWT_SECRET|g" "$SCRIPT_DIR/.env.dokploy"
        sed -i '' "s|YOUR_ENCRYPTION_KEY_HERE|$ENCRYPTION_KEY|g" "$SCRIPT_DIR/.env.dokploy"
    else
        # Linux
        sed -i "s|YOUR_STRONG_POSTGRES_PASSWORD_HERE|$POSTGRES_PASSWORD|g" "$SCRIPT_DIR/.env.dokploy"
        sed -i "s|YOUR_STRONG_REDIS_PASSWORD_HERE|$REDIS_PASSWORD|g" "$SCRIPT_DIR/.env.dokploy"
        sed -i "s|YOUR_JWT_SECRET_KEY_HERE|$JWT_SECRET|g" "$SCRIPT_DIR/.env.dokploy"
        sed -i "s|YOUR_ENCRYPTION_KEY_HERE|$ENCRYPTION_KEY|g" "$SCRIPT_DIR/.env.dokploy"
    fi
    
    print_success ".env.dokploy created with secure secrets"
}

# Configure domain
configure_domain() {
    print_info "Enter your domain (e.g., yourdomain.com):"
    read -p "Domain: " DOMAIN
    
    if [ -z "$DOMAIN" ]; then
        print_error "Domain cannot be empty"
        exit 1
    fi
    
    API_DOMAIN="api.$DOMAIN"
    APP_DOMAIN="app.$DOMAIN"
    WEBHOOK_DOMAIN="webhook.$DOMAIN"
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|api.yourdomain.com|$API_DOMAIN|g" "$SCRIPT_DIR/.env.dokploy"
        sed -i '' "s|app.yourdomain.com|$APP_DOMAIN|g" "$SCRIPT_DIR/.env.dokploy"
        sed -i '' "s|webhook.yourdomain.com|$WEBHOOK_DOMAIN|g" "$SCRIPT_DIR/.env.dokploy"
    else
        sed -i "s|api.yourdomain.com|$API_DOMAIN|g" "$SCRIPT_DIR/.env.dokploy"
        sed -i "s|app.yourdomain.com|$APP_DOMAIN|g" "$SCRIPT_DIR/.env.dokploy"
        sed -i "s|webhook.yourdomain.com|$WEBHOOK_DOMAIN|g" "$SCRIPT_DIR/.env.dokploy"
    fi
    
    print_success "Domain configured: $DOMAIN"
}

# Validate Dockerfiles
validate_dockerfiles() {
    print_info "Validating Dockerfiles..."
    
    SERVICES=("api" "paperclip" "hermes" "csv-handler" "transformer" "frontend")
    for service in "${SERVICES[@]}"; do
        if [ ! -f "$SCRIPT_DIR/$service/Dockerfile" ]; then
            print_error "Dockerfile not found in $service directory"
            exit 1
        fi
        print_success "$service/Dockerfile found"
    done
}

# Build services
build_services() {
    print_info "Building Docker images..."
    print_info "This may take several minutes..."
    
    cd "$SCRIPT_DIR"
    
    if docker compose -f dokploy.yml --env-file .env.dokploy build; then
        print_success "All services built successfully"
    else
        print_error "Build failed. Check logs above."
        exit 1
    fi
}

# Start services
start_services() {
    print_info "Starting services..."
    
    cd "$SCRIPT_DIR"
    
    if docker compose -f dokploy.yml --env-file .env.dokploy up -d; then
        print_success "Services started"
    else
        print_error "Failed to start services"
        exit 1
    fi
}

# Wait for services to be healthy
wait_for_services() {
    print_info "Waiting for services to be healthy (this may take 1-2 minutes)..."
    
    cd "$SCRIPT_DIR"
    
    # Wait for PostgreSQL
    print_info "Waiting for PostgreSQL..."
    for i in {1..30}; do
        if docker exec growthengine-postgres pg_isready -U orgcomms &> /dev/null; then
            print_success "PostgreSQL is ready"
            break
        fi
        if [ $i -eq 30 ]; then
            print_error "PostgreSQL failed to start"
            exit 1
        fi
        sleep 2
    done
    
    # Wait for Redis
    print_info "Waiting for Redis..."
    for i in {1..30}; do
        if docker exec growthengine-redis redis-cli ping &> /dev/null; then
            print_success "Redis is ready"
            break
        fi
        if [ $i -eq 30 ]; then
            print_error "Redis failed to start"
            exit 1
        fi
        sleep 2
    done
    
    # Wait for API
    print_info "Waiting for API server..."
    for i in {1..30}; do
        if curl -f http://localhost:3000/health &> /dev/null; then
            print_success "API is ready"
            break
        fi
        if [ $i -eq 30 ]; then
            print_error "API failed to start"
            exit 1
        fi
        sleep 2
    done
}

# Show status
show_status() {
    print_info "Checking service status..."
    
    cd "$SCRIPT_DIR"
    docker compose -f dokploy.yml --env-file .env.dokploy ps
}

# Summary
show_summary() {
    echo ""
    echo "=========================================="
    print_success "GrowthEngine Dokploy Deployment Complete!"
    echo "=========================================="
    echo ""
    echo "Services running:"
    echo "  - PostgreSQL:        127.0.0.1:5432"
    echo "  - Redis:             127.0.0.1:6379"
    echo "  - API:               127.0.0.1:3000"
    echo "  - Paperclip:         127.0.0.1:8000"
    echo "  - Frontend:          127.0.0.1:3005"
    echo ""
    echo "Quick Commands:"
    echo "  View logs:           docker compose -f dokploy.yml logs -f"
    echo "  Stop services:       docker compose -f dokploy.yml down"
    echo "  Restart services:    docker compose -f dokploy.yml restart"
    echo ""
    echo "Next Steps:"
    echo "  1. Configure DNS (A records):"
    echo "     api.$DOMAIN -> $(hostname -I | awk '{print $1}')"
    echo "     app.$DOMAIN -> $(hostname -I | awk '{print $1}')"
    echo ""
    echo "  2. Edit .env.dokploy to add:"
    echo "     - SARVAM_API_KEY"
    echo "     - SENDGRID_API_KEY (optional)"
    echo "     - AWS credentials (optional)"
    echo ""
    echo "  3. Set up reverse proxy (Nginx/dokploy ingress)"
    echo ""
    echo "  4. Enable SSL with LetsEncrypt"
    echo ""
    echo "Documentation: See DOKPLOY_DEPLOYMENT.md"
    echo "=========================================="
    echo ""
}

# Main execution
main() {
    echo "=========================================="
    echo "GrowthEngine Dokploy Quick Start Setup"
    echo "=========================================="
    echo ""
    
    check_dependencies
    validate_dockerfiles
    generate_secrets
    create_env_file
    configure_domain
    build_services
    start_services
    wait_for_services
    show_status
    show_summary
}

# Run main
main
