#!/bin/bash
#
# BMv2 Setup Script for Planter Integration
# ==========================================
# 
# This script sets up the complete BMv2 environment for ML-based traffic classification.
# It replicates what the ansible playbook does, but as a standalone bash script.
#
# Topology:
#   h1 (10.0.1.1) <---> s1 <---> s2 <---> h2 (10.0.2.2)
#
# The switches run simple_switch with ML classification + routing.
# Traffic between h1 and h2 passes through both switches and gets classified.
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo_step() {
    echo -e "${GREEN}[STEP]${NC} $1"
}

echo_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# =============================================================================
# Configuration
# =============================================================================

# Host configuration
H1_NAME="h1"
H1_IP="10.0.1.1"
H1_MAC="00:00:00:00:01:01"
H1_GW_IP="10.0.1.254"
H1_GW_MAC="00:aa:00:00:01:01"

H2_NAME="h2"
H2_IP="10.0.2.2"
H2_MAC="00:00:00:00:02:02"
H2_GW_IP="10.0.2.254"
H2_GW_MAC="00:aa:00:00:01:02"

# Switch configuration
S1_NAME="s1"
S1_MAC="00:aa:00:00:01:01"
S1_THRIFT_PORT="9090"

S2_NAME="s2"
S2_MAC="00:aa:00:00:01:02"
S2_THRIFT_PORT="9090"

# =============================================================================
# Step 1: Compile P4 program
# =============================================================================

compile_p4() {
    echo_step "Compiling P4 program..."
    
    cd "$SCRIPT_DIR"
    
    # Copy the ML classifier P4 to bmv2/p4src
    mkdir -p "${SCRIPT_DIR}/p4src"
    if [ -f "${PROJECT_ROOT}/p4/ml_classifier.p4" ]; then
        cp "${PROJECT_ROOT}/p4/ml_classifier.p4" "${SCRIPT_DIR}/p4src/"
        echo_info "Copied ml_classifier.p4 to p4src/"
    fi
    
    # Check if router.json already exists and is newer than source
    if [ -f "build/router.json" ]; then
        echo_info "P4 program already compiled (build/router.json exists)"
        echo_info "Delete build/router.json to force recompilation"
        return 0
    fi
    
    mkdir -p build
    
    # Determine which P4 file to compile
    P4_FILE="ml_classifier.p4"
    if [ ! -f "p4src/${P4_FILE}" ]; then
        P4_FILE="router.p4"
    fi
    
    echo_info "Compiling ${P4_FILE} to JSON..."
    
    # Try to compile using docker
    docker run --rm -v "${SCRIPT_DIR}:/work" -w /work --platform linux/amd64 \
        p4lang/p4c:stable \
        p4c --std p4_16 \
        -b bmv2 -a v1model \
        --p4runtime-files build/p4info.txt --p4runtime-format text \
        -o build "p4src/${P4_FILE}" 2>&1 || {
            echo_error "P4 compilation failed"
            exit 1
        }
    
    # Rename to router.json for compatibility with switch Dockerfile
    OUTPUT_JSON="${P4_FILE%.p4}.json"
    if [ -f "build/${OUTPUT_JSON}" ] && [ "${OUTPUT_JSON}" != "router.json" ]; then
        mv "build/${OUTPUT_JSON}" "build/router.json"
        echo_info "Renamed build/${OUTPUT_JSON} to build/router.json"
    fi
    
    if [ -f "build/router.json" ]; then
        echo_info "P4 compilation successful: build/router.json"
    else
        echo_error "No router.json found. Compilation may have failed."
        exit 1
    fi
}

# =============================================================================
# Step 2: Start Docker containers
# =============================================================================

start_containers() {
    echo_step "Starting Docker containers..."
    
    cd "$SCRIPT_DIR"
    
    # Stop any existing containers first
    docker-compose down 2>/dev/null || true
    
    # Remove any conflicting containers
    docker rm -f h1 h2 s1 s2 2>/dev/null || true
    
    # Start fresh
    docker-compose up -d --build
    
    echo_info "Waiting for containers to start..."
    sleep 5
    
    # Verify all containers are running
    for container in h1 h2 s1 s2; do
        if ! docker ps --format '{{.Names}}' | grep -q "^${container}$"; then
            echo_error "Container ${container} is not running!"
            docker-compose logs "${container}"
            exit 1
        fi
    done
    
    echo_info "All containers started successfully"
}

# =============================================================================
# Step 3: Wait for network interfaces
# =============================================================================

wait_for_interfaces() {
    echo_step "Waiting for network interfaces..."
    
    for container in h1 h2 s1 s2; do
        echo_info "Waiting for eth0 in ${container}..."
        for i in $(seq 1 30); do
            if docker exec "${container}" ip link show eth0 >/dev/null 2>&1; then
                break
            fi
            sleep 1
        done
    done
    
    echo_info "All network interfaces ready"
}

# =============================================================================
# Step 4: Configure sysctl settings
# =============================================================================

