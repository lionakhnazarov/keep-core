#!/bin/bash
# Script to fix DKG result JSON format - converts string numbers to numeric values
# Usage: ./scripts/fix-dkg-result-json.sh <input-json-file> [output-json-file]
#
# This fixes the common issue where JSON has string values like "1" instead of
# numeric values like 1 for *big.Int and uint32 fields.

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

INPUT_FILE="$1"
OUTPUT_FILE="${2:-${INPUT_FILE}.fixed}"

if [ -z "$INPUT_FILE" ] || [ ! -f "$INPUT_FILE" ]; then
    echo "Usage: $0 <input-json-file> [output-json-file]"
    echo ""
    echo "Fixes DKG result JSON by converting string numbers to numeric values."
    echo "Required for Go's json.Unmarshal to work with *big.Int fields."
    exit 1
fi

echo "Fixing DKG result JSON format..."
echo "Input:  $INPUT_FILE"
echo "Output: $OUTPUT_FILE"
echo ""

# Use jq to convert string numbers to numeric values
# Fields that need to be numeric:
# - submitterMemberIndex: *big.Int -> number
# - signingMembersIndices: []*big.Int -> []number
# - members: []uint32 -> []number
# - misbehavedMembersIndices: []uint8 -> []number

if command -v jq &> /dev/null; then
    jq '
      .submitterMemberIndex |= tonumber |
      .signingMembersIndices |= map(tonumber) |
      .members |= map(tonumber) |
      .misbehavedMembersIndices |= map(tonumber)
    ' "$INPUT_FILE" > "$OUTPUT_FILE"
    
    echo "✓ Fixed JSON saved to: $OUTPUT_FILE"
    echo ""
    echo "You can now use it with:"
    echo "  KEEP_ETHEREUM_PASSWORD=password ./keep-client ethereum ecdsa wallet-registry approve-dkg-result '$(cat $OUTPUT_FILE)' \\"
    echo "    --submit --config configs/config.toml --developer"
else
    echo "Error: jq is required but not installed"
    echo "Install with: brew install jq (macOS) or apt-get install jq (Linux)"
    exit 1
fi

