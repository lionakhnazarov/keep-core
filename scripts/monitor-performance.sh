#!/bin/bash
# Monitor Keep Node Performance Metrics
# Usage: ./scripts/monitor-performance.sh [node_port] [node_log_file]

set -e

NODE_PORT=${1:-9601}
LOG_FILE=${2:-logs/node1.log}
METRICS_URL="http://localhost:${NODE_PORT}/metrics"
DIAGNOSTICS_URL="http://localhost:${NODE_PORT}/diagnostics"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Helper function to get metric value
get_metric() {
    local metric_name=$1
    curl -s "$METRICS_URL" | grep "^${metric_name} " | awk '{print $2}' || echo "0"
}

# Helper function to check if value exists
metric_exists() {
    local metric_name=$1
    curl -s "$METRICS_URL" | grep -q "^${metric_name} "
}

echo -e "${BLUE}=== Keep Node Performance Metrics ===${NC}"
echo "Timestamp: $(date)"
echo "Metrics URL: $METRICS_URL"
echo ""

# Check if metrics endpoint is accessible
if ! curl -s "$METRICS_URL" > /dev/null 2>&1; then
    echo -e "${RED}Error: Cannot access metrics endpoint at $METRICS_URL${NC}"
    echo "Make sure the node is running and the port is correct."
    exit 1
fi

# DKG Metrics
echo -e "${GREEN}--- DKG Metrics ---${NC}"
DKG_REQUESTED=$(get_metric "performance_dkg_requested_total")
DKG_JOINED=$(get_metric "performance_dkg_joined_total")
DKG_FAILED=$(get_metric "performance_dkg_failed_total")
DKG_VALIDATION=$(get_metric "performance_dkg_validation_total")
DKG_CHALLENGES=$(get_metric "performance_dkg_challenges_submitted_total")
DKG_APPROVALS=$(get_metric "performance_dkg_approvals_submitted_total")

if metric_exists "performance_dkg_duration_seconds "; then
    DKG_DURATION=$(get_metric "performance_dkg_duration_seconds ")
    DKG_COUNT=$(get_metric "performance_dkg_duration_seconds_count")
else
    DKG_DURATION="N/A"
    DKG_COUNT="0"
fi

echo "DKG Requested: ${DKG_REQUESTED}"
echo "DKG Joined: ${DKG_JOINED}"
echo "DKG Failed: ${DKG_FAILED}"
echo "DKG Validations: ${DKG_VALIDATION}"
echo "DKG Challenges: ${DKG_CHALLENGES}"
echo "DKG Approvals: ${DKG_APPROVALS}"

if [ "$DKG_COUNT" != "0" ] && [ -n "$DKG_DURATION" ] && [ "$DKG_DURATION" != "N/A" ]; then
    echo "Avg DKG Duration: ${DKG_DURATION}s (from ${DKG_COUNT} operations)"
fi

if [ "$DKG_JOINED" -gt 0 ] && [ "$DKG_FAILED" -gt 0 ]; then
    SUCCESS_RATE=$(echo "scale=2; ($DKG_JOINED - $DKG_FAILED) * 100 / $DKG_JOINED" | bc 2>/dev/null || echo "N/A")
    if [ "$SUCCESS_RATE" != "N/A" ]; then
        if (( $(echo "$SUCCESS_RATE < 95" | bc -l 2>/dev/null || echo 0) )); then
            echo -e "${RED}DKG Success Rate: ${SUCCESS_RATE}% (LOW)${NC}"
        else
            echo -e "${GREEN}DKG Success Rate: ${SUCCESS_RATE}%${NC}"
        fi
    fi
fi

if [ "$DKG_REQUESTED" -gt 0 ]; then
    PARTICIPATION_RATE=$(echo "scale=2; $DKG_JOINED * 100 / $DKG_REQUESTED" | bc 2>/dev/null || echo "N/A")
    if [ "$PARTICIPATION_RATE" != "N/A" ]; then
        echo "DKG Participation Rate: ${PARTICIPATION_RATE}%"
    fi
fi

echo ""

# Wallet Action Metrics (Deposits & Redemptions)
echo -e "${GREEN}--- Wallet Action Metrics (Deposits & Redemptions) ---${NC}"
WALLET_ACTIONS=$(get_metric "performance_wallet_actions_total")
WALLET_SUCCESS=$(get_metric "performance_wallet_action_success_total")
WALLET_FAILED=$(get_metric "performance_wallet_action_failed_total")

if metric_exists "performance_wallet_action_duration_seconds "; then
    WALLET_DURATION=$(get_metric "performance_wallet_action_duration_seconds ")
    WALLET_COUNT=$(get_metric "performance_wallet_action_duration_seconds_count")