configure_sysctl() {
    echo_step "Configuring sysctl settings..."
    
    SYSCTLS="net.ipv4.conf.all.arp_ignore=1
net.ipv4.conf.all.arp_announce=2
net.ipv4.conf.default.arp_ignore=1
net.ipv4.conf.default.arp_announce=2
net.ipv6.conf.all.disable_ipv6=1
net.ipv6.conf.default.disable_ipv6=1
net.ipv6.conf.lo.disable_ipv6=1"
    
    for container in h1 h2 s1 s2; do
        echo "$SYSCTLS" | while read sysctl; do
            docker exec "${container}" sysctl -w "${sysctl}" >/dev/null 2>&1 || true
        done
    done
    
    echo_info "sysctl settings configured"
}

# =============================================================================
# Step 5: Configure host networking
# =============================================================================

configure_hosts() {
    echo_step "Configuring host networking..."
    
    # Configure h1
    echo_info "Configuring h1 (${H1_IP})..."
    docker exec h1 sh -c "
        ip addr flush dev eth0
        ip addr add ${H1_IP}/24 dev eth0
        ip link set eth0 up
        ip route replace default via ${H1_GW_IP}
        ip neigh replace ${H1_GW_IP} lladdr ${H1_GW_MAC} dev eth0 nud permanent
    " || echo_error "Failed to configure h1"
    
    # Configure h2
    echo_info "Configuring h2 (${H2_IP})..."
    docker exec h2 sh -c "
        ip addr flush dev eth0
        ip addr add ${H2_IP}/24 dev eth0
        ip link set eth0 up
        ip route replace default via ${H2_GW_IP}
        ip neigh replace ${H2_GW_IP} lladdr ${H2_GW_MAC} dev eth0 nud permanent
    " || echo_error "Failed to configure h2"
    
    echo_info "Host networking configured"
}

# =============================================================================
# Step 6: Wait for switches to be ready
# =============================================================================

wait_for_switches() {
    echo_step "Waiting for switch pipelines..."
    
    for name in s1 s2; do
        echo_info "Waiting for ${name} pipeline to be ready..."
        for i in $(seq 1 60); do
            if docker exec "${name}" sh -c 'echo "show_tables" | simple_switch_CLI --thrift-port 9090' >/dev/null 2>&1; then
                echo_info "${name} is ready"
                break
            fi
            sleep 1
        done
    done
    
    echo_info "All switches ready"
}

# =============================================================================
# Step 7: Generate and load switch tables
# =============================================================================

generate_switch_commands() {
    echo_step "Generating combined switch commands..."
    
    mkdir -p "${SCRIPT_DIR}/cmds"
    
    # ML table commands (from generated_p4)
    ML_COMMANDS="${PROJECT_ROOT}/generated_p4/table_commands.txt"
    
    # S1 commands: MAC table + routing + ML
    cat > "${SCRIPT_DIR}/cmds/s1-combined.txt" << 'EOF'
# S1 Switch Configuration
# =======================

# Clear tables
table_clear my_mac
table_clear ipv4_lpm
table_clear ml_feature_0
table_clear ml_feature_1
table_clear ml_feature_2
table_clear ml_classify

# MAC table - accept packets for this switch
table_add my_mac mark_as_my_mac 00:aa:00:00:01:01 =>

# Routing table
# h1 is directly connected (same subnet)
table_add ipv4_lpm set_nhop 10.0.1.1/32 => 00:00:00:00:01:01 00:aa:00:00:01:01 0
# h2 goes through s2
table_add ipv4_lpm set_nhop 10.0.2.2/32 => 00:aa:00:00:01:02 00:aa:00:00:01:01 0
# Default route to s2 for 10.0.2.0/24
table_add ipv4_lpm set_nhop 10.0.2.0/24 => 00:aa:00:00:01:02 00:aa:00:00:01:01 0

EOF

    # Append ML commands if they exist
    if [ -f "$ML_COMMANDS" ]; then
        echo "# ML Classification Tables" >> "${SCRIPT_DIR}/cmds/s1-combined.txt"
        grep -v "^#" "$ML_COMMANDS" | grep -v "^$" >> "${SCRIPT_DIR}/cmds/s1-combined.txt" || true
    fi
    
    # S2 commands: MAC table + routing + ML
    cat > "${SCRIPT_DIR}/cmds/s2-combined.txt" << 'EOF'
# S2 Switch Configuration
# =======================

# Clear tables
table_clear my_mac
table_clear ipv4_lpm
table_clear ml_feature_0
table_clear ml_feature_1
table_clear ml_feature_2
table_clear ml_classify

# MAC table - accept packets for this switch
table_add my_mac mark_as_my_mac 00:aa:00:00:01:02 =>

# Routing table
# h1 goes through s1
table_add ipv4_lpm set_nhop 10.0.1.1/32 => 00:aa:00:00:01:01 00:aa:00:00:01:02 0
# h2 is directly connected
table_add ipv4_lpm set_nhop 10.0.2.2/32 => 00:00:00:00:02:02 00:aa:00:00:01:02 0
# Default route to s1 for 10.0.1.0/24
table_add ipv4_lpm set_nhop 10.0.1.0/24 => 00:aa:00:00:01:01 00:aa:00:00:01:02 0

EOF

    # Append ML commands if they exist
    if [ -f "$ML_COMMANDS" ]; then
        echo "# ML Classification Tables" >> "${SCRIPT_DIR}/cmds/s2-combined.txt"
        grep -v "^#" "$ML_COMMANDS" | grep -v "^$" >> "${SCRIPT_DIR}/cmds/s2-combined.txt" || true
    fi
    
    echo_info "Generated s1-combined.txt and s2-combined.txt"
}

