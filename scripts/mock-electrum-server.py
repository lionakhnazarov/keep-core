#!/usr/bin/env python3
"""
Mock Electrum Server for Deposit Sweep Testing

This server intercepts queries for the funding transaction hash from deposit reveals
and returns transaction data reconstructed from the deposit reveal's BitcoinTxInfo.
"""

import json
import socket
import threading
import sys
import os
from typing import Dict, Optional

# Add project root to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

# Configuration
SERVER_HOST = 'localhost'
SERVER_PORT = 50001
FUNDING_TX_HASH_ETH = None  # Will be set from deposit data
FUNDING_TX_HASH_BTC = None  # Bitcoin format (reversed bytes)
RAW_TX_HEX = None  # Raw transaction hex
BLOCK_HEIGHT = 100  # Fake block height for confirmations

def load_deposit_data():
    """Load deposit data and extract transaction information."""
    global FUNDING_TX_HASH_ETH, FUNDING_TX_HASH_BTC, RAW_TX_HEX
    
    deposit_data_file = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'deposit-data', 'deposit-data.json')
    
    if not os.path.exists(deposit_data_file):
        print(f"❌ Error: {deposit_data_file} not found")
        print("   Run: ./scripts/emulate-deposit.sh first")
        sys.exit(1)
    
    with open(deposit_data_file, 'r') as f:
        deposit_data = json.load(f)
    
    # Extract funding transaction hash (Ethereum format)
    FUNDING_TX_HASH_ETH = deposit_data.get('fundingTxHash', '').lower()
    if not FUNDING_TX_HASH_ETH or FUNDING_TX_HASH_ETH == 'null':
        print("❌ Error: fundingTxHash not found in deposit data")
        sys.exit(1)
    
    # Convert to Bitcoin format (reverse bytes, remove 0x)
    tx_hash_hex = FUNDING_TX_HASH_ETH.replace('0x', '')
    # Reverse bytes for Bitcoin (little-endian)
    FUNDING_TX_HASH_BTC = ''.join(reversed([tx_hash_hex[i:i+2] for i in range(0, len(tx_hash_hex), 2)]))
    
    # Reconstruct raw transaction from BitcoinTxInfo
    funding_tx_info = deposit_data.get('fundingTxInfo', {})
    if not funding_tx_info:
        print("❌ Error: fundingTxInfo not found in deposit data")
        sys.exit(1)
    
    version = funding_tx_info.get('version', '').replace('0x', '')
    input_vector = funding_tx_info.get('inputVector', '').replace('0x', '')
    output_vector = funding_tx_info.get('outputVector', '').replace('0x', '')
    locktime = funding_tx_info.get('locktime', '').replace('0x', '')
    
    RAW_TX_HEX = version + input_vector + output_vector + locktime
    
    print(f"✅ Loaded deposit data:")
    print(f"   Funding TX Hash (Ethereum): {FUNDING_TX_HASH_ETH}")
    print(f"   Funding TX Hash (Bitcoin): {FUNDING_TX_HASH_BTC}")
    print(f"   Raw TX Length: {len(RAW_TX_HEX) // 2} bytes")

