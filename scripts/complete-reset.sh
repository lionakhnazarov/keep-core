#!/bin/bash
# Complete environment reset script
# This script completely resets the development environment:
# 1. Stops Geth
# 2. Deletes all chaindata
# 3. Cleans all deployment files
# 4. Starts Geth
# 5. Deploys all contracts
# 6. Initializes operators
# 7. Updates config files
#
# Usage:
#   ./scripts/complete-reset.sh [--non-interactive]
#
# Options:
#   --non-interactive    Skip all prompts (use with caution!)

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
KEEP_ETHEREUM_PASSWORD="${KEEP_ETHEREUM_PASSWORD:-password}"
RPC_URL="http://localhost:8545"
WS_URL="ws://localhost:8546"

# Check for non-interactive mode
NON_INTERACTIVE=false
if [[ "$*" == *"--non-interactive"* ]]; then
    NON_INTERACTIVE=true
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

wait_for_geth() {
    log_info "Waiting for Geth to be ready..."
    local max_attempts=30
    local attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if cast block-number --rpc-url "$RPC_URL" >/dev/null 2>&1; then
            log_success "Geth is ready!"
            return 0
        fi
        attempt=$((attempt + 1))
        sleep 1
    done
    
    log_error "Geth did not become ready in time"
    return 1
}

