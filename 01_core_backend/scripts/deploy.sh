#!/bin/bash

# StudyAI Deployment Script
# Automated deployment with blue-green strategy and rollback capabilities

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DOCKER_COMPOSE_FILE="docker-compose.prod.yml"
BACKUP_DIR="/opt/studyai/backups"
LOG_FILE="/var/log/studyai/deployment.log"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    local level=$1
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case $level in
        INFO)  echo -e "${GREEN}[INFO]${NC} $message" | tee -a "$LOG_FILE" ;;
        WARN)  echo -e "${YELLOW}[WARN]${NC} $message" | tee -a "$LOG_FILE" ;;
        ERROR) echo -e "${RED}[ERROR]${NC} $message" | tee -a "$LOG_FILE" ;;
        DEBUG) echo -e "${BLUE}[DEBUG]${NC} $message" | tee -a "$LOG_FILE" ;;
    esac
}

# Help function
show_help() {
    cat << EOF
StudyAI Deployment Script

Usage: $0 [COMMAND] [OPTIONS]

Commands:
    deploy      Deploy the application (default)
    rollback    Rollback to previous version
    status      Show deployment status
    backup      Create backup
    restore     Restore from backup
    health      Run health checks
    logs        Show application logs

Options:
    -e, --env ENVIRONMENT    Target environment (staging|production)
    -v, --version VERSION    Application version to deploy
    -f, --force             Force deployment without confirmation
    -h, --help              Show this help message

Examples:
    $0 deploy -e production -v v1.2.3
    $0 rollback -e staging
    $0 health -e production
EOF
}

# Parse command line arguments
COMMAND="deploy"
ENVIRONMENT=""
VERSION=""
FORCE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        deploy|rollback|status|backup|restore|health|logs)
            COMMAND=$1
            shift
            ;;
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log ERROR "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Validate environment
if [[ -z "$ENVIRONMENT" ]]; then
    log ERROR "Environment must be specified with -e option"
    exit 1
fi

if [[ "$ENVIRONMENT" != "staging" && "$ENVIRONMENT" != "production" ]]; then
    log ERROR "Environment must be 'staging' or 'production'"
    exit 1
fi

# Load environment-specific configuration
ENV_FILE="$PROJECT_DIR/.env.$ENVIRONMENT"
if [[ -f "$ENV_FILE" ]]; then
    log INFO "Loading environment configuration from $ENV_FILE"
    source "$ENV_FILE"
else
    log WARN "Environment file $ENV_FILE not found, using defaults"
fi

# Set Docker Compose file based on environment
case $ENVIRONMENT in
    staging)
        DOCKER_COMPOSE_FILE="docker-compose.staging.yml"
        ;;
    production)
        DOCKER_COMPOSE_FILE="docker-compose.prod.yml"
        ;;
esac

# Pre-deployment checks
pre_deployment_checks() {
    log INFO "Running pre-deployment checks..."
    
    # Check if Docker is running
    if ! docker info >/dev/null 2>&1; then
        log ERROR "Docker is not running"
        exit 1
    fi
    
    # Check if required files exist
    if [[ ! -f "$PROJECT_DIR/$DOCKER_COMPOSE_FILE" ]]; then
        log ERROR "Docker Compose file not found: $DOCKER_COMPOSE_FILE"
        exit 1
    fi
    
    # Check disk space
    local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    if [[ $disk_usage -gt 85 ]]; then
        log WARN "Disk space is $disk_usage% full"
        if [[ $disk_usage -gt 95 ]]; then
            log ERROR "Critical disk space. Aborting deployment."
            exit 1
        fi
    fi
    
    # Check if ports are available
    local required_ports=("80" "443" "3001")
    for port in "${required_ports[@]}"; do
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            log WARN "Port $port is already in use"
        fi
    done
    
    log INFO "Pre-deployment checks completed"
}