else
    WALLET_DURATION="N/A"
    WALLET_COUNT="0"
fi

echo "Total Wallet Actions: ${WALLET_ACTIONS}"
echo "Successful: ${WALLET_SUCCESS}"
echo "Failed: ${WALLET_FAILED}"

if [ "$WALLET_COUNT" != "0" ] && [ -n "$WALLET_DURATION" ] && [ "$WALLET_DURATION" != "N/A" ]; then
    echo "Avg Duration: ${WALLET_DURATION}s (from ${WALLET_COUNT} operations)"
fi

if [ "$WALLET_ACTIONS" -gt 0 ] && [ "$WALLET_FAILED" -gt 0 ]; then
    SUCCESS_RATE=$(echo "scale=2; ($WALLET_ACTIONS - $WALLET_FAILED) * 100 / $WALLET_ACTIONS" | bc 2>/dev/null || echo "N/A")
    if [ "$SUCCESS_RATE" != "N/A" ]; then
        if (( $(echo "$SUCCESS_RATE < 98" | bc -l 2>/dev/null || echo 0) )); then
            echo -e "${RED}Success Rate: ${SUCCESS_RATE}% (LOW)${NC}"
        else
            echo -e "${GREEN}Success Rate: ${SUCCESS_RATE}%${NC}"
        fi
    fi
fi

echo ""

# Signing Metrics
echo -e "${GREEN}--- Signing Metrics ---${NC}"
SIGNING_OPS=$(get_metric "performance_signing_operations_total")
SIGNING_SUCCESS=$(get_metric "performance_signing_success_total")
SIGNING_FAILED=$(get_metric "performance_signing_failed_total")
SIGNING_TIMEOUTS=$(get_metric "performance_signing_timeouts_total")

if metric_exists "performance_signing_duration_seconds "; then
    SIGNING_DURATION=$(get_metric "performance_signing_duration_seconds ")
    SIGNING_COUNT=$(get_metric "performance_signing_duration_seconds_count")
else
    SIGNING_DURATION="N/A"
    SIGNING_COUNT="0"
fi

echo "Total Signing Operations: ${SIGNING_OPS}"
echo "Successful: ${SIGNING_SUCCESS}"
echo "Failed: ${SIGNING_FAILED}"
echo "Timeouts: ${SIGNING_TIMEOUTS}"

if [ "$SIGNING_COUNT" != "0" ] && [ -n "$SIGNING_DURATION" ] && [ "$SIGNING_DURATION" != "N/A" ]; then
    echo "Avg Duration: ${SIGNING_DURATION}s (from ${SIGNING_COUNT} operations)"
fi

if [ "$SIGNING_OPS" -gt 0 ] && [ "$SIGNING_FAILED" -gt 0 ]; then
    SUCCESS_RATE=$(echo "scale=2; ($SIGNING_OPS - $SIGNING_FAILED) * 100 / $SIGNING_OPS" | bc 2>/dev/null || echo "N/A")
    if [ "$SUCCESS_RATE" != "N/A" ]; then
        if (( $(echo "$SUCCESS_RATE < 95" | bc -l 2>/dev/null || echo 0) )); then
            echo -e "${RED}Success Rate: ${SUCCESS_RATE}% (LOW)${NC}"
        else
            echo -e "${GREEN}Success Rate: ${SUCCESS_RATE}%${NC}"
        fi
    fi
fi

echo ""

# Network Health
echo -e "${GREEN}--- Network Health ---${NC}"
if command -v jq > /dev/null 2>&1; then
    PEERS=$(curl -s "$DIAGNOSTICS_URL" 2>/dev/null | jq -r '.connected_peers | length' 2>/dev/null || echo "N/A")
    ETH_CONNECTIVITY=$(curl -s "$METRICS_URL" | grep "^eth_connectivity " | awk '{print $2}' || echo "N/A")
    BTC_CONNECTIVITY=$(curl -s "$METRICS_URL" | grep "^btc_connectivity " | awk '{print $2}' || echo "N/A")
    
    echo "Connected Peers: ${PEERS}"
    
    if [ "$ETH_CONNECTIVITY" != "N/A" ]; then
        if [ "$ETH_CONNECTIVITY" = "1" ]; then
            echo -e "${GREEN}Ethereum Connectivity: OK${NC}"
        else
            echo -e "${RED}Ethereum Connectivity: FAILED${NC}"
        fi
    fi
    
    if [ "$BTC_CONNECTIVITY" != "N/A" ]; then
        if [ "$BTC_CONNECTIVITY" = "1" ]; then
            echo -e "${GREEN}Bitcoin Connectivity: OK${NC}"
        else
            echo -e "${RED}Bitcoin Connectivity: FAILED${NC}"
        fi
    fi
