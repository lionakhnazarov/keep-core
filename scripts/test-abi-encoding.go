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
	// Create a test DKG result struct
	testResult := ecdsaabi.EcdsaDkgResult{
		SubmitterMemberIndex:     big.NewInt(1),
		GroupPubKey:              []byte{0x01, 0x02, 0x03},
		MisbehavedMembersIndices: []uint8{},
		Signatures:               []byte{0x04, 0x05, 0x06},
		SigningMembersIndices:    []*big.Int{big.NewInt(1), big.NewInt(2)},
		Members:                  []uint32{1, 2, 3},
		MembersHash:              [32]byte{0x07},
	}
	
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
	
	// Encode the arguments
	encoded, err := method.Inputs.Pack(testResult)
	if err != nil {
		fmt.Fprintf(os.Stderr, "Error encoding: %v\n", err)
		os.Exit(1)
	}
	
	// Compute hash (keccak256)
	hashBytes := crypto.Keccak256Hash(encoded).Bytes()
	
	fmt.Println("Encoded length:", len(encoded))
	fmt.Println("Encoded (first 100 bytes):", hex.EncodeToString(encoded[:min(100, len(encoded))]))
	fmt.Println("Hash:", hex.EncodeToString(hashBytes))
	
	// Also try encoding just the struct (without method selector)
	// Get the tuple type from the method inputs
	if len(method.Inputs) > 0 {
		tupleType := method.Inputs[0].Type
		fmt.Println("\nTuple type:", tupleType)
		
		// Try encoding the struct directly
		args := abi.Arguments{method.Inputs[0]}
		encoded2, err := args.Pack(testResult)
		if err != nil {
			fmt.Fprintf(os.Stderr, "Error encoding struct directly: %v\n", err)
		} else {
			hashBytes2 := crypto.Keccak256Hash(encoded2).Bytes()
			fmt.Println("Direct struct encoding hash:", hex.EncodeToString(hashBytes2))
		}
	}
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

