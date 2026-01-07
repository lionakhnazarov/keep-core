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

func main() {
	// Get the ABI
	contractABI := ecdsaabi.WalletRegistryMetaData.ABI
	
	// Parse the ABI
	parsedABI, err := abi.JSON(strings.NewReader(contractABI))
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing ABI: %v\n", err)
		os.Exit(1)
	}
	
	// Find the Result struct type definition
	// In Solidity, abi.encode(result) encodes the struct directly
	// We need to create an Arguments that matches the struct definition
	
	// Get the approveDkgResult method to extract the struct type
	method, exists := parsedABI.Methods["approveDkgResult"]
	if !exists {
		fmt.Fprintf(os.Stderr, "Could not find approveDkgResult method\n")
		os.Exit(1)
	}
	
	// The struct is the first (and only) input
	if len(method.Inputs) == 0 {
		fmt.Fprintf(os.Stderr, "Method has no inputs\n")
		os.Exit(1)
	}
	
	structArg := method.Inputs[0]
	
	// Create test data matching the actual submission
	// From the debug script, we know:
	// - submitterMemberIndex: 1
	// - groupPubKey: 130 bytes
	// - misbehavedMembersIndices: [] (empty)
	// - signatures: 13002 bytes
	// - signingMembersIndices: [100] values
	// - members: [100] values
	// - membersHash: 0xf4ae56d9805c0d82d39278d682ff07cc25fd992cd1146d4b90af53fefab880c9
	
	testResult := ecdsaabi.EcdsaDkgResult{
		SubmitterMemberIndex:     big.NewInt(1),
		GroupPubKey:              make([]byte, 130),
		MisbehavedMembersIndices: []uint8{},
		Signatures:               make([]byte, 13002),
		SigningMembersIndices:    make([]*big.Int, 100),
		Members:                  make([]uint32, 100),
		MembersHash:              [32]byte{},
	}
	
	// Fill in some test data
	for i := range testResult.SigningMembersIndices {
		testResult.SigningMembersIndices[i] = big.NewInt(int64(i + 1))
	}
	for i := range testResult.Members {
		testResult.Members[i] = uint32(i + 1)
	}
	
	// Set membersHash
	membersHashBytes, _ := hex.DecodeString("f4ae56d9805c0d82d39278d682ff07cc25fd992cd1146d4b90af53fefab880c9")
	copy(testResult.MembersHash[:], membersHashBytes)
	
	// Encode the struct directly (like Solidity's abi.encode(result))
	args := abi.Arguments{structArg}
	encoded, err := args.Pack(testResult)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error encoding: %v\n", err)
		os.Exit(1)
	}
	
	// Compute hash (keccak256)
	hashBytes := crypto.Keccak256Hash(encoded).Bytes()
	hashHex := hex.EncodeToString(hashBytes)
	
	fmt.Println("Test encoding:")
	fmt.Println("Hash:", hashHex)
	fmt.Println("")
	fmt.Println("Expected hash (from contract): 0xa4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75")
	fmt.Println("")
	
	if hashHex == "a4c691f074124bfbce638356b4c89d4d2d1966b0e29faa7f3ef9ed5fce7b4d75" {
		fmt.Println("✅ HASHES MATCH! Encoding is correct.")
	} else {
		fmt.Println("❌ HASHES DO NOT MATCH!")
		fmt.Println("")
		fmt.Println("This suggests the encoding order or method is different.")
		fmt.Println("The go-ethereum encoder might be using a different order than Solidity's abi.encode().")
	}
}

