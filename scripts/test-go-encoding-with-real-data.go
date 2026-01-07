package main

import (
	"encoding/hex"
	"fmt"
	"math/big"
	"os"
	"strings"
	
	"github.com/ethereum/go-ethereum/accounts/abi"
	"github.com/ethereum/go-ethereum/crypto"
	ecdsaabi "github.com/keep-network/keep-core/pkg/chain/ethereum/ecdsa/gen/abi"
)

// This script tests encoding with actual data extracted from the chain event
// Run: go run scripts/test-go-encoding-with-real-data.go
func main() {
	if len(os.Args) < 2 {
		fmt.Println("Usage: go run scripts/test-go-encoding-with-real-data.go <event_data_json>")
		fmt.Println("")
		fmt.Println("Or run: cd solidity/ecdsa && npx hardhat run scripts/extract-event-data.ts --network development")
		fmt.Println("Then paste the JSON output here")
		os.Exit(1)
	}
	
	// TODO: Parse JSON from event and create EcdsaDkgResult
	// For now, this is a template
	
	// Get the ABI
	contractABI := ecdsaabi.WalletRegistryMetaData.ABI
	
	// Parse the ABI
	parsedABI, err := abi.JSON(strings.NewReader(contractABI))
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing ABI: %v\n", err)
		os.Exit(1)
	}
	
	// Get the approveDkgResult method
	method, exists := parsedABI.Methods["approveDkgResult"]
	if !exists {
		fmt.Fprintf(os.Stderr, "Could not find approveDkgResult method\n")
		os.Exit(1)
	}
	
	// Extract struct argument
	structArg := method.Inputs[0]
	
	// Create result from event data (to be filled in)
	result := ecdsaabi.EcdsaDkgResult{
		// Fill with actual event data
	}
	
	// Encode
	args := abi.Arguments{structArg}
	encoded, err := args.Pack(result)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error encoding: %v\n", err)
		os.Exit(1)
	}
	
	// Compute hash
	hashBytes := crypto.Keccak256Hash(encoded).Bytes()
	hashHex := hex.EncodeToString(hashBytes)
	
	fmt.Println("Computed hash:", hashHex)
	fmt.Println("Expected hash: a4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75")
	
	if hashHex == "a4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75" {
		fmt.Println("✅ HASHES MATCH!")
	} else {
		fmt.Println("❌ HASHES DO NOT MATCH!")
		fmt.Println("")
		fmt.Println("This confirms the encoding issue.")
	}
}