def handle_request(request: Dict) -> Optional[Dict]:
    """Handle an Electrum protocol request."""
    method = request.get('method', '')
    params = request.get('params', [])
    request_id = request.get('id')
    
    # blockchain.transaction.get - Return raw transaction
    if method == 'blockchain.transaction.get':
        tx_hash = params[0] if params else None
        verbose = params[1] if len(params) > 1 else False
        
        if tx_hash and tx_hash.lower() == FUNDING_TX_HASH_BTC.lower():
            if verbose:
                # Return verbose transaction info
                return {
                    'id': request_id,
                    'result': {
                        'hex': RAW_TX_HEX,
                        'txid': FUNDING_TX_HASH_BTC,
                        'hash': FUNDING_TX_HASH_BTC,
                        'size': len(RAW_TX_HEX) // 2,
                        'vsize': len(RAW_TX_HEX) // 2,
                        'weight': len(RAW_TX_HEX) // 2 * 4,
                        'version': 1,
                        'locktime': 0,
                        'vin': [],
                        'vout': [],
                        'blockhash': '0' * 64,  # Fake block hash
                        'confirmations': 100,  # Fake confirmations (> 6 required)
                        'time': 1234567890,
                        'blocktime': 1234567890,
                        'blockheight': BLOCK_HEIGHT
                    }
                }
            else:
                # Return raw hex
                return {
                    'id': request_id,
                    'result': RAW_TX_HEX
                }
        else:
            # Transaction not found
            return {
                'id': request_id,
                'error': {
                    'code': -32603,
                    'message': f'Transaction {tx_hash} not found'
                }
            }
    
    # blockchain.transaction.get_merkle - Return merkle proof
    elif method == 'blockchain.transaction.get_merkle':
        tx_hash = params[0] if params else None
        block_height = params[1] if len(params) > 1 else None
        
        if tx_hash and tx_hash.lower() == FUNDING_TX_HASH_BTC.lower():
            # Return fake merkle proof
            return {
                'id': request_id,
                'result': {
                    'block_height': BLOCK_HEIGHT,
                    'merkle': ['0' * 64] * 10,  # Fake merkle path
                    'pos': 0
                }
            }
    
    # blockchain.block.header - Return block header
    elif method == 'blockchain.block.header':
        block_height = params[0] if params else None
        if block_height == BLOCK_HEIGHT:
            # Return fake block header (80 bytes)
            return {
                'id': request_id,
                'result': '0' * 160  # 80 bytes = 160 hex chars
            }
    
    # blockchain.headers.subscribe - Subscribe to block headers (used for GetLatestBlockHeight)
    elif method == 'blockchain.headers.subscribe':
        # Return current block header info
        # Format: {'height': int, 'hex': str}
        return {
            'id': request_id,
            'result': {
                'height': BLOCK_HEIGHT,
                'hex': '0' * 160  # 80-byte block header in hex
            }
        }
    
    # blockchain.scripthash.get_history - Return transaction history
    elif method == 'blockchain.scripthash.get_history':
        script_hash = params[0] if params else None
        # Return empty history or include our transaction
        return {
            'id': request_id,
            'result': [
                {
                    'height': BLOCK_HEIGHT,
                    'tx_hash': FUNDING_TX_HASH_BTC
                }
            ]
        }
    
    # server.version - Return server version
    elif method == 'server.version':
        client_name = params[0] if params else 'unknown'
        protocol_version = params[1] if len(params) > 1 else '1.4'
        return {
            'id': request_id,
            'result': ['Mock Electrum Server 1.0', '1.4']
        }
    
    # server.banner - Return server banner
    elif method == 'server.banner':
        return {
            'id': request_id,
            'result': 'Mock Electrum Server for Deposit Testing'
        }
    
    # server.ping - Health check / keep-alive
    elif method == 'server.ping':
        return {
            'id': request_id,
            'result': None  # Ping typically returns null/None
        }
    
    # server.peers.subscribe - Return empty peer list
    elif method == 'server.peers.subscribe':
        return {
            'id': request_id,
            'result': []
        }
    
    # Default: Method not found
    return {
        'id': request_id,
        'error': {
            'code': -32601,
            'message': f'Method {method} not found'
        }
    }

def handle_client(client_socket, address):
    """Handle a client connection."""
    print(f"📡 Client connected: {address}")
    
    buffer = ''
    try:
        while True:
            data = client_socket.recv(4096).decode('utf-8')
            if not data:
                break
            
            buffer += data
            
            # Process complete JSON-RPC messages
            while '\n' in buffer:
                line, buffer = buffer.split('\n', 1)
                line = line.strip()
                if not line:
                    continue
                
                try:
                    request = json.loads(line)
                    response = handle_request(request)
                    if response:
                        response_json = json.dumps(response) + '\n'
                        client_socket.send(response_json.encode('utf-8'))
                        print(f"   → {request.get('method', 'unknown')}: {request.get('id', '?')}")
                except json.JSONDecodeError as e:
                    print(f"   ⚠️  JSON decode error: {e}")
                    print(f"   Data: {line[:100]}")
    
    except Exception as e:
        print(f"   ❌ Error handling client {address}: {e}")
    finally:
        client_socket.close()
        print(f"📡 Client disconnected: {address}")

def main():
    """Main server function."""
    print("==========================================")
    print("Mock Electrum Server for Deposit Testing")
    print("==========================================")
    print("")
    
    # Load deposit data
    load_deposit_data()
    
    # Create socket
    server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server_socket.bind((SERVER_HOST, SERVER_PORT))
    server_socket.listen(5)
    
    print(f"✅ Server listening on {SERVER_HOST}:{SERVER_PORT}")
    print(f"")
    print(f"Configure nodes to use:")
    print(f"  URL = \"tcp://{SERVER_HOST}:{SERVER_PORT}\"")
    print(f"")
    print(f"Press Ctrl+C to stop")
    print(f"")
    
    try:
        while True:
            client_socket, address = server_socket.accept()
            client_thread = threading.Thread(
                target=handle_client,
                args=(client_socket, address)
            )
            client_thread.daemon = True
            client_thread.start()
    except KeyboardInterrupt:
        print("\n🛑 Shutting down server...")
    finally:
        server_socket.close()

if __name__ == '__main__':
    main()

