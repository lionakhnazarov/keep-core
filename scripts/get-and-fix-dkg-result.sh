#!/bin/bash
# Script to get DKG result from contract and convert it to the correct format for approval
# Usage: ./scripts/get-and-fix-dkg-result.sh [config-file]

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

CONFIG_FILE=${1:-"configs/config.toml"}
OUTPUT_FILE="/tmp/dkg-result-from-contract.json"

echo "=========================================="
echo "Get DKG Result from Contract & Fix Format"
echo "=========================================="
echo ""

# Query the contract using Hardhat and save JSON directly
echo "Querying DkgResultSubmitted events from contract..."
cd solidity/ecdsa

TEMP_JSON=$(mktemp)

npx hardhat console --network development << 'EOF' > "$TEMP_JSON" 2>&1
const { ethers, helpers } = require("hardhat");
(async () => {
  try {
    const wr = await helpers.contracts.getContract("WalletRegistry");
    const filter = wr.filters.DkgResultSubmitted();
    const events = await wr.queryFilter(filter);
    
    if (events.length === 0) {
      console.error("No DkgResultSubmitted events found");
      process.exit(1);
    }
    
    const latestEvent = events[events.length - 1];
    const result = latestEvent.args.result;
    const dkgResultJson = {
      submitterMemberIndex: result.submitterMemberIndex.toNumber(),
      groupPubKey: result.groupPubKey,
      misbehavedMembersIndices: result.misbehavedMembersIndices.map(x => Number(x)),
      signatures: result.signatures,
      signingMembersIndices: result.signingMembersIndices.map(x => x.toNumber()),
      members: result.members.map(x => Number(x)),
      membersHash: result.membersHash || "0x0000000000000000000000000000000000000000000000000000000000000000"
    };
    console.log(JSON.stringify(dkgResultJson, null, 2));
    process.exit(0);
  } catch (error) {
    console.error("Error:", error.message);
    process.exit(1);
  }
})();
EOF

cd ../..

# Extract just the JSON (skip Hardhat output)
if [ ! -s "$TEMP_JSON" ]; then
    echo "Error: Could not query DKG result from contract"
    exit 1
fi

# Get the JSON part (usually the last valid JSON object)
JSON_LINES=$(grep -n "^{" "$TEMP_JSON" | tail -1 | cut -d: -f1)
if [ -n "$JSON_LINES" ]; then
    sed -n "${JSON_LINES},\$p" "$TEMP_JSON" > "${TEMP_JSON}.clean"
    mv "${TEMP_JSON}.clean" "$TEMP_JSON"
fi

# Fix the JSON: convert hex strings to base64 for byte arrays
if command -v python3 &> /dev/null; then
    echo "Converting hex strings to base64 for byte arrays..."
    python3 << PYEOF > "$OUTPUT_FILE"
import json
import base64
import sys

def hex_to_base64(hex_str):
    """Convert hex string (with or without 0x prefix) to base64"""
    if hex_str.startswith('0x'):
        hex_str = hex_str[2:]
    hex_str = hex_str.strip()
    try:
        bytes_data = bytes.fromhex(hex_str)
        return base64.b64encode(bytes_data).decode('ascii')
    except Exception as e:
        print(f"Error converting hex to base64: {e}", file=sys.stderr)
        return hex_str

with open('$TEMP_JSON', 'r') as f:
    data = json.load(f)

# Convert groupPubKey and signatures from hex to base64
if 'groupPubKey' in data and isinstance(data['groupPubKey'], str):
    data['groupPubKey'] = hex_to_base64(data['groupPubKey'])

if 'signatures' in data and isinstance(data['signatures'], str):
    data['signatures'] = hex_to_base64(data['signatures'])

# Convert membersHash from hex to array of 32 numbers
# Go's json.Unmarshal expects [32]byte as an array of numbers, not base64 string
if 'membersHash' in data and isinstance(data['membersHash'], str):
    if data['membersHash'].startswith('0x'):
        # Convert hex to bytes, then to array of numbers
        hex_str = data['membersHash'][2:]
        bytes_data = bytes.fromhex(hex_str)
    else:
        # Assume it's already base64, decode it
        bytes_data = base64.b64decode(data['membersHash'])
    
    if len(bytes_data) != 32:
        print(f"Warning: membersHash length is {len(bytes_data)}, expected 32", file=sys.stderr)
    
    # Convert to array of 32 integers (0-255)
    data['membersHash'] = [int(b) for b in bytes_data[:32]]

print(json.dumps(data, separators=(',', ':')))
PYEOF
    
    rm -f "$TEMP_JSON"
    
    echo ""
    echo "✓ Fixed JSON saved to: $OUTPUT_FILE"
    echo ""
    echo "You can now use it with:"
    echo "  KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry approve-dkg-result \"\$(cat $OUTPUT_FILE)\" \\"
    echo "    --submit --config $CONFIG_FILE --developer"
else
    echo "Error: python3 is required but not installed"
    echo "Raw JSON saved to: $TEMP_JSON"
    exit 1
fi