unlock_accounts() {
    log_info "Unlocking Ethereum accounts..."
    
    # Wait a bit for Geth to fully initialize accounts
    sleep 2
    
    # Try using Hardhat unlock-accounts task first (more reliable)
    if [ -d "$PROJECT_ROOT/solidity/random-beacon" ]; then
        log_info "Using Hardhat unlock-accounts task..."
        cd "$PROJECT_ROOT/solidity/random-beacon"
        KEEP_ETHEREUM_PASSWORD="$KEEP_ETHEREUM_PASSWORD" npx hardhat unlock-accounts --network development >/dev/null 2>&1 || {
            log_warning "Hardhat unlock-accounts failed, trying cast method..."
        }
    fi
    
    # Also try cast method as fallback
    local accounts
    accounts=$(cast rpc eth_accounts --rpc-url "$RPC_URL" 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
    
    if [ -z "$accounts" ] || [ "$accounts" = "" ]; then
        log_warning "No accounts found to unlock via cast"
        log_info "Accounts will be unlocked when needed by Hardhat"
        return
    fi
    
    local unlocked=0
    while IFS= read -r addr; do
        if [ -n "$addr" ] && [ "$addr" != "null" ]; then
            # Try unlocking with cast
            if cast rpc "personal_unlockAccount" "[\"$addr\",\"$KEEP_ETHEREUM_PASSWORD\",0]" --rpc-url "$RPC_URL" >/dev/null 2>&1; then
                unlocked=$((unlocked + 1))
            fi
        fi
    done <<< "$accounts"
    
    if [ $unlocked -gt 0 ]; then
        log_success "Unlocked $unlocked account(s) via cast"
    else
        log_info "Accounts will be unlocked automatically by Hardhat when needed"
    fi
}

# Main execution
main() {
    echo "=========================================="
    echo "Complete Environment Reset"
    echo "=========================================="
    echo ""
    log_warning "This will:"
    echo "  - Stop Geth (if running)"
    echo "  - Delete all chaindata"
    echo "  - Clean all deployment files"
    echo "  - Redeploy all contracts"
    echo "  - Deploy and setup ReimbursementPool (authorize WalletRegistry, fund with ETH)"
    echo "  - Ensure WalletRegistry uses correct ReimbursementPool address (update via governance if needed)"
    echo "  - Deploy Bridge contract (if not already deployed)"
    echo "  - Initialize WalletRegistry walletOwner"
    echo "  - Initialize all operators"
    echo "  - Fund operators with ETH"
    echo "  - Join operators to sortition pools"
    echo "  - Set DKG parameters"
    echo "  - Update DKG resultSubmissionTimeout to 4000 blocks (for 100-member DKG with retries)"
    echo "  - Update config files"
    echo "  - Restart all nodes"
    echo "  - Fix RandomBeacon configuration (upgrade and authorize)"
    echo ""
    echo "Press Ctrl+C to cancel, or Enter to continue..."
    read
    
    cd "$PROJECT_ROOT"
    
    # Step 1: Stop Geth
    log_info "Step 1: Stopping Geth..."
    if pgrep -f "geth.*8545" > /dev/null; then
        pkill -f "geth.*8545" || true
        sleep 3
        log_success "Geth stopped"
    else
        log_info "Geth is not running"
    fi
    
    # Step 2: Delete chaindata
    log_info "Step 2: Deleting chaindata..."
    if [ -d "$HOME/ethereum/data/geth" ]; then
        rm -rf "$HOME/ethereum/data/geth"
        log_success "Chaindata deleted"
    else
        log_info "No chaindata found"
    fi
    
    # Step 2.5: Initialize genesis.json with Clique consensus (1 second block time)
    log_info "Step 2.5: Initializing genesis.json with Clique consensus..."
    GETH_DATA_DIR="$HOME/ethereum/data"
    GENESIS_FILE="$GETH_DATA_DIR/genesis.json"
    mkdir -p "$GETH_DATA_DIR"
    
    # Get signer account (first account in keystore)
    SIGNER_ACCOUNT=""
    if [ -d "$GETH_DATA_DIR/keystore" ]; then
        SIGNER_ACCOUNT=$(geth account list --keystore "$GETH_DATA_DIR/keystore" 2>/dev/null | head -1 | grep -o '{[^}]*}' | sed 's/{//;s/}//' | sed 's/^/0x/' || echo "")
    fi
    
    # If no signer found, use default or create one
    if [ -z "$SIGNER_ACCOUNT" ]; then
        log_warning "No signer account found, will use first account from start-geth-fast.sh"
        SIGNER_ACCOUNT="0x7966c178f466b060aaeb2b91e9149a5fb2ec9c53"  # Default fallback
    fi
    
    log_info "Using signer account: $SIGNER_ACCOUNT"
    
    # Check if genesis.json exists
    if [ -f "$GENESIS_FILE" ]; then
        log_info "Updating existing genesis.json with Clique config..."
        # Backup existing genesis
        cp "$GENESIS_FILE" "${GENESIS_FILE}.backup"
        
        # Update genesis.json to include Clique config with 1 second period
        SIGNER_HEX="${SIGNER_ACCOUNT#0x}"
        EXTRA_DATA="0x$(printf '0%.0s' {1..64})${SIGNER_HEX}$(printf '0%.0s' {1..130})"
        
        # Update genesis.json using jq
        if command -v jq >/dev/null 2>&1; then
            # Add Clique config if not present
            if ! jq -e '.config.clique' "$GENESIS_FILE" >/dev/null 2>&1; then
                jq '.config.clique = {"period": 1, "epoch": 30000}' "$GENESIS_FILE" > "${GENESIS_FILE}.tmp" && mv "${GENESIS_FILE}.tmp" "$GENESIS_FILE"
                log_success "Added Clique config to genesis.json"
            else
                # Update period to 1 second
                jq '.config.clique.period = 1' "$GENESIS_FILE" > "${GENESIS_FILE}.tmp" && mv "${GENESIS_FILE}.tmp" "$GENESIS_FILE"
                log_success "Updated Clique period to 1 second"
            fi
            
            # Update extraData with signer
            jq --arg extraData "$EXTRA_DATA" '.extraData = $extraData' "$GENESIS_FILE" > "${GENESIS_FILE}.tmp" && mv "${GENESIS_FILE}.tmp" "$GENESIS_FILE"
            log_success "Updated extraData with signer"
        else
            log_warning "jq not found, cannot update genesis.json automatically"
            log_info "Please ensure genesis.json has Clique config with period: 1"
        fi
    else
        log_info "Creating new genesis.json with Clique PoA (1 second block time)..."
        
        # Prepare extraData with signer
        SIGNER_HEX="${SIGNER_ACCOUNT#0x}"
        EXTRA_DATA="0x$(printf '0%.0s' {1..64})${SIGNER_HEX}$(printf '0%.0s' {1..130})"
        
        # Create genesis.json with Clique PoA configuration
        # Use jq to create properly formatted JSON
        if command -v jq >/dev/null 2>&1; then
            jq -n \
                --arg extraData "$EXTRA_DATA" \
                '{
                  "config": {
                    "chainId": 1101,
                    "homesteadBlock": 0,
                    "eip150Block": 0,
                    "eip155Block": 0,
                    "eip158Block": 0,
                    "byzantiumBlock": 0,
                    "constantinopleBlock": 0,
                    "petersburgBlock": 0,
                    "istanbulBlock": 0,
                    "clique": {
                      "period": 1,
                      "epoch": 30000
                    }
                  },
                  "difficulty": "0x1",
                  "gasLimit": "0x7A1200",
                  "extraData": $extraData,
                  "alloc": {}
                }' > "$GENESIS_FILE"
            log_success "Created genesis.json with Clique PoA (period: 1s)"
        else
            # Fallback: create JSON manually (less reliable)
            cat > "$GENESIS_FILE" <<GENESIS_EOF
{
  "config": {
    "chainId": 1101,
    "homesteadBlock": 0,
    "eip150Block": 0,
    "eip155Block": 0,
    "eip158Block": 0,
    "byzantiumBlock": 0,
    "constantinopleBlock": 0,
    "petersburgBlock": 0,
    "istanbulBlock": 0,
    "clique": {
      "period": 1,
      "epoch": 30000
    }
  },
  "difficulty": "0x1",
  "gasLimit": "0x7A1200",
  "extraData": "${EXTRA_DATA}",
  "alloc": {}
}
GENESIS_EOF
            log_success "Created genesis.json with Clique PoA (period: 1s)"
        fi
    fi
    
    # Initialize chain with genesis.json
    log_info "Initializing chain with genesis.json..."
    if geth --datadir="$GETH_DATA_DIR" init "$GENESIS_FILE" 2>&1 | grep -E "(Successfully|Writing|Fatal)" | tail -3; then
        log_success "Chain initialized with Clique consensus (1 second block time)"
    else
        log_warning "Chain initialization may have issues - check output above"
    fi
    echo ""
    
    # Step 3: Clean deployment files
    log_info "Step 3: Cleaning deployment files..."
    
    # Clean RandomBeacon deployments
    if [ -d "$PROJECT_ROOT/solidity/random-beacon/deployments/development" ]; then
        rm -f "$PROJECT_ROOT/solidity/random-beacon/deployments/development"/*.json 2>/dev/null || true
        log_success "RandomBeacon deployments cleaned"
    fi
    
    # Clean ECDSA deployments
    if [ -d "$PROJECT_ROOT/solidity/ecdsa/deployments/development" ]; then
        rm -f "$PROJECT_ROOT/solidity/ecdsa/deployments/development"/*.json 2>/dev/null || true
        log_success "ECDSA deployments cleaned"
    fi
    
    # Clean OpenZeppelin manifest
    if [ -d "$PROJECT_ROOT/solidity/ecdsa/.openzeppelin" ]; then
        rm -rf "$PROJECT_ROOT/solidity/ecdsa/.openzeppelin" 2>/dev/null || true
        log_success "OpenZeppelin manifest cleaned"
    fi
    
    # Clean tBTC stub deployments
    if [ -d "$PROJECT_ROOT/solidity/tbtc-stub/deployments/development" ]; then
        rm -f "$PROJECT_ROOT/solidity/tbtc-stub/deployments/development"/*.json 2>/dev/null || true
        log_success "tBTC stub deployments cleaned"
    fi
    
    # Clean tBTC v2 deployments (including Bridge)
    if [ -d "$PROJECT_ROOT/tmp/tbtc-v2/solidity/deployments/development" ]; then
        rm -f "$PROJECT_ROOT/tmp/tbtc-v2/solidity/deployments/development"/*.json 2>/dev/null || true
        log_success "tBTC v2 deployments cleaned"
    fi
    
    # Clean T token deployments
    if [ -d "$PROJECT_ROOT/tmp/solidity-contracts/deployments/development" ]; then
        rm -f "$PROJECT_ROOT/tmp/solidity-contracts/deployments/development"/*.json 2>/dev/null || true
        log_success "T token deployments cleaned"
    fi
    
    echo ""
    log_success "Reset complete!"
    echo ""
    
    # Step 4: Start Geth
    log_info "Step 4: Starting Geth with Clique consensus (1 second block time)..."
    if [ -f "$PROJECT_ROOT/scripts/start-geth-fast.sh" ]; then
        log_info "Found start-geth-fast.sh, starting Geth in background..."
        cd "$PROJECT_ROOT"
        # Start with 1 second block period (fastest Clique supports)
        BLOCK_PERIOD=1 nohup ./scripts/start-geth-fast.sh "$HOME/ethereum/data" 1 > /tmp/geth.log 2>&1 &
        GETH_PID=$!
        log_info "Geth started (PID: $GETH_PID)"
        log_info "Logs: tail -f /tmp/geth.log"
        log_info "Waiting a few seconds for Geth to initialize..."
        sleep 5
    else
        log_warning "start-geth-fast.sh not found"
        log_info "Please start Geth manually or use your start script"
        log_info "Example: geth --dev --http --http.addr 0.0.0.0 --http.port 8545 --http.api eth,web3,personal,net --ws --ws.addr 0.0.0.0 --ws.port 8546 --ws.api eth,web3,personal,net --allow-insecure-unlock --datadir $HOME/ethereum/data"
        echo ""
        if [ "$NON_INTERACTIVE" = false ]; then
            echo "Press Enter once Geth is running..."
            read
        else
            log_warning "Non-interactive mode: waiting for Geth to be available..."
        fi
    fi
    
    # Wait for Geth
    if ! wait_for_geth; then
        log_error "Failed to connect to Geth. Please ensure it's running and try again."
        exit 1
    fi
    
    # Wait a bit more for accounts to be available
    log_info "Waiting for accounts to be available..."
    sleep 3
    
    # Step 5: Unlock accounts
    unlock_accounts
    echo ""
    
    # Step 6: Deploy T token
    log_info "Step 6: Deploying T token..."
    if [ -d "$PROJECT_ROOT/tmp/solidity-contracts" ]; then
        cd "$PROJECT_ROOT/tmp/solidity-contracts"
        
        # Unlock accounts specifically for T token deployment
        log_info "Unlocking accounts for T token deployment..."
        
        # Wait for accounts to be available
        sleep 3
        
        local accounts
        accounts=$(cast rpc eth_accounts --rpc-url "$RPC_URL" 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
        
        if [ -z "$accounts" ] || [ "$accounts" = "" ]; then
            log_warning "No accounts found, waiting a bit more..."
            sleep 2
            accounts=$(cast rpc eth_accounts --rpc-url "$RPC_URL" 2>/dev/null | jq -r '.[]' 2>/dev/null || echo "")
        fi
        
        if [ -n "$accounts" ] && [ "$accounts" != "" ]; then
            log_info "Found accounts, unlocking all..."
            local unlocked=0
            local failed=0
            while IFS= read -r addr; do
                if [ -n "$addr" ] && [ "$addr" != "null" ]; then
                    # Unlock with duration 0 (indefinite unlock)
                    # Use positional arguments: cast rpc personal_unlockAccount <addr> <password> <duration>
                    if cast rpc personal_unlockAccount --rpc-url "$RPC_URL" "$addr" "$KEEP_ETHEREUM_PASSWORD" 0 >/dev/null 2>&1; then
                        unlocked=$((unlocked + 1))
                    else
                        failed=$((failed + 1))
                        # Don't log every failure to avoid spam, but track count
                    fi
                fi
            done <<< "$accounts"
            if [ $unlocked -gt 0 ]; then
                log_success "Unlocked $unlocked account(s)"
            fi
            if [ $failed -gt 0 ]; then
                log_warning "$failed account(s) failed to unlock (may already be unlocked)"
            fi
        else
            log_warning "No accounts found to unlock - Geth may need more time to initialize"
        fi
        
        # Wait a moment for unlocks to propagate
        sleep 2
        
        yarn deploy --network development --reset || {
            log_error "T token deployment failed"
            log_info "This might be due to account unlocking issues."
            log_info "Try manually unlocking accounts:"
            log_info "  cast rpc eth_accounts --rpc-url $RPC_URL | jq -r '.[]' | while read addr; do cast rpc \"personal_unlockAccount\" [\"\$addr\",\"$KEEP_ETHEREUM_PASSWORD\",0] --rpc-url $RPC_URL; done"
            log_info "Or check Geth logs: tail -f /tmp/geth.log"
            exit 1
        }
        log_success "T token deployed"
    else
        log_warning "tmp/solidity-contracts directory not found, skipping T token deployment"
    fi
    echo ""
    
    # Step 6.5: Deploy ExtendedTokenStaking (needed before RandomBeacon for development)
    log_info "Step 6.5: Deploying ExtendedTokenStaking..."
    cd "$PROJECT_ROOT/solidity/ecdsa"
    npx hardhat deploy --network development --tags ExtendedTokenStaking || {
        log_error "ExtendedTokenStaking deployment failed"
        exit 1
    }
    log_success "ExtendedTokenStaking deployed"
    echo ""
    
    # Step 7: Deploy RandomBeacon
    log_info "Step 7: Deploying RandomBeacon..."
    cd "$PROJECT_ROOT/solidity/random-beacon"
    npx hardhat deploy --network development --tags RandomBeacon || {
        log_error "RandomBeacon deployment failed"
        exit 1
    }
    log_success "RandomBeacon deployed"
    echo ""
    
    # Step 8: Deploy RandomBeaconChaosnet
    log_info "Step 8: Deploying RandomBeaconChaosnet..."
    npx hardhat deploy --network development --tags RandomBeaconChaosnet || {
        log_error "RandomBeaconChaosnet deployment failed"
        exit 1
    }
    log_success "RandomBeaconChaosnet deployed"
    echo ""
    
    # Step 9: Deploy RandomBeaconGovernance (needed by ECDSA contracts)
    log_info "Step 9: Deploying RandomBeaconGovernance..."
    npx hardhat deploy --network development --tags RandomBeaconGovernance || {
        log_error "RandomBeaconGovernance deployment failed"
        exit 1
    }
    log_success "RandomBeaconGovernance deployed"
    echo ""
    
    # Step 10: Deploy ECDSA contracts (needs RandomBeaconChaosnet and RandomBeaconGovernance to exist)
    log_info "Step 10: Deploying ECDSA contracts..."
    cd "$PROJECT_ROOT/solidity/ecdsa"
    npx hardhat deploy --network development || {
        log_error "ECDSA contracts deployment failed"
        exit 1
    }
    log_success "ECDSA contracts deployed"
    echo ""
    
    # Step 10.5: Deploy and setup ReimbursementPool (fix for DKG approval revert)
    # This ensures ReimbursementPool is deployed, authorized for WalletRegistry, and funded
    log_info "Step 10.5: Deploying and setting up ReimbursementPool..."
    cd "$PROJECT_ROOT/solidity/ecdsa"
    if [ -f "scripts/deploy-and-setup-reimbursement-pool.ts" ]; then
        SETUP_OUTPUT=$(npx hardhat run scripts/deploy-and-setup-reimbursement-pool.ts --network development 2>&1)
        SETUP_EXIT_CODE=$?
        
        # Filter out Hardhat warnings and show only important output
        echo "$SETUP_OUTPUT" | grep -vE "(You are using a version|Please, make sure|To learn more|Error encountered|No need to generate|Contract Name|Size \(KB\)|^ ·|^ \||^---|Compiled|Compiling)" | grep -E "(Step|ReimbursementPool|WalletRegistry|authorized|funded|SUCCESS|Error|error|Failed|failed|Transaction|✓|✗|Setup Complete)" || true
        
        if [ $SETUP_EXIT_CODE -eq 0 ] && echo "$SETUP_OUTPUT" | grep -qE "Setup Complete"; then
            log_success "ReimbursementPool deployed and configured"
            
            # Verify WalletRegistry is using the correct ReimbursementPool
            WALLET_REGISTRY=$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistry.json" 2>/dev/null || echo "")
            REIMBURSEMENT_POOL=$(jq -r '.address' "$PROJECT_ROOT/solidity/random-beacon/deployments/development/ReimbursementPool.json" 2>/dev/null || echo "")
            
            if [ -n "$WALLET_REGISTRY" ] && [ -n "$REIMBURSEMENT_POOL" ] && [ "$WALLET_REGISTRY" != "null" ] && [ "$REIMBURSEMENT_POOL" != "null" ]; then
                CURRENT_POOL=$(cast call "$WALLET_REGISTRY" "reimbursementPool()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
                if [ "$CURRENT_POOL" = "$REIMBURSEMENT_POOL" ]; then
                    log_success "WalletRegistry is using the correct ReimbursementPool"
                else
                    log_warning "WalletRegistry is using different ReimbursementPool (current: $CURRENT_POOL, expected: $REIMBURSEMENT_POOL)"
                    log_info "This is normal if WalletRegistry was deployed before ReimbursementPool"
                    log_info "WalletRegistry will use the ReimbursementPool it was initialized with"
                fi
            fi
        elif echo "$SETUP_OUTPUT" | grep -qE "(already exists|already authorized|already has sufficient)"; then
            log_success "ReimbursementPool already configured"
        else
            log_warning "ReimbursementPool setup completed with warnings"
            log_info "You may need to run manually: cd solidity/ecdsa && npx hardhat run scripts/deploy-and-setup-reimbursement-pool.ts --network development"
        fi
    else
        log_warning "deploy-and-setup-reimbursement-pool.ts script not found"
        log_info "Skipping ReimbursementPool setup - you may need to run it manually"
        log_info "This may cause DKG approval to fail with empty revert errors"
    fi
    echo ""
    
    # Step 10.6: Ensure WalletRegistry uses correct ReimbursementPool address and it's configured properly
    log_info "Step 10.6: Ensuring WalletRegistry uses correct ReimbursementPool address..."
    cd "$PROJECT_ROOT"
    
    WALLET_REGISTRY=$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistry.json" 2>/dev/null || echo "")
    REIMBURSEMENT_POOL=$(jq -r '.address' "$PROJECT_ROOT/solidity/random-beacon/deployments/development/ReimbursementPool.json" 2>/dev/null || echo "")
    WALLET_REGISTRY_GOV=$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistryGovernance.json" 2>/dev/null || echo "")
    
    if [ -n "$WALLET_REGISTRY" ] && [ "$WALLET_REGISTRY" != "null" ] && \
       [ -n "$REIMBURSEMENT_POOL" ] && [ "$REIMBURSEMENT_POOL" != "null" ] && \
       [ -n "$WALLET_REGISTRY_GOV" ] && [ "$WALLET_REGISTRY_GOV" != "null" ]; then
        
        # Get current ReimbursementPool address from WalletRegistry
        CURRENT_POOL=$(cast call "$WALLET_REGISTRY" "reimbursementPool()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
        
        if [ "$CURRENT_POOL" = "$REIMBURSEMENT_POOL" ]; then
            log_success "WalletRegistry is using the correct ReimbursementPool address"
        else
            log_warning "WalletRegistry is using wrong ReimbursementPool address"
            log_info "Current: $CURRENT_POOL"
            log_info "Expected: $REIMBURSEMENT_POOL"
            log_info "Updating via governance..."
            
            # Get governance owner
            OWNER=$(cast call "$WALLET_REGISTRY_GOV" "owner()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x23d5975f6D72A57ba984886d3dF40Dca7f10ceca")
            
            # Begin update
            BEGIN_TX=$(cast send "$WALLET_REGISTRY_GOV" \
                "beginReimbursementPoolUpdate(address)" "$REIMBURSEMENT_POOL" \
                --rpc-url "$RPC_URL" \
                --unlocked \
                --from "$OWNER" \
                --gas-limit 200000 2>&1 | grep -E "transactionHash" | grep -oE '0x[a-fA-F0-9]{64}' || echo "")
            
            if [ -n "$BEGIN_TX" ]; then
                log_success "Governance update initiated (tx: ${BEGIN_TX:0:10}...)"
                
                # Wait for governance delay (65 seconds for development)
                log_info "Waiting for governance delay (65 seconds)..."
                sleep 65
                
                # Finalize update
                log_info "Finalizing governance update..."
                FINALIZE_TX=$(cast send "$WALLET_REGISTRY_GOV" \
                    "finalizeReimbursementPoolUpdate()" \
                    --rpc-url "$RPC_URL" \
                    --unlocked \
                    --from "$OWNER" \
                    --gas-limit 200000 2>&1 | grep -E "transactionHash|status" | head -3)
                
                sleep 3
                
                # Verify update
                NEW_POOL=$(cast call "$WALLET_REGISTRY" "reimbursementPool()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
                
                if [ "$NEW_POOL" = "$REIMBURSEMENT_POOL" ]; then
                    log_success "ReimbursementPool address updated successfully"
                else
                    log_warning "Update may have failed (current: $NEW_POOL, expected: $REIMBURSEMENT_POOL)"
                    log_info "You may need to update manually via governance"
                fi
            else
                log_warning "Failed to initiate governance update"
                log_info "You may need to update manually: cast send $WALLET_REGISTRY_GOV beginReimbursementPoolUpdate $REIMBURSEMENT_POOL --rpc-url $RPC_URL --unlocked --from $OWNER"
            fi
        fi
        
        # Ensure ReimbursementPool is funded with ETH
        POOL_BALANCE=$(cast balance "$REIMBURSEMENT_POOL" --rpc-url "$RPC_URL" 2>/dev/null || echo "0")
        MIN_BALANCE="1000000000000000000"  # 1 ETH minimum
        
        if [ -n "$POOL_BALANCE" ] && [ "$POOL_BALANCE" != "0" ] && [ "$POOL_BALANCE" != "0x0" ]; then
            # Convert hex to decimal for comparison
            POOL_BALANCE_DEC=$(printf "%d" "$POOL_BALANCE" 2>/dev/null || echo "0")
            MIN_BALANCE_DEC=$(printf "%d" "$MIN_BALANCE" 2>/dev/null || echo "1000000000000000000")
            
            if [ "$POOL_BALANCE_DEC" -lt "$MIN_BALANCE_DEC" ]; then
                log_info "ReimbursementPool balance is low ($POOL_BALANCE_DEC wei), funding with 10 ETH..."
                FUND_TX=$(cast send --value 10ether "$REIMBURSEMENT_POOL" \
                    --rpc-url "$RPC_URL" \
                    --unlocked \
                    --from "$OWNER" \
                    2>&1 | grep -E "transactionHash" | grep -oE '0x[a-fA-F0-9]{64}' || echo "")
                
                if [ -n "$FUND_TX" ]; then
                    log_success "ReimbursementPool funded (tx: ${FUND_TX:0:10}...)"
                else
                    log_warning "Failed to fund ReimbursementPool"
                fi
            else
                log_success "ReimbursementPool has sufficient balance"
            fi
        else
            log_info "ReimbursementPool has no balance, funding with 10 ETH..."
            FUND_TX=$(cast send --value 10ether "$REIMBURSEMENT_POOL" \
                --rpc-url "$RPC_URL" \
                --unlocked \
                --from "$OWNER" \
                2>&1 | grep -E "transactionHash" | grep -oE '0x[a-fA-F0-9]{64}' || echo "")
            
            if [ -n "$FUND_TX" ]; then
                log_success "ReimbursementPool funded (tx: ${FUND_TX:0:10}...)"
            else
                log_warning "Failed to fund ReimbursementPool"
            fi
        fi
        
        # Ensure WalletRegistry is authorized in ReimbursementPool
        IS_AUTHORIZED=$(cast call "$REIMBURSEMENT_POOL" "isAuthorized(address)(bool)" "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null || echo "false")
        
        if [ "$IS_AUTHORIZED" = "true" ]; then
            log_success "WalletRegistry is authorized in ReimbursementPool"
        else
            log_info "Authorizing WalletRegistry in ReimbursementPool..."
            
            # Get ReimbursementPool owner
            POOL_OWNER=$(cast call "$REIMBURSEMENT_POOL" "owner()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "$OWNER")
            
            AUTH_TX=$(cast send "$REIMBURSEMENT_POOL" \
                "authorize(address)" "$WALLET_REGISTRY" \
                --rpc-url "$RPC_URL" \
                --unlocked \
                --from "$POOL_OWNER" \
                --gas-limit 200000 2>&1 | grep -E "transactionHash" | grep -oE '0x[a-fA-F0-9]{64}' || echo "")
            
            if [ -n "$AUTH_TX" ]; then
                sleep 2
                # Verify authorization
                IS_AUTHORIZED=$(cast call "$REIMBURSEMENT_POOL" "isAuthorized(address)(bool)" "$WALLET_REGISTRY" --rpc-url "$RPC_URL" 2>/dev/null || echo "false")
                
                if [ "$IS_AUTHORIZED" = "true" ]; then
                    log_success "WalletRegistry authorized in ReimbursementPool (tx: ${AUTH_TX:0:10}...)"
                else
                    log_warning "Authorization may have failed"
                fi
            else
                log_warning "Failed to authorize WalletRegistry"
                log_info "You may need to authorize manually: cast send $REIMBURSEMENT_POOL authorize $WALLET_REGISTRY --rpc-url $RPC_URL --unlocked --from $POOL_OWNER"
            fi
        fi
    else
        log_warning "Could not verify ReimbursementPool configuration (missing contracts)"
        log_info "You may need to configure ReimbursementPool manually"
    fi
    echo ""
    
    # Step 11: Approve RandomBeacon in TokenStaking
    log_info "Step 11: Approving RandomBeacon in TokenStaking..."
    cd "$PROJECT_ROOT/solidity/random-beacon"
    npx hardhat deploy --network development --tags RandomBeaconApprove || {
        log_error "RandomBeacon approval failed"
        exit 1
    }
    log_success "RandomBeacon approved in TokenStaking"
    echo ""
    
    # Step 12: Deploy tBTC stubs
    log_info "Step 12: Deploying tBTC stubs..."
    cd "$PROJECT_ROOT/solidity/tbtc-stub"
    npx hardhat deploy --network development --tags TBTCStubs || {
        log_error "tBTC stubs deployment failed"
        exit 1
    }
    log_success "tBTC stubs deployed"
    echo ""
    
    # Step 12.5: Deploy Bridge contract (if not already deployed)
    log_info "Step 12.5: Deploying Bridge contract..."
    cd "$PROJECT_ROOT"
    
    # Try new Bridge deployment location first, then fall back to old location
    BRIDGE_PATH_NEW="$PROJECT_ROOT/tmp/tbtc-v2/solidity/deployments/development/Bridge.json"
    BRIDGE_PATH_OLD="$PROJECT_ROOT/solidity/tbtc-stub/deployments/development/Bridge.json"
    
    BRIDGE=""
    BRIDGE_HAS_CODE=false
    
    # Check if Bridge exists and has code
    if [ -f "$BRIDGE_PATH_NEW" ]; then
        BRIDGE=$(jq -r '.address' "$BRIDGE_PATH_NEW" 2>/dev/null || echo "")
        if [ -n "$BRIDGE" ] && [ "$BRIDGE" != "null" ]; then
            BRIDGE_CODE=$(cast code "$BRIDGE" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x")
            if [ "$BRIDGE_CODE" != "0x" ] && [ -n "$BRIDGE_CODE" ]; then
                BRIDGE_HAS_CODE=true
                log_info "Found existing Bridge at: $BRIDGE_PATH_NEW"
                log_success "Bridge already deployed at $BRIDGE (has code)"
            else
                log_warning "Bridge deployment file exists but contract has no code at $BRIDGE"
                log_info "Will redeploy Bridge..."
            fi
        fi
    elif [ -f "$BRIDGE_PATH_OLD" ]; then
        BRIDGE=$(jq -r '.address' "$BRIDGE_PATH_OLD" 2>/dev/null || echo "")
        if [ -n "$BRIDGE" ] && [ "$BRIDGE" != "null" ]; then
            BRIDGE_CODE=$(cast code "$BRIDGE" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x")
            if [ "$BRIDGE_CODE" != "0x" ] && [ -n "$BRIDGE_CODE" ]; then
                BRIDGE_HAS_CODE=true
                log_info "Found existing Bridge at: $BRIDGE_PATH_OLD"
                log_success "Bridge already deployed at $BRIDGE (has code)"
            else
                log_warning "Bridge deployment file exists but contract has no code at $BRIDGE"
                log_info "Will redeploy Bridge..."
            fi
        fi
    fi
    
    # Deploy Bridge if it doesn't exist or has no code
    if [ "$BRIDGE_HAS_CODE" != "true" ]; then
        log_info "Deploying Bridge contract..."
        
        # Try deploying from tmp/tbtc-v2 first (preferred location)
        if [ -d "$PROJECT_ROOT/tmp/tbtc-v2/solidity" ]; then
            cd "$PROJECT_ROOT/tmp/tbtc-v2/solidity"
            log_info "Deploying Bridge from tmp/tbtc-v2/solidity..."
            DEPLOY_OUTPUT=$(npx hardhat deploy --network development --tags Bridge 2>&1) || {
                log_warning "Bridge deployment from tmp/tbtc-v2 failed, trying tbtc-stub..."
                cd "$PROJECT_ROOT/solidity/tbtc-stub"
                npx hardhat deploy --network development --tags TBTCStubs 2>&1 || {
                    log_error "Bridge deployment failed from both locations"
                    log_info "You may need to deploy Bridge manually"
                }
            }
            
            # Check if deployment succeeded
            if [ -f "$BRIDGE_PATH_NEW" ]; then
                BRIDGE=$(jq -r '.address' "$BRIDGE_PATH_NEW" 2>/dev/null || echo "")
                if [ -n "$BRIDGE" ] && [ "$BRIDGE" != "null" ]; then
                    BRIDGE_CODE=$(cast code "$BRIDGE" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x")
                    if [ "$BRIDGE_CODE" != "0x" ] && [ -n "$BRIDGE_CODE" ]; then
                        BRIDGE_HAS_CODE=true
                        log_success "Bridge deployed at $BRIDGE"
                    fi
                fi
            fi
        else
            log_warning "tmp/tbtc-v2/solidity directory not found, Bridge may need manual deployment"
        fi
    fi
    
    echo ""
    
    # Step 12.6: Initialize WalletRegistry walletOwner
    # IMPORTANT: Prefer Bridge stub (has callback) over Bridge v2 (may not have callback)
    log_info "Step 12.6: Initializing WalletRegistry walletOwner..."
    cd "$PROJECT_ROOT"
    
    WALLET_REGISTRY=$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistry.json" 2>/dev/null || echo "")
    WALLET_REGISTRY_GOV=$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistryGovernance.json" 2>/dev/null || echo "")
    
    if [ -z "$WALLET_REGISTRY" ] || [ "$WALLET_REGISTRY" = "null" ] || \
       [ -z "$WALLET_REGISTRY_GOV" ] || [ "$WALLET_REGISTRY_GOV" = "null" ]; then
        log_warning "WalletRegistry or WalletRegistryGovernance not found, skipping walletOwner initialization"
        echo ""
    else
    
    # Find Bridge stub first (has callback function), then fall back to Bridge v2
    BRIDGE_STUB_PATH="$PROJECT_ROOT/solidity/tbtc-stub/deployments/development/Bridge.json"
    BRIDGE_V2_PATH="$PROJECT_ROOT/tmp/tbtc-v2/solidity/deployments/development/Bridge.json"
    
    TARGET_BRIDGE=""
    BRIDGE_SOURCE=""
    
    # Prefer Bridge stub (has callback function)
    if [ -f "$BRIDGE_STUB_PATH" ]; then
        BRIDGE_STUB=$(jq -r '.address' "$BRIDGE_STUB_PATH" 2>/dev/null || echo "")
        if [ -n "$BRIDGE_STUB" ] && [ "$BRIDGE_STUB" != "null" ]; then
            BRIDGE_STUB_CODE=$(cast code "$BRIDGE_STUB" --rpc-url "$RPC_URL" 2>/dev/null | head -c 10 || echo "0x")
            if [ "$BRIDGE_STUB_CODE" != "0x" ]; then
                # Verify it has the callback function
                if cast call "$BRIDGE_STUB" "__ecdsaWalletCreatedCallback(bytes32,bytes32,bytes32)" \
                    "0x0000000000000000000000000000000000000000000000000000000000000000" \
                    "0x0000000000000000000000000000000000000000000000000000000000000000" \
                    "0x0000000000000000000000000000000000000000000000000000000000000000" \
                    --rpc-url "$RPC_URL" >/dev/null 2>&1; then
                    TARGET_BRIDGE="$BRIDGE_STUB"
                    BRIDGE_SOURCE="Bridge stub (tbtc-stub)"
                    log_info "Found Bridge stub with callback function: $TARGET_BRIDGE"
                fi
            fi
        fi
    fi
    
    # Fall back to Bridge v2 if stub not found
    if [ -z "$TARGET_BRIDGE" ] && [ -f "$BRIDGE_V2_PATH" ]; then
        BRIDGE_V2=$(jq -r '.address' "$BRIDGE_V2_PATH" 2>/dev/null || echo "")
        if [ -n "$BRIDGE_V2" ] && [ "$BRIDGE_V2" != "null" ]; then
            BRIDGE_V2_CODE=$(cast code "$BRIDGE_V2" --rpc-url "$RPC_URL" 2>/dev/null | head -c 10 || echo "0x")
            if [ "$BRIDGE_V2_CODE" != "0x" ]; then
                TARGET_BRIDGE="$BRIDGE_V2"
                BRIDGE_SOURCE="Bridge v2 (tmp/tbtc-v2)"
                log_info "Found Bridge v2: $TARGET_BRIDGE"
                log_warning "Bridge v2 may not have callback function - DKG approvals may fail"
            fi
        fi
    fi
    
    if [ -z "$TARGET_BRIDGE" ]; then
        log_warning "No Bridge contract found with code, skipping walletOwner initialization"
        log_info "You may need to deploy Bridge manually and then run:"
        log_info "  cd solidity/ecdsa && npx hardhat run scripts/init-wallet-owner.ts --network development"
    else
    
    log_info "Using $BRIDGE_SOURCE: $TARGET_BRIDGE"
    
    # Check current walletOwner
    CURRENT_OWNER=$(cast call "$WALLET_REGISTRY" "walletOwner()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
    
    if [ "$CURRENT_OWNER" = "$TARGET_BRIDGE" ]; then
        log_success "WalletOwner already set correctly to Bridge address"
    else
        log_info "Current walletOwner: $CURRENT_OWNER"
        log_info "Setting walletOwner to Bridge address ($BRIDGE_SOURCE)..."
        
        # Get governance owner
        OWNER=$(cast call "$WALLET_REGISTRY_GOV" "owner()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "")
        if [ -z "$OWNER" ] || [ "$OWNER" = "0x0000000000000000000000000000000000000000" ]; then
            log_warning "Could not get governance owner, trying init-wallet-owner.ts script..."
            cd "$PROJECT_ROOT/solidity/ecdsa"
            INIT_OUTPUT=$(npx hardhat run scripts/init-wallet-owner.ts --network development 2>&1) || {
                INIT_EXIT_CODE=$?
                if echo "$INIT_OUTPUT" | grep -qE "(already|already set|already initialized)"; then
                    log_success "WalletOwner already initialized"
                else
                    log_warning "WalletOwner initialization script failed (exit code: $INIT_EXIT_CODE)"
                    echo "$INIT_OUTPUT" | grep -E "(Error|error|Failed|failed)" | head -5 | sed 's/^/  /' || true
                fi
            }
        else
            # Use governance to update walletOwner
            if [ "$CURRENT_OWNER" = "0x0000000000000000000000000000000000000000" ]; then
                # Initialize (no delay)
                log_info "Initializing walletOwner (no governance delay)..."
                INIT_TX=$(cast send "$WALLET_REGISTRY_GOV" \
                    "initializeWalletOwner(address)" "$TARGET_BRIDGE" \
                    --rpc-url "$RPC_URL" \
                    --unlocked \
                    --from "$OWNER" \
                    --gas-limit 200000 2>&1 | grep -E "transactionHash" | grep -oE '0x[a-fA-F0-9]{64}' || echo "")
                
                if [ -n "$INIT_TX" ]; then
                    log_success "WalletOwner initialized (tx: ${INIT_TX:0:10}...)"
                else
                    log_warning "Failed to initialize walletOwner"
                fi
            else
                # Update (requires governance delay)
                log_info "Updating walletOwner (requires governance delay)..."
                BEGIN_TX=$(cast send "$WALLET_REGISTRY_GOV" \
                    "beginWalletOwnerUpdate(address)" "$TARGET_BRIDGE" \
                    --rpc-url "$RPC_URL" \
                    --unlocked \
                    --from "$OWNER" \
                    --gas-limit 200000 2>&1 | grep -E "transactionHash" | grep -oE '0x[a-fA-F0-9]{64}' || echo "")
                
                if [ -n "$BEGIN_TX" ]; then
                    log_success "Update initiated (tx: ${BEGIN_TX:0:10}...)"
                    log_info "Waiting for governance delay (65 seconds)..."
                    sleep 65
                    
                    log_info "Finalizing walletOwner update..."
                    FINALIZE_TX=$(cast send "$WALLET_REGISTRY_GOV" \
                        "finalizeWalletOwnerUpdate()" \
                        --rpc-url "$RPC_URL" \
                        --unlocked \
                        --from "$OWNER" \
                        --gas-limit 200000 2>&1 | grep -E "transactionHash|status" | head -3)
                    
                    sleep 2
                else
                    log_warning "Failed to initiate walletOwner update"
                fi
            fi
        fi
        
        # Verify walletOwner was set correctly
        sleep 2
        VERIFY_OWNER=$(cast call "$WALLET_REGISTRY" "walletOwner()(address)" --rpc-url "$RPC_URL" 2>/dev/null || echo "0x0000000000000000000000000000000000000000")
        if [ "$VERIFY_OWNER" = "$TARGET_BRIDGE" ]; then
            log_success "WalletOwner verified: $VERIFY_OWNER ($BRIDGE_SOURCE)"
            
            # Verify callback function if Bridge stub
            if [ "$BRIDGE_SOURCE" = "Bridge stub (tbtc-stub)" ]; then
                if cast call "$TARGET_BRIDGE" "__ecdsaWalletCreatedCallback(bytes32,bytes32,bytes32)" \
                    "0x0000000000000000000000000000000000000000000000000000000000000000" \
                    "0x0000000000000000000000000000000000000000000000000000000000000000" \
                    "0x0000000000000000000000000000000000000000000000000000000000000000" \
                    --rpc-url "$RPC_URL" >/dev/null 2>&1; then
                    log_success "Callback function verified - Bridge is properly configured"
                else
                    log_warning "Callback function verification failed"
                fi
            fi
        else
            log_warning "WalletOwner verification failed (current: $VERIFY_OWNER, expected: $TARGET_BRIDGE)"
            log_info "You may need to update manually via governance"
        fi
    fi
    fi  # Close else block for TARGET_BRIDGE found
    fi  # Close else block for contracts found
    echo ""
    
    # Step 13: Initialize all operators (stake and authorize)
    log_info "Step 13: Initializing all operators (stake and authorize)..."
    cd "$PROJECT_ROOT"
    
    CONFIG_DIR="${CONFIG_DIR:-./configs}"
    STAKE_AMOUNT="${STAKE_AMOUNT:-1000000}"  # Default: 1M T tokens
    AUTHORIZATION_AMOUNT="${AUTHORIZATION_AMOUNT:-}"  # Default: minimum authorization (will be set automatically)
    
    # Try using the dedicated initialization script if available
    if [ -f "./scripts/initialize-all-operators.sh" ]; then
        log_info "Using dedicated initialization script..."
        
        # Run initialization script and capture output
        INIT_OUTPUT=$(NETWORK="development" \
            STAKE_AMOUNT="$STAKE_AMOUNT" \
            AUTHORIZATION_AMOUNT="$AUTHORIZATION_AMOUNT" \
            ./scripts/initialize-all-operators.sh 2>&1) || {
            INIT_EXIT_CODE=$?
            log_warning "Initialization script exited with code $INIT_EXIT_CODE"
            echo "$INIT_OUTPUT" | grep -E "(Error|error|Failed|failed|⚠|✗)" | head -10 | sed 's/^/  /' || true
            log_warning "Falling back to inline initialization..."
        }
        
        # Show summary from initialization script
        if echo "$INIT_OUTPUT" | grep -q "Successfully initialized"; then
            echo "$INIT_OUTPUT" | grep -E "(Successfully initialized|Failed|Summary)" | head -5 | sed 's/^/  /'
        fi
        
        # Extract operators for later steps
        declare -a OPERATORS
        declare -a NODE_NUMS
        
        for config_file in "$CONFIG_DIR"/node*.toml; do
            if [ ! -f "$config_file" ]; then
                continue
            fi
            
            NODE_NUM=$(basename "$config_file" | sed -n 's/node\([0-9]*\)\.toml/\1/p')
            if [ -z "$NODE_NUM" ]; then
                continue
            fi
            
            KEYFILE=$(grep "^KeyFile" "$config_file" | head -1 | cut -d'"' -f2)
            if [ -z "$KEYFILE" ]; then
                continue
            fi
            
            if [[ "$KEYFILE" != /* ]]; then
                KEYFILE="${KEYFILE#./}"
                KEYFILE="$PROJECT_ROOT/$KEYFILE"
            fi
            
            if [ ! -f "$KEYFILE" ]; then
                continue
            fi
            
            OPERATOR=$(cat "$KEYFILE" | jq -r .address 2>/dev/null | tr -d '\n')
            if [ -z "$OPERATOR" ] || [ "$OPERATOR" = "null" ]; then
                continue
            fi
            
            if [[ "$OPERATOR" != 0x* ]]; then
                OPERATOR="0x$OPERATOR"
            fi
            
            OPERATORS+=("$OPERATOR")
            NODE_NUMS+=("$NODE_NUM")
        done
        
        if [ ${#OPERATORS[@]} -gt 0 ]; then
            log_success "Found ${#OPERATORS[@]} operator(s) for subsequent steps"
        else
            log_warning "No operators found in config files"
        fi
    else
        # Fallback to inline initialization
        log_info "Using inline initialization..."
        KEEP_BEACON_SOL_PATH="$PROJECT_ROOT/solidity/random-beacon"
        KEEP_ECDSA_SOL_PATH="$PROJECT_ROOT/solidity/ecdsa"
        
        # Find all node config files
        declare -a CONFIG_FILES
        for config_file in "$CONFIG_DIR"/node*.toml; do
            if [ -f "$config_file" ]; then
                CONFIG_FILES+=("$config_file")
            fi
        done
        
        if [ ${#CONFIG_FILES[@]} -eq 0 ]; then
            log_warning "No node config files found in $CONFIG_DIR, skipping operator initialization"
            OPERATORS=()
            NODE_NUMS=()
        else
            log_info "Found ${#CONFIG_FILES[@]} node config(s)"
            
            # Extract operator addresses from configs
            declare -a OPERATORS
            declare -a NODE_NUMS
            
            for config_file in "${CONFIG_FILES[@]}"; do
                NODE_NUM=$(basename "$config_file" | sed -n 's/node\([0-9]*\)\.toml/\1/p')
                if [ -z "$NODE_NUM" ]; then
                    continue
                fi
                
                KEYFILE=$(grep "^KeyFile" "$config_file" | head -1 | cut -d'"' -f2)
                if [ -z "$KEYFILE" ]; then
                    continue
                fi
                
                # Resolve relative path
                if [[ "$KEYFILE" != /* ]]; then
                    KEYFILE="${KEYFILE#./}"
                    KEYFILE="$PROJECT_ROOT/$KEYFILE"
                fi
                
                if [ ! -f "$KEYFILE" ]; then
                    continue
                fi
                
                OPERATOR=$(cat "$KEYFILE" | jq -r .address 2>/dev/null | tr -d '\n')
                if [ -z "$OPERATOR" ] || [ "$OPERATOR" = "null" ]; then
                    continue
                fi
                
                if [[ "$OPERATOR" != 0x* ]]; then
                    OPERATOR="0x$OPERATOR"
                fi
                
                OPERATORS+=("$OPERATOR")
                NODE_NUMS+=("$NODE_NUM")
            done
            
            if [ ${#OPERATORS[@]} -gt 0 ]; then
                log_info "Initializing ${#OPERATORS[@]} operator(s)..."
                
                for i in "${!OPERATORS[@]}"; do
                    OPERATOR="${OPERATORS[$i]}"
                    NODE_NUM="${NODE_NUMS[$i]}"
                    
                    log_info "  Initializing Node $NODE_NUM ($OPERATOR)..."
                    
                    # Build initialize command with stake amount
                    INIT_CMD="npx hardhat initialize --network development --owner $OPERATOR --provider $OPERATOR --operator $OPERATOR --beneficiary $OPERATOR --authorizer $OPERATOR --amount $STAKE_AMOUNT"
                    
                    # Add authorization amount if specified (ensures above minimum)
                    # If not specified, Hardhat will use minimum authorization automatically
                    if [ -n "$AUTHORIZATION_AMOUNT" ]; then
                        INIT_CMD="$INIT_CMD --authorization $AUTHORIZATION_AMOUNT"
                        log_info "    Using authorization amount: $AUTHORIZATION_AMOUNT T tokens"
                    else
                        log_info "    Using minimum authorization (will be set automatically)"
                    fi
                    
                    # Initialize RandomBeacon
                    log_info "    Initializing RandomBeacon..."
                    cd "$KEEP_BEACON_SOL_PATH"
                    if eval "$INIT_CMD" 2>&1 | grep -vE "(You are using a version|Please, make sure|To learn more|Error encountered|No need to generate|Contract Name|Size \(KB\)|^ ·|^ \||^---)" | grep -E "(✓|SUCCESS|Error|Transaction|hash|already|initialized)" | head -3; then
                        log_success "    Node $NODE_NUM: RandomBeacon initialized"
                    else
                        log_warning "    Node $NODE_NUM: RandomBeacon initialization may have failed or already initialized"
                    fi
                    
                    sleep 1
                    
                    # Initialize WalletRegistry
                    log_info "    Initializing WalletRegistry..."
                    cd "$KEEP_ECDSA_SOL_PATH"
                    if eval "$INIT_CMD" 2>&1 | grep -vE "(You are using a version|Please, make sure|To learn more|Error encountered|No need to generate|Contract Name|Size \(KB\)|^ ·|^ \||^---)" | grep -E "(✓|SUCCESS|Error|Transaction|hash|already|initialized)" | head -3; then
                        log_success "    Node $NODE_NUM: WalletRegistry initialized"
                    else
                        log_warning "    Node $NODE_NUM: WalletRegistry initialization may have failed or already initialized"
                    fi
                    
                    sleep 2
                done
                
                log_success "All operators initialized"
            else
                log_warning "No valid operators found in config files"
                OPERATORS=()
                NODE_NUMS=()
            fi
        fi
    fi
    echo ""
    
    # Step 13.5: Fund operators with ETH
    log_info "Step 13.5: Funding operators with ETH..."
    cd "$PROJECT_ROOT"
    if [ -f "./scripts/fund-operators.sh" ] && [ ${#OPERATORS[@]} -gt 0 ]; then
        NUM_NODES=${#OPERATORS[@]}
        if ./scripts/fund-operators.sh "$NUM_NODES" 1 >/dev/null 2>&1; then
            log_success "Operators funded with ETH"
        else
            log_warning "Operator funding may have failed (they may already have ETH)"
        fi
    else
        log_warning "fund-operators.sh not found or no operators, skipping funding"
    fi
    echo ""
    
    # Step 13.5.5: Verify operators are initialized (have authorization)
    if [ ${#OPERATORS[@]} -gt 0 ]; then
        log_info "Step 13.5.5: Verifying operator initialization..."
        cd "$PROJECT_ROOT"
        
        # Check if we can verify authorization using cast
        RPC="http://localhost:8545"
        TOKEN_STAKING=$(jq -r '.address' solidity/ecdsa/deployments/development/ExtendedTokenStaking.json 2>/dev/null || echo "")
        
        if [ -n "$TOKEN_STAKING" ] && [ "$TOKEN_STAKING" != "null" ]; then
            UNAUTHORIZED_COUNT=0
            UNAUTHORIZED_NODES=()
            
            for i in "${!OPERATORS[@]}"; do
                OPERATOR="${OPERATORS[$i]}"
                NODE_NUM="${NODE_NUMS[$i]}"
                
                # Check eligible stake (this includes authorization)
                ELIGIBLE_STAKE=$(cast call "$TOKEN_STAKING" "eligibleStake(address)(uint256)" "$OPERATOR" --rpc-url "$RPC" 2>/dev/null || echo "0")
                
                if [ -z "$ELIGIBLE_STAKE" ] || [ "$ELIGIBLE_STAKE" = "0" ] || [ "$ELIGIBLE_STAKE" = "0x0" ]; then
                    log_warning "    Node $NODE_NUM: No eligible stake (not initialized)"
                    UNAUTHORIZED_COUNT=$((UNAUTHORIZED_COUNT + 1))
                    UNAUTHORIZED_NODES+=("$NODE_NUM")
                else
                    # Convert hex to decimal for display
                    ELIGIBLE_DEC=$(printf "%d" "$ELIGIBLE_STAKE" 2>/dev/null || echo "0")
                    log_success "    Node $NODE_NUM: Eligible stake = $ELIGIBLE_DEC"
                fi
            done
            
            if [ $UNAUTHORIZED_COUNT -gt 0 ]; then
                log_error "$UNAUTHORIZED_COUNT operator(s) are not properly initialized"
                log_info "Nodes needing initialization: ${UNAUTHORIZED_NODES[*]}"
                log_info ""
                log_info "Re-running initialization for failed nodes..."
                
                # Re-initialize failed operators
                for i in "${!OPERATORS[@]}"; do
                    OPERATOR="${OPERATORS[$i]}"
                    NODE_NUM="${NODE_NUMS[$i]}"
                    
                    if [[ " ${UNAUTHORIZED_NODES[*]} " =~ " ${NODE_NUM} " ]]; then
                        log_info "  Re-initializing Node $NODE_NUM..."
                        KEEP_BEACON_SOL_PATH="$PROJECT_ROOT/solidity/random-beacon"
                        KEEP_ECDSA_SOL_PATH="$PROJECT_ROOT/solidity/ecdsa"
                        
                        INIT_CMD="npx hardhat initialize --network development --owner $OPERATOR --provider $OPERATOR --operator $OPERATOR --beneficiary $OPERATOR --authorizer $OPERATOR --amount $STAKE_AMOUNT"
                        if [ -n "$AUTHORIZATION_AMOUNT" ]; then
                            INIT_CMD="$INIT_CMD --authorization $AUTHORIZATION_AMOUNT"
                        fi
                        
                        cd "$KEEP_BEACON_SOL_PATH"
                        eval "$INIT_CMD" >/dev/null 2>&1 || true
                        sleep 1
                        
                        cd "$KEEP_ECDSA_SOL_PATH"
                        eval "$INIT_CMD" >/dev/null 2>&1 || true
                        sleep 1
                    fi
                done
                
                log_info "Re-initialization complete. Re-checking..."
                sleep 2
                
                # Re-check
                RE_CHECK_FAILED=0
                for i in "${!OPERATORS[@]}"; do
                    OPERATOR="${OPERATORS[$i]}"
                    NODE_NUM="${NODE_NUMS[$i]}"
                    
                    if [[ " ${UNAUTHORIZED_NODES[*]} " =~ " ${NODE_NUM} " ]]; then
                        ELIGIBLE_STAKE=$(cast call "$TOKEN_STAKING" "eligibleStake(address)(uint256)" "$OPERATOR" --rpc-url "$RPC" 2>/dev/null || echo "0")
                        if [ -z "$ELIGIBLE_STAKE" ] || [ "$ELIGIBLE_STAKE" = "0" ] || [ "$ELIGIBLE_STAKE" = "0x0" ]; then
                            RE_CHECK_FAILED=$((RE_CHECK_FAILED + 1))
                        fi
                    fi
                done
                
                if [ $RE_CHECK_FAILED -gt 0 ]; then
                    log_error "Some operators still not initialized. Manual intervention may be needed."
                    log_info "Run: ./scripts/initialize-all-operators.sh"
                else
                    log_success "All operators now have eligible stake"
                fi
            else
                log_success "All operators have eligible stake"
            fi
        else
            log_warning "Could not verify authorization (TokenStaking contract not found)"
        fi
        echo ""
    fi
    
    # Step 13.6: Join operators to sortition pools
    log_info "Step 13.6: Joining operators to sortition pools..."
    cd "$PROJECT_ROOT"
    
    # Try using the dedicated join script if available
    if [ -f "./scripts/join-all-operators-to-pools.sh" ] && [ ${#OPERATORS[@]} -gt 0 ]; then
        log_info "Using dedicated join script..."
        KEEP_ETHEREUM_PASSWORD="$KEEP_ETHEREUM_PASSWORD" \
        CONFIG_DIR="$CONFIG_DIR" \
        ./scripts/join-all-operators-to-pools.sh 2>&1 | grep -vE "(You are using a version|Please, make sure|To learn more|Error encountered|No need to generate|Contract Name|Size \(KB\)|^ ·|^ \||^---|Found.*node config)" || {
            log_warning "Join script completed with warnings - check output above"
        }
    elif [ ${#OPERATORS[@]} -gt 0 ]; then
        # Fallback to inline joining with better error reporting
        log_info "Using inline join process..."
        SUCCESS_COUNT=0
        FAIL_COUNT=0
        
        for i in "${!OPERATORS[@]}"; do
            OPERATOR="${OPERATORS[$i]}"
            NODE_NUM="${NODE_NUMS[$i]}"
            CONFIG_FILE="$CONFIG_DIR/node${NODE_NUM}.toml"
            
            log_info "  Joining Node $NODE_NUM to pools..."
            
            # Join RandomBeacon sortition pool
            RB_OUTPUT=$(KEEP_ETHEREUM_PASSWORD="$KEEP_ETHEREUM_PASSWORD" ./keep-client ethereum beacon random-beacon join-sortition-pool \
                --submit --config "$CONFIG_FILE" --developer 2>&1)
            
            if echo "$RB_OUTPUT" | grep -qE "(Transaction|hash|SUCCESS|already|joined)" && ! echo "$RB_OUTPUT" | grep -qE "(Error|error|execution reverted|Authorization below|not registered)"; then
                log_success "    Node $NODE_NUM: Joined RandomBeacon pool"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                log_warning "    Node $NODE_NUM: RandomBeacon pool join failed"
                echo "$RB_OUTPUT" | grep -E "(Error|error|execution reverted|Authorization|not registered)" | head -2 | sed 's/^/      /' || true
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
            
            sleep 2
            
            # Join WalletRegistry sortition pool
            WR_OUTPUT=$(KEEP_ETHEREUM_PASSWORD="$KEEP_ETHEREUM_PASSWORD" ./keep-client ethereum ecdsa wallet-registry join-sortition-pool \
                --submit --config "$CONFIG_FILE" --developer 2>&1)
            
            if echo "$WR_OUTPUT" | grep -qE "(Transaction|hash|SUCCESS|already|joined)" && ! echo "$WR_OUTPUT" | grep -qE "(Error|error|execution reverted|Authorization below|not registered)"; then
                log_success "    Node $NODE_NUM: Joined WalletRegistry pool"
                SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
            else
                log_warning "    Node $NODE_NUM: WalletRegistry pool join failed"
                echo "$WR_OUTPUT" | grep -E "(Error|error|execution reverted|Authorization|not registered)" | head -2 | sed 's/^/      /' || true
                FAIL_COUNT=$((FAIL_COUNT + 1))
            fi
            
            sleep 2
        done
        
        echo ""
        log_info "Join Summary:"
        log_info "  Successfully joined: $SUCCESS_COUNT"
        if [ $FAIL_COUNT -gt 0 ]; then
            log_warning "  Failed: $FAIL_COUNT"
            log_warning "Operators may need to be initialized first (stake + authorize)"
            log_info "Run: ./scripts/initialize-all-operators.sh"
        else
            log_success "All operators joined sortition pools"
        fi
    else
        log_warning "No operators to join pools"
    fi
    echo ""
    
    # Step 14: Set minimum DKG parameters (mandatory)
    log_info "Step 14: Setting minimum DKG parameters for development..."
    cd "$PROJECT_ROOT"
    if [ -f "./scripts/set-minimum-dkg-params.sh" ]; then
        ./scripts/set-minimum-dkg-params.sh || {
            log_error "Failed to set minimum DKG parameters"
            exit 1
        }
        log_success "DKG parameters set to minimum"
    else
        log_error "set-minimum-dkg-params.sh not found"
        exit 1
    fi
    echo ""
    
    # Step 14.5: Update DKG resultSubmissionTimeout to 4000 blocks (for 100-member DKG with 3 retries × 1200 blocks)
    log_info "Step 14.5: Updating DKG resultSubmissionTimeout to 4000 blocks..."
    cd "$PROJECT_ROOT"
    
    WALLET_REGISTRY_GOV=$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistryGovernance.json" 2>/dev/null || echo "")
    OWNER_ADDRESS="0x23d5975f6D72A57ba984886d3dF40Dca7f10ceca"  # Default owner for development
    
    if [ -n "$WALLET_REGISTRY_GOV" ] && [ "$WALLET_REGISTRY_GOV" != "null" ]; then
        log_info "WalletRegistryGovernance: $WALLET_REGISTRY_GOV"
        
        # Check current timeout
        CURRENT_TIMEOUT=$(cast abi-decode "dkgParameters()(uint256,uint256,uint256,uint256)" \
            $(cast call "$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistry.json")" \
                "dkgParameters()" --rpc-url "$RPC_URL") 2>&1 | tail -1 | grep -oE '[0-9]+' || echo "120")
        
        if [ "$CURRENT_TIMEOUT" = "4000" ]; then
            log_success "DKG resultSubmissionTimeout already set to 4000 blocks"
        else
            log_info "Current resultSubmissionTimeout: $CURRENT_TIMEOUT blocks"
            log_info "Updating to 4000 blocks (required for 100-member DKG with 3 retries × 1200 blocks)..."
            
            # Begin update
            log_info "Initiating governance update..."
            BEGIN_TX=$(cast send "$WALLET_REGISTRY_GOV" \
                "beginDkgResultSubmissionTimeoutUpdate(uint256)" 4000 \
                --rpc-url "$RPC_URL" \
                --unlocked \
                --from "$OWNER_ADDRESS" \
                --gas-limit 200000 2>&1 | grep -E "transactionHash" | grep -oE '0x[a-fA-F0-9]{64}' || echo "")
            
            if [ -n "$BEGIN_TX" ]; then
                log_success "Governance update initiated (tx: ${BEGIN_TX:0:10}...)"
                
                # Wait for governance delay (65 seconds for development)
                log_info "Waiting for governance delay (65 seconds)..."
                sleep 65
                
                # Finalize update
                log_info "Finalizing governance update..."
                FINALIZE_TX=$(cast send "$WALLET_REGISTRY_GOV" \
                    "finalizeDkgResultSubmissionTimeoutUpdate()" \
                    --rpc-url "$RPC_URL" \
                    --unlocked \
                    --from "$OWNER_ADDRESS" \
                    --gas-limit 200000 2>&1 | grep -E "transactionHash" | grep -oE '0x[a-fA-F0-9]{64}' || echo "")
                
                if [ -n "$FINALIZE_TX" ]; then
                    sleep 3
                    # Verify update
                    NEW_TIMEOUT=$(cast abi-decode "dkgParameters()(uint256,uint256,uint256,uint256)" \
                        $(cast call "$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistry.json")" \
                            "dkgParameters()" --rpc-url "$RPC_URL") 2>&1 | tail -1 | grep -oE '[0-9]+' || echo "")
                    
                    if [ "$NEW_TIMEOUT" = "4000" ]; then
                        log_success "DKG resultSubmissionTimeout updated to 4000 blocks"
                    else
                        log_warning "Update may have failed (current: $NEW_TIMEOUT, expected: 4000)"
                        log_info "You may need to update manually via governance"
                    fi
                else
                    log_warning "Failed to finalize governance update"
                    log_info "You may need to finalize manually: cast send $WALLET_REGISTRY_GOV finalizeDkgResultSubmissionTimeoutUpdate() --rpc-url $RPC_URL --unlocked --from $OWNER_ADDRESS"
                fi
            else
                log_warning "Failed to initiate governance update"
                log_info "You may need to update manually: cast send $WALLET_REGISTRY_GOV beginDkgResultSubmissionTimeoutUpdate 536 --rpc-url $RPC_URL --unlocked --from $OWNER_ADDRESS"
            fi
        fi
    else
        log_warning "WalletRegistryGovernance contract not found, skipping timeout update"
        log_info "You may need to update DKG parameters manually after deployment"
    fi
    echo ""
    
    # Step 15: Update config files
    log_info "Step 15: Updating config files with new contract addresses..."
    
    # Get deployed addresses
    WALLET_REGISTRY=$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/WalletRegistry.json" 2>/dev/null || echo "")
    RANDOM_BEACON=$(jq -r '.address' "$PROJECT_ROOT/solidity/random-beacon/deployments/development/RandomBeacon.json" 2>/dev/null || echo "")
    TOKEN_STAKING=$(jq -r '.address' "$PROJECT_ROOT/solidity/ecdsa/deployments/development/ExtendedTokenStaking.json" 2>/dev/null || echo "")
    
    # Try new Bridge deployment location first, then fall back to old location
    BRIDGE_PATH_NEW="$PROJECT_ROOT/tmp/tbtc-v2/solidity/deployments/development/Bridge.json"
    BRIDGE_PATH_OLD="$PROJECT_ROOT/solidity/tbtc-stub/deployments/development/Bridge.json"
    BRIDGE=""
    if [ -f "$BRIDGE_PATH_NEW" ]; then
        BRIDGE=$(jq -r '.address' "$BRIDGE_PATH_NEW" 2>/dev/null || echo "")
    elif [ -f "$BRIDGE_PATH_OLD" ]; then
        BRIDGE=$(jq -r '.address' "$BRIDGE_PATH_OLD" 2>/dev/null || echo "")
    fi
    MAINTAINER_PROXY=$(jq -r '.address' "$PROJECT_ROOT/solidity/tbtc-stub/deployments/development/MaintainerProxy.json" 2>/dev/null || echo "")
    WALLET_PROPOSAL_VALIDATOR=$(jq -r '.address' "$PROJECT_ROOT/solidity/tbtc-stub/deployments/development/WalletProposalValidator.json" 2>/dev/null || echo "")
    
    if [ -z "$WALLET_REGISTRY" ] || [ -z "$RANDOM_BEACON" ] || [ -z "$TOKEN_STAKING" ]; then
        log_error "Could not read contract addresses from deployment files"
        exit 1
    fi
    
    # Update config files
    CONFIG_FILES=(
        "$PROJECT_ROOT/config.toml"
        "$PROJECT_ROOT/node5.toml"
        "$PROJECT_ROOT/configs/config.toml"
    )
    
    # Add node config files
    for i in {1..10}; do
        if [ -f "$PROJECT_ROOT/configs/node$i.toml" ]; then
            CONFIG_FILES+=("$PROJECT_ROOT/configs/node$i.toml")
        fi
    done
    
    for config_file in "${CONFIG_FILES[@]}"; do
        if [ -f "$config_file" ]; then
            # Update addresses using sed
            sed -i '' "s|RandomBeaconAddress = \".*\"|RandomBeaconAddress = \"$RANDOM_BEACON\"|g" "$config_file" 2>/dev/null || true
            sed -i '' "s|WalletRegistryAddress = \".*\"|WalletRegistryAddress = \"$WALLET_REGISTRY\"|g" "$config_file" 2>/dev/null || true
            sed -i '' "s|TokenStakingAddress = \".*\"|TokenStakingAddress = \"$TOKEN_STAKING\"|g" "$config_file" 2>/dev/null || true
            
            if [ -n "$BRIDGE" ]; then
                sed -i '' "s|BridgeAddress = \".*\"|BridgeAddress = \"$BRIDGE\"|g" "$config_file" 2>/dev/null || true
            fi
            
            if [ -n "$MAINTAINER_PROXY" ]; then
                sed -i '' "s|MaintainerProxyAddress = \".*\"|MaintainerProxyAddress = \"$MAINTAINER_PROXY\"|g" "$config_file" 2>/dev/null || true
            fi
            
            if [ -n "$WALLET_PROPOSAL_VALIDATOR" ]; then
                sed -i '' "s|WalletProposalValidatorAddress = \".*\"|WalletProposalValidatorAddress = \"$WALLET_PROPOSAL_VALIDATOR\"|g" "$config_file" 2>/dev/null || true
            fi
            
            log_success "Updated $(basename "$config_file")"
        fi
    done
    
    echo ""
    
    # Step 16: Restart all nodes
    log_info "Step 16: Restarting all nodes..."
    cd "$PROJECT_ROOT"
    
    if [ -f "./scripts/restart-all-nodes.sh" ]; then
        # Stop nodes first
        log_info "Stopping existing nodes..."
        pkill -f "keep-client.*start" >/dev/null 2>&1 || true
        sleep 2
        
        # Restart nodes
        log_info "Starting all nodes..."
        ./scripts/restart-all-nodes.sh >/dev/null 2>&1 || {
            log_warning "Node restart may have failed - you may need to start nodes manually"
        }
        log_success "All nodes restarted"
    else
        log_warning "restart-all-nodes.sh not found"
        log_info "Please start nodes manually: ./scripts/start-all-nodes.sh"
    fi
    echo ""
    
    # Step 17: Fix RandomBeacon configuration (upgrade and authorize)
    log_info "Step 17: Fixing RandomBeacon configuration (upgrade and authorize)..."
    cd "$PROJECT_ROOT"
    
    if [ -f "./solidity/ecdsa/scripts/fix-randombeacon-and-authorize.ts" ]; then
        cd "$PROJECT_ROOT/solidity/ecdsa"
        FIX_OUTPUT=$(npx hardhat run scripts/fix-randombeacon-and-authorize.ts --network development 2>&1)
        FIX_EXIT_CODE=$?
        
        # Filter out Hardhat warnings and show only important output
        echo "$FIX_OUTPUT" | grep -vE "(You are using a version|Please, make sure|To learn more|Error encountered|No need to generate|Contract Name|Size \(KB\)|^ ·|^ \||^---|Compiled|Compiling)" | grep -E "(Step|RandomBeacon|WalletRegistry|authorized|upgraded|SUCCESS|Error|error|Failed|failed|Transaction|✓|✗)" || true
        
        if [ $FIX_EXIT_CODE -eq 0 ] && echo "$FIX_OUTPUT" | grep -qE "SUCCESS.*RandomBeacon is fixed"; then
            log_success "RandomBeacon configuration fixed successfully"
        elif echo "$FIX_OUTPUT" | grep -qE "(already|already set|already authorized|already upgraded)"; then
            log_success "RandomBeacon configuration already correct"
        else
            log_warning "RandomBeacon fix script completed with warnings"
            log_info "You may need to run manually: cd solidity/ecdsa && npx hardhat run scripts/fix-randombeacon-and-authorize.ts --network development"
        fi
    else
        log_warning "fix-randombeacon-and-authorize.ts script not found"
        log_info "Skipping RandomBeacon fix - you may need to run it manually"
    fi
    echo ""
    
    echo "=========================================="
    log_success "Complete reset and initialization finished!"
    echo "=========================================="
    echo ""
    echo "Contract addresses:"
    echo "  RandomBeacon: $RANDOM_BEACON"
    echo "  WalletRegistry: $WALLET_REGISTRY"
    echo "  TokenStaking: $TOKEN_STAKING"
    if [ -n "$BRIDGE" ]; then
        echo "  Bridge: $BRIDGE"
        echo "  MaintainerProxy: $MAINTAINER_PROXY"
        echo "  WalletProposalValidator: $WALLET_PROPOSAL_VALIDATOR"
    fi
    echo ""
    echo "Next steps:"
    echo "  1. Verify operators are in sortition pools"
    echo "  2. Trigger DKG: ./scripts/request-new-wallet.sh"
    echo ""
}

main "$@"
