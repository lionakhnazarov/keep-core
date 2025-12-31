#!/bin/bash
RB_POOL=$(jq -r '.address' solidity/random-beacon/deployments/development/BeaconSortitionPool.json)
WR_POOL=$(jq -r '.address' solidity/ecdsa/deployments/development/EcdsaSortitionPool.json)
RPC="http://localhost:8545"

printf "%-10s %-45s %-20s %-20s\n" "Node" "Operator Address" "RandomBeacon" "WalletRegistry"
echo "--------------------------------------------------------------------------------------------------------"

for config in configs/node*.toml; do
    NODE=$(basename "$config" | grep -oE '[0-9]+')
    KEYFILE=$(grep -E "^KeyFile\s*=" "$config" | cut -d'"' -f2)
    if [[ "$KEYFILE" != /* ]]; then KEYFILE="./$KEYFILE"; fi
    OPERATOR="0x$(cat "$KEYFILE" | jq -r '.address')"
    
    RB=$(cast call "$RB_POOL" "isOperatorInPool(address)(bool)" "$OPERATOR" --rpc-url "$RPC" 2>/dev/null)
    WR=$(cast call "$WR_POOL" "isOperatorInPool(address)(bool)" "$OPERATOR" --rpc-url "$RPC" 2>/dev/null)
    
    RB_SYM="✗"; [ "$RB" = "true" ] && RB_SYM="✓"
    WR_SYM="✗"; [ "$WR" = "true" ] && WR_SYM="✓"
    
    printf "%-10s %-45s %-20s %-20s\n" "node$NODE" "$OPERATOR" "$RB_SYM" "$WR_SYM"
done
