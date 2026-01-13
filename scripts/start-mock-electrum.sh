#!/bin/bash
# Start the mock Electrum server for deposit testing

cd "$(dirname "$0")/.."

echo "=========================================="
echo "Starting Mock Electrum Server"
echo "=========================================="
echo ""

# Check if deposit data exists
if [ ! -f "deposit-data/deposit-data.json" ]; then
  echo "❌ Error: deposit-data/deposit-data.json not found"
  echo "   Run: ./scripts/emulate-deposit.sh first"
  exit 1
fi

# Check if Python 3 is available
if ! command -v python3 &> /dev/null; then
  echo "❌ Error: python3 not found"
  echo "   Install Python 3 to run the mock server"
  exit 1
fi

# Check if server is already running
if lsof -Pi :50001 -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo "⚠️  Mock Electrum server already running on port 50001"
  echo "   Stopping existing server..."
  pkill -f "mock-electrum-server.py" || true
  sleep 2
fi

echo "Starting mock Electrum server..."
echo ""

# Start server in background
python3 scripts/mock-electrum-server.py > /tmp/mock-electrum.log 2>&1 &
SERVER_PID=$!

sleep 2

# Check if server started
if ! kill -0 $SERVER_PID 2>/dev/null; then
  echo "❌ Failed to start server"
  echo "   Check logs: tail -f /tmp/mock-electrum.log"
  exit 1
fi

echo "✅ Mock Electrum server started (PID: $SERVER_PID)"
echo ""
echo "Server is listening on: tcp://localhost:50001"
echo ""
echo "Next steps:"
echo "  1. Update config.toml to use: URL = \"tcp://localhost:50001\""
echo "  2. Restart nodes"
echo ""
echo "To stop the server:"
echo "  kill $SERVER_PID"
echo "  or: pkill -f mock-electrum-server.py"
echo ""
echo "View logs:"
echo "  tail -f /tmp/mock-electrum.log"
echo ""

