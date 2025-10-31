#!/bin/bash
# =============================================================================
# Docker Health Check Hook
# Validates Docker containers are built and running properly
# =============================================================================

set -euo pipefail

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROJECT_ROOT="$(pwd)"
readonly HEALTH_REPORT="${PROJECT_ROOT}/.docker-health.json"
readonly MAX_WAIT=300  # 5 minutes
readonly CHECK_INTERVAL=10

# Colors
readonly GREEN='\033[0;32m'
readonly RED='\033[0;31m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Check if Docker Compose exists
check_docker_compose() {
    if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        return 0
    fi
    return 1
}

# Build Docker containers
build_containers() {
    echo -e "${YELLOW}Building Docker containers...${NC}"
    
    if docker-compose build; then
        echo -e "${GREEN}✅ Containers built successfully${NC}"
        return 0
    else
        echo -e "${RED}❌ Container build failed${NC}"
        return 1
    fi
}

# Start Docker containers
start_containers() {
    echo -e "${YELLOW}Starting Docker containers...${NC}"
    
    if docker-compose up -d; then
        echo -e "${GREEN}✅ Containers started${NC}"
        return 0
    else
        echo -e "${RED}❌ Failed to start containers${NC}"
        return 1
    fi
}

# Wait for containers to be healthy
wait_for_healthy() {
    echo -e "${YELLOW}Waiting for containers to be healthy...${NC}"
    
    local elapsed=0
    while [ $elapsed -lt $MAX_WAIT ]; do
        # Get container statuses
        local unhealthy=$(docker-compose ps 2>/dev/null | grep -c "unhealthy\|starting\|restarting" || echo "0")
        local total=$(docker-compose ps 2>/dev/null | grep -c "Up" || echo "0")
        
        if [ "$unhealthy" -eq 0 ] && [ "$total" -gt 0 ]; then
            echo -e "${GREEN}✅ All $total containers healthy!${NC}"
            return 0
        fi
        
        echo "  Waiting... ($elapsed/$MAX_WAIT seconds) - $total containers up, $unhealthy unhealthy"
        sleep $CHECK_INTERVAL
        elapsed=$((elapsed + CHECK_INTERVAL))
    done
    
    echo -e "${RED}❌ Timeout waiting for healthy containers${NC}"
    return 1
}

# Check individual services
check_services() {
    echo -e "${YELLOW}Checking individual services...${NC}"
    
    local services=$(docker-compose ps --services 2>/dev/null)
    local all_healthy=true
    
    while IFS= read -r service; do
        if [ -z "$service" ]; then
            continue
        fi
        
        # Check if service is running
        if docker-compose ps "$service" 2>/dev/null | grep -q "Up"; then
            echo -e "  ${GREEN}✓${NC} $service: Running"
            
            # Try to get health status
            local container=$(docker-compose ps -q "$service" 2>/dev/null)
            if [ -n "$container" ]; then
                local health=$(docker inspect "$container" 2>/dev/null | jq -r '.[0].State.Health.Status // "none"')
                if [ "$health" = "healthy" ]; then
                    echo -e "    Health: ${GREEN}Healthy${NC}"
                elif [ "$health" = "unhealthy" ]; then
                    echo -e "    Health: ${RED}Unhealthy${NC}"
                    all_healthy=false
                fi
            fi
        else
            echo -e "  ${RED}✗${NC} $service: Not running"
            all_healthy=false
        fi
    done <<< "$services"
    
    if [ "$all_healthy" = true ]; then
        return 0
    else
        return 1
    fi
}

# Generate health report
generate_report() {
    local status=$1
    
    # Get container information
    local containers=$(docker-compose ps --format json 2>/dev/null || echo '[]')
    
    cat > "$HEALTH_REPORT" << EOF
{
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "status": "$status",
    "containers": $containers,
    "services": {
EOF
    
    # Add service URLs if available
    if [ -f "docker-compose.yml" ]; then
        # Extract exposed ports
        local api_port=$(grep -A5 "ports:" docker-compose.yml | grep -oE "8[0-9]{3}" | head -1 || echo "8000")
        local db_port=$(grep -A5 "postgres\|mysql\|mongo" docker-compose.yml | grep -oE "[0-9]{4}" | head -1 || echo "5432")
        
        cat >> "$HEALTH_REPORT" << EOF
        "api": "http://localhost:$api_port",
        "database": "localhost:$db_port"
EOF
    fi
    
    cat >> "$HEALTH_REPORT" << EOF
    }
}
EOF
}

# Show container logs if unhealthy
show_unhealthy_logs() {
    echo -e "${YELLOW}Showing logs for unhealthy containers:${NC}"
    
    local unhealthy=$(docker-compose ps 2>/dev/null | grep "unhealthy\|Exit\|Restarting" | awk '{print $1}')
    
    while IFS= read -r container; do
        if [ -n "$container" ]; then
            echo -e "${YELLOW}Logs for $container:${NC}"
            docker-compose logs --tail=20 "$container" 2>/dev/null
            echo ""
        fi
    done <<< "$unhealthy"
}

# Main execution
main() {
    echo ""
    echo "╔══════════════════════════════════════════╗"
    echo "║   DOCKER INFRASTRUCTURE VALIDATION       ║"
    echo "╚══════════════════════════════════════════╝"
    echo ""
    
    # Check if Docker Compose exists
    if ! check_docker_compose; then
        echo -e "${YELLOW}No Docker Compose file found. Skipping infrastructure validation.${NC}"
        generate_report "not_applicable"
        exit 0
    fi
    
    # Build containers
    if ! build_containers; then
        generate_report "build_failed"
        exit 1
    fi
    
    # Start containers
    if ! start_containers; then
        generate_report "start_failed"
        exit 1
    fi
    
    # Wait for healthy status
    if ! wait_for_healthy; then
        show_unhealthy_logs
        generate_report "unhealthy"
        exit 1
    fi
    
    # Check individual services
    if ! check_services; then
        show_unhealthy_logs
        generate_report "service_check_failed"
        exit 1
    fi
    
    # Success!
    generate_report "healthy"
    
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  INFRASTRUCTURE READY FOR DEMO!${NC}"
    echo -e "${GREEN}════════════════════════════════════════════${NC}"
    echo ""
    
    # Show access information
    if [ -f "docker-compose.yml" ]; then
        echo "Service URLs:"
        jq -r '.services | to_entries[] | "  • \(.key): \(.value)"' "$HEALTH_REPORT" 2>/dev/null || true
        echo ""
    fi
    
    echo "Health report saved to: $HEALTH_REPORT"
    echo ""
    
    # Signal success
    echo "DOCKER_INFRASTRUCTURE_READY" > "${PROJECT_ROOT}/.claude/.pipeline-signal" 2>/dev/null || true
}

# Run health check
main "$@"