# Create backup
create_backup() {
    log INFO "Creating backup..."
    
    local backup_timestamp=$(date '+%Y%m%d_%H%M%S')
    local backup_path="$BACKUP_DIR/studyai_backup_$backup_timestamp"
    
    mkdir -p "$backup_path"
    
    # Backup application data
    if docker-compose -f "$PROJECT_DIR/$DOCKER_COMPOSE_FILE" ps -q | grep -q .; then
        log INFO "Backing up application data..."
        
        # Backup Redis data
        docker exec studyai-redis-$ENVIRONMENT redis-cli --rdb - > "$backup_path/redis_dump.rdb" 2>/dev/null || true
        
        # Backup Prometheus data
        docker cp "studyai-prometheus-$ENVIRONMENT:/prometheus" "$backup_path/prometheus_data" 2>/dev/null || true
        
        # Backup Grafana data
        docker cp "studyai-grafana-$ENVIRONMENT:/var/lib/grafana" "$backup_path/grafana_data" 2>/dev/null || true
        
        # Backup logs
        docker cp "studyai-gateway-$ENVIRONMENT:/app/logs" "$backup_path/application_logs" 2>/dev/null || true
    fi
    
    # Backup configuration files
    cp -r "$PROJECT_DIR/config" "$backup_path/"
    cp "$PROJECT_DIR/$DOCKER_COMPOSE_FILE" "$backup_path/"
    cp "$PROJECT_DIR/.env.$ENVIRONMENT" "$backup_path/" 2>/dev/null || true
    
    # Create backup metadata
    cat > "$backup_path/metadata.json" << EOF
{
    "timestamp": "$backup_timestamp",
    "environment": "$ENVIRONMENT",
    "version": "$VERSION",
    "created_by": "$(whoami)",
    "hostname": "$(hostname)"
}
EOF
    
    # Compress backup
    tar -czf "$backup_path.tar.gz" -C "$BACKUP_DIR" "$(basename "$backup_path")"
    rm -rf "$backup_path"
    
    log INFO "Backup created: $backup_path.tar.gz"
}

# Health check
run_health_checks() {
    log INFO "Running health checks..."
    
    local max_attempts=30
    local attempt=1
    local health_endpoint="http://localhost:3001/health"
    
    while [[ $attempt -le $max_attempts ]]; do
        if curl -fs "$health_endpoint" >/dev/null 2>&1; then
            log INFO "Health check passed"
            return 0
        fi
        
        log DEBUG "Health check attempt $attempt/$max_attempts failed, waiting..."
        sleep 10
        ((attempt++))
    done
    
    log ERROR "Health checks failed after $max_attempts attempts"
    return 1
}

# Performance test
run_performance_test() {
    log INFO "Running performance tests..."
    
    cd "$PROJECT_DIR"
    
    # Run quick performance check
    if npm run performance:quick >/dev/null 2>&1; then
        log INFO "Performance tests passed"
        return 0
    else
        log WARN "Performance tests failed or timed out"
        return 1
    fi
}

# Deploy application
deploy() {
    log INFO "Starting deployment to $ENVIRONMENT environment..."
    
    if [[ "$FORCE" != true ]]; then
        echo -n "Are you sure you want to deploy to $ENVIRONMENT? (y/N): "
        read -r confirmation
        if [[ "$confirmation" != "y" && "$confirmation" != "Y" ]]; then
            log INFO "Deployment cancelled"
            exit 0
        fi
    fi
    
    # Run pre-deployment checks
    pre_deployment_checks
    
    # Create backup
    create_backup
    
    # Update application images
    log INFO "Pulling latest images..."
    cd "$PROJECT_DIR"
    docker-compose -f "$DOCKER_COMPOSE_FILE" pull
    
    # Blue-Green deployment strategy
    log INFO "Starting blue-green deployment..."
    
    # Start new containers (green)
    docker-compose -f "$DOCKER_COMPOSE_FILE" up -d --force-recreate --remove-orphans
    
    # Wait for containers to be ready
    sleep 30
    
    # Run health checks
    if run_health_checks; then
        log INFO "New deployment is healthy"
        
        # Run performance tests
        if run_performance_test; then
            log INFO "Performance tests passed"
        else
            log WARN "Performance tests failed, but continuing deployment"
        fi
        
        # Clean up old images
        docker image prune -f
        
        log INFO "Deployment completed successfully!"
        
        # Show deployment status
        show_status
        
    else
        log ERROR "Health checks failed, rolling back..."
        rollback
        exit 1
    fi
}