else
    echo "Install 'jq' for network diagnostics"
    PEERS=$(curl -s "$METRICS_URL" | grep "^connected_peers_count " | awk '{print $2}' || echo "N/A")
    echo "Connected Peers: ${PEERS}"
fi

echo ""

# Redemption-Specific Metrics from Logs
if [ -f "$LOG_FILE" ]; then
    echo -e "${GREEN}--- Redemption Metrics (from logs) ---${NC}"
    
    # Count redemption actions
    REDEMPTION_STARTED=$(grep -c "starting orchestration of the redemption action\|dispatching wallet action.*redemption" "$LOG_FILE" 2>/dev/null || echo "0")
    REDEMPTION_SUCCESS=$(grep -c "action execution terminated with success.*redemption\|wallet action.*redemption.*success" "$LOG_FILE" 2>/dev/null || echo "0")
    REDEMPTION_FAILED=$(grep -c "action execution terminated with error.*redemption\|wallet action.*redemption.*error\|redemption.*failed" "$LOG_FILE" 2>/dev/null || echo "0")
    
    echo "Redemptions Started: ${REDEMPTION_STARTED}"
    echo "Redemptions Successful: ${REDEMPTION_SUCCESS}"
    echo "Redemptions Failed: ${REDEMPTION_FAILED}"
    
    if [ "$REDEMPTION_STARTED" -gt 0 ]; then
        if [ "$REDEMPTION_FAILED" -gt 0 ] || [ "$REDEMPTION_SUCCESS" -gt 0 ]; then
            TOTAL_COMPLETED=$((REDEMPTION_SUCCESS + REDEMPTION_FAILED))
            if [ "$TOTAL_COMPLETED" -gt 0 ]; then
                REDEMPTION_SUCCESS_RATE=$(echo "scale=2; $REDEMPTION_SUCCESS * 100 / $TOTAL_COMPLETED" | bc 2>/dev/null || echo "N/A")
                if [ "$REDEMPTION_SUCCESS_RATE" != "N/A" ]; then
                    if (( $(echo "$REDEMPTION_SUCCESS_RATE < 95" | bc -l 2>/dev/null || echo 0) )); then
                        echo -e "${RED}Redemption Success Rate: ${REDEMPTION_SUCCESS_RATE}% (LOW)${NC}"
                    else
                        echo -e "${GREEN}Redemption Success Rate: ${REDEMPTION_SUCCESS_RATE}%${NC}"
                    fi
                fi
            fi
        fi
    fi
    
    echo ""
fi

# Recent Activity from Logs (if log file exists)
if [ -f "$LOG_FILE" ]; then
    echo -e "${GREEN}--- Recent Activity (Last 5 minutes) ---${NC}"
    
    # Count recent DKG activity
    RECENT_DKG=$(grep "$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M' 2>/dev/null || date -u -v-5M '+%Y-%m-%dT%H:%M' 2>/dev/null || echo "")" "$LOG_FILE" 2>/dev/null | grep -c "DKG started" || echo "0")
    echo "DKG Started (last 5min): ${RECENT_DKG}"
    
    # Count recent wallet actions
    RECENT_WALLET=$(grep "$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M' 2>/dev/null || date -u -v-5M '+%Y-%m-%dT%H:%M' 2>/dev/null || echo "")" "$LOG_FILE" 2>/dev/null | grep -c "wallet action" || echo "0")
    echo "Wallet Actions (last 5min): ${RECENT_WALLET}"
    
    # Count recent redemptions
    RECENT_REDEMPTIONS=$(grep "$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M' 2>/dev/null || date -u -v-5M '+%Y-%m-%dT%H:%M' 2>/dev/null || echo "")" "$LOG_FILE" 2>/dev/null | grep -c "redemption action\|redemption proposal" || echo "0")
    echo "Redemptions (last 5min): ${RECENT_REDEMPTIONS}"
    
    # Count recent errors
    RECENT_ERRORS=$(grep "$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M' 2>/dev/null || date -u -v-5M '+%Y-%m-%dT%H:%M' 2>/dev/null || echo "")" "$LOG_FILE" 2>/dev/null | grep -ci "error\|failed\|timeout" || echo "0")
    if [ "$RECENT_ERRORS" -gt 0 ]; then
        echo -e "${YELLOW}Recent Errors/Warnings (last 5min): ${RECENT_ERRORS}${NC}"
    else
        echo "Recent Errors/Warnings (last 5min): 0"
    fi
else
    echo -e "${YELLOW}Log file not found: $LOG_FILE${NC}"
fi

echo ""
echo -e "${BLUE}=== End of Report ===${NC}"

