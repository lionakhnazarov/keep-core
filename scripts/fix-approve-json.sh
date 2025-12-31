#!/bin/bash
# Script to extract and fix the JSON from scripts/approve
# Converts string numbers to numeric values for Go's json.Unmarshal

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

APPROVE_FILE="scripts/approve"
OUTPUT_FILE="${1:-/tmp/dkg-result-fixed.json}"

if [ ! -f "$APPROVE_FILE" ]; then
    echo "Error: $APPROVE_FILE not found"
    exit 1
fi

echo "Extracting JSON from $APPROVE_FILE..."
echo ""

# Extract the JSON part (lines 2-210)
# The JSON starts with '{' (on line 1) and ends with '}'
TEMP_JSON=$(mktemp)
# Add opening brace
echo "{" > "$TEMP_JSON"
# Extract lines 2-210, remove leading spaces, remove the last line (which has the closing quote and backslash)
sed -n '2,210p' "$APPROVE_FILE" | sed 's/^  //' | sed '$d' >> "$TEMP_JSON"
# Add the closing brace
echo "}" >> "$TEMP_JSON"

# Fix the JSON: convert string numbers to numeric values and hex strings to base64
if command -v jq &> /dev/null && command -v python3 &> /dev/null; then
    echo "Fixing JSON format (converting strings to numbers and hex to base64)..."
    # First convert numbers
    NUM_TEMP="${TEMP_JSON}.num"
    jq '
      .submitterMemberIndex |= tonumber |
      .signingMembersIndices |= map(tonumber) |
      .members |= map(tonumber) |
      .misbehavedMembersIndices |= map(tonumber)
    ' "$TEMP_JSON" > "$NUM_TEMP"
    
    # Then convert hex strings to base64 using Python
    python3 << PYEOF > "$OUTPUT_FILE"
import json
import base64
import sys

def hex_to_base64(hex_str):
    """Convert hex string (with or without 0x prefix) to base64"""
    if hex_str.startswith('0x'):
        hex_str = hex_str[2:]
    # Remove any whitespace
    hex_str = hex_str.strip()
    try:
        bytes_data = bytes.fromhex(hex_str)
        return base64.b64encode(bytes_data).decode('ascii')
    except Exception as e:
        print(f"Error converting hex to base64: {e}", file=sys.stderr)
        return hex_str

with open('$NUM_TEMP', 'r') as f:
    data = json.load(f)

# Convert groupPubKey and signatures from hex to base64
if 'groupPubKey' in data and isinstance(data['groupPubKey'], str):
    data['groupPubKey'] = hex_to_base64(data['groupPubKey'])

if 'signatures' in data and isinstance(data['signatures'], str):
    data['signatures'] = hex_to_base64(data['signatures'])

print(json.dumps(data, separators=(',', ':')))
PYEOF
    
    rm -f "$NUM_TEMP"
    
    echo ""
    echo "✓ Fixed JSON saved to: $OUTPUT_FILE"
    echo ""
    echo "You can now use it with:"
    echo "  KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry approve-dkg-result '$(cat $OUTPUT_FILE)' \\"
    echo "    --submit --config configs/config.toml --developer"
    echo ""
    echo "Or save it to a file and use:"
    echo "  KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry approve-dkg-result \"\$(cat $OUTPUT_FILE)\" \\"
    echo "    --submit --config configs/config.toml --developer"
    
    rm -f "$TEMP_JSON"
else
    echo "Error: jq is required but not installed"
    echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
    echo ""
    echo "Raw JSON extracted to: $TEMP_JSON"
    echo "You'll need to manually convert string numbers to numeric values."
    exit 1
fi

