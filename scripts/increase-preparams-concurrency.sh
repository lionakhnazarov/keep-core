#!/bin/bash
# Script to increase pre-parameters generation concurrency in all node config files
# This speeds up pre-parameter generation so DKG can start faster

set -eou pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_DIR="${CONFIG_DIR:-$PROJECT_ROOT/configs}"

# Default concurrency (can be overridden)
CONCURRENCY=${1:-4}

echo "=========================================="
echo "Increase Pre-Parameters Generation Concurrency"
echo "=========================================="
echo ""
echo "Setting PreParamsGenerationConcurrency to $CONCURRENCY"
echo ""

cd "$PROJECT_ROOT"

# Find all node config files
NODE_CONFIGS=()
for config in "$CONFIG_DIR"/node*.toml; do
    if [ -f "$config" ]; then
        NODE_CONFIGS+=("$config")
    fi
done

if [ ${#NODE_CONFIGS[@]} -eq 0 ]; then
    echo "Error: No node*.toml config files found in $CONFIG_DIR"
    exit 1
fi

echo "Found ${#NODE_CONFIGS[@]} node config file(s)"
echo ""

# Update each config file
for config_file in "${NODE_CONFIGS[@]}"; do
    echo "Updating $(basename "$config_file")..."
    
    # Check if [tbtc] section exists
    if grep -q "^\[tbtc\]" "$config_file"; then
        # Section exists, update PreParamsGenerationConcurrency if it exists
        if grep -q "PreParamsGenerationConcurrency" "$config_file"; then
            # Update existing value
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "s/PreParamsGenerationConcurrency = .*/PreParamsGenerationConcurrency = $CONCURRENCY/" "$config_file"
            else
                sed -i "s/PreParamsGenerationConcurrency = .*/PreParamsGenerationConcurrency = $CONCURRENCY/" "$config_file"
            fi
        else
            # Add PreParamsGenerationConcurrency to existing section
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' "/^\[tbtc\]/a\\
PreParamsGenerationConcurrency = $CONCURRENCY
" "$config_file"
            else
                sed -i "/^\[tbtc\]/a PreParamsGenerationConcurrency = $CONCURRENCY" "$config_file"
            fi
        fi
    else
        # Section doesn't exist, add it at the end
        cat >> "$config_file" << EOF

[tbtc]
PreParamsGenerationConcurrency = $CONCURRENCY
PreParamsGenerationDelay = "5s"
EOF
    fi
    
    echo "  ✓ Updated"
done

echo ""
echo "=========================================="
echo "✓ All config files updated!"
echo "=========================================="
echo ""
echo "Pre-parameters will now be generated with concurrency $CONCURRENCY"
echo ""
echo "Note: You need to restart the nodes for the changes to take effect:"
echo "  ./scripts/restart-all-nodes.sh"
echo ""