load_tables() {
    echo_step "Loading switch tables..."
    
    # Generate combined command files
    generate_switch_commands
    
    # Load to s1
    echo_info "Loading tables for s1..."
    docker exec -i s1 simple_switch_CLI --thrift-port 9090 < "${SCRIPT_DIR}/cmds/s1-combined.txt" 2>&1 | head -20 || {
        echo_error "Failed to load tables for s1"
    }
    
    # Load to s2
    echo_info "Loading tables for s2..."
    docker exec -i s2 simple_switch_CLI --thrift-port 9090 < "${SCRIPT_DIR}/cmds/s2-combined.txt" 2>&1 | head -20 || {
        echo_error "Failed to load tables for s2"
    }
    
    echo_info "Switch tables loaded"
}

# =============================================================================
# Step 8: Verify connectivity
# =============================================================================

verify_connectivity() {
    echo_step "Verifying connectivity..."
    
    echo_info "Testing h1 -> h2 (10.0.2.2)..."
    if docker exec h1 ping -c 3 10.0.2.2; then
        echo -e "${GREEN}SUCCESS: h1 can reach h2${NC}"
    else
        echo_error "FAILED: h1 cannot reach h2"
        echo_info "Checking switch logs for debugging..."
        return 1
    fi
    
    echo_info "Testing h2 -> h1 (10.0.1.1)..."
    if docker exec h2 ping -c 3 10.0.1.1; then
        echo -e "${GREEN}SUCCESS: h2 can reach h1${NC}"
    else
        echo_error "FAILED: h2 cannot reach h1"
        return 1
    fi
}

# =============================================================================
# Helper functions
# =============================================================================

show_status() {
    echo ""
    echo "=========================================="
    echo "  BMv2 Environment Status"
    echo "=========================================="
    echo ""
    echo "Containers:"
    docker-compose ps 2>/dev/null || docker ps --filter "name=h1" --filter "name=h2" --filter "name=s1" --filter "name=s2" --format "table {{.Names}}\t{{.Status}}"
    echo ""
    echo "Host Configuration:"
    echo "  h1: ${H1_IP} -> gateway ${H1_GW_IP} (s1)"
    echo "  h2: ${H2_IP} -> gateway ${H2_GW_IP} (s2)"
    echo ""
    echo "Switch Configuration:"
    echo "  s1: MAC ${S1_MAC}, Thrift port ${S1_THRIFT_PORT}"
    echo "  s2: MAC ${S2_MAC}, Thrift port ${S2_THRIFT_PORT}"
    echo ""
}

show_logs() {
    local switch="${1:-s1}"
    echo "Logs for ${switch}:"
    docker logs --tail 100 "${switch}" 2>&1 | grep -E "ML CLASSIFICATION|ICMP|packet|log_msg" || echo "(no classification logs found)"
}

show_help() {
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  setup     Full setup (compile, start, configure, load tables)"
    echo "  start     Start containers only"
    echo "  stop      Stop containers"
    echo "  restart   Restart containers and reload tables"
    echo "  status    Show environment status"
    echo "  test      Test connectivity"
    echo "  logs [s1|s2]  Show switch logs"
    echo "  compile   Compile P4 program only"
    echo "  load      Load tables only (containers must be running)"
    echo "  help      Show this help"
    echo ""
}

# =============================================================================
# Main
# =============================================================================

main() {
    cd "$SCRIPT_DIR"
    
    case "${1:-setup}" in
        setup)
            compile_p4
            start_containers
            wait_for_interfaces
            configure_sysctl
            configure_hosts
            wait_for_switches
            load_tables
            show_status
            echo ""
            echo_step "Setup complete! Testing connectivity..."
            verify_connectivity || true
            ;;
        start)
            start_containers
            wait_for_interfaces
            configure_sysctl
            configure_hosts
            wait_for_switches
            load_tables
            ;;
        stop)
            echo_step "Stopping containers..."
            docker-compose down
            ;;
        restart)
            docker-compose down
            start_containers
            wait_for_interfaces
            configure_sysctl
            configure_hosts
            wait_for_switches
            load_tables
            verify_connectivity || true
            ;;
        status)
            show_status
            ;;
        test)
            verify_connectivity
            ;;
        logs)
            show_logs "${2:-s1}"
            ;;
        compile)
            compile_p4
            ;;
        load)
            wait_for_switches
            load_tables
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            echo_error "Unknown command: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