# Rollback deployment
rollback() {
    log INFO "Starting rollback..."
    
    # Execute Phase 4 rollback procedures
    cd "$PROJECT_DIR"
    node scripts/phase4-rollback.js emergency
    
    # Stop current containers
    docker-compose -f "$DOCKER_COMPOSE_FILE" down
    
    # Find latest backup
    local latest_backup=$(ls -t "$BACKUP_DIR"/studyai_backup_*.tar.gz 2>/dev/null | head -n1)
    
    if [[ -n "$latest_backup" ]]; then
        log INFO "Restoring from backup: $latest_backup"
        
        # Extract backup
        local backup_dir=$(mktemp -d)
        tar -xzf "$latest_backup" -C "$backup_dir"
        local backup_name=$(basename "$latest_backup" .tar.gz)
        
        # Restore configuration
        cp -r "$backup_dir/$backup_name/config/"* "$PROJECT_DIR/config/" 2>/dev/null || true
        
        # Restart with previous configuration
        docker-compose -f "$PROJECT_DIR/$DOCKER_COMPOSE_FILE" up -d
        
        # Cleanup
        rm -rf "$backup_dir"
        
        log INFO "Rollback completed"
    else
        log WARN "No backup found, cannot restore previous state"
    fi
}

# Show deployment status
show_status() {
    log INFO "Deployment Status:"
    echo
    
    cd "$PROJECT_DIR"
    docker-compose -f "$DOCKER_COMPOSE_FILE" ps
    
    echo
    log INFO "Service Health:"
    
    # Check API Gateway
    if curl -fs http://localhost:3001/health >/dev/null 2>&1; then
        echo -e "  API Gateway: ${GREEN}✓ Healthy${NC}"
    else
        echo -e "  API Gateway: ${RED}✗ Unhealthy${NC}"
    fi
    
    # Check Redis
    if docker exec "studyai-redis-$ENVIRONMENT" redis-cli ping >/dev/null 2>&1; then
        echo -e "  Redis Cache: ${GREEN}✓ Healthy${NC}"
    else
        echo -e "  Redis Cache: ${RED}✗ Unhealthy${NC}"
    fi
    
    # Check Prometheus
    if curl -fs http://localhost:9090/-/healthy >/dev/null 2>&1; then
        echo -e "  Prometheus: ${GREEN}✓ Healthy${NC}"
    else
        echo -e "  Prometheus: ${RED}✗ Unhealthy${NC}"
    fi
    
    # Check Grafana
    if curl -fs http://localhost:3000/api/health >/dev/null 2>&1; then
        echo -e "  Grafana: ${GREEN}✓ Healthy${NC}"
    else
        echo -e "  Grafana: ${RED}✗ Unhealthy${NC}"
    fi
}

# Show logs
show_logs() {
    log INFO "Showing application logs..."
    cd "$PROJECT_DIR"
    docker-compose -f "$DOCKER_COMPOSE_FILE" logs -f --tail=100
}

# Main execution
main() {
    # Create required directories
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$(dirname "$LOG_FILE")"
    
    case $COMMAND in
        deploy)
            deploy
            ;;
        rollback)
            rollback
            ;;
        status)
            show_status
            ;;
        backup)
            create_backup
            ;;
        health)
            run_health_checks
            ;;
        logs)
            show_logs
            ;;
        *)
            log ERROR "Unknown command: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# Execute main function
main "$@"