package main

import (
	"fmt"
	"reflect"
	"strings"
	
	ecdsaabi "github.com/keep-network/keep-core/pkg/chain/ethereum/ecdsa/gen/abi"
)

func main() {
	// Create an instance of the struct
	result := ecdsaabi.EcdsaDkgResult{}
	
	// Use reflection to get field order
	t := reflect.TypeOf(result)
	
	fmt.Println("Go struct field order (via reflection):")
	fmt.Println(strings.Repeat("=", 60))
	for i := 0; i < t.NumField(); i++ {
		field := t.Field(i)
		fmt.Printf("%2d. %s (%s)\n", i+1, field.Name, field.Type)
	}
	
	fmt.Println("\n")
	fmt.Println("Expected order (from Solidity/ABI):")
	fmt.Println(strings.Repeat("=", 60))
	fmt.Println(" 1. submitterMemberIndex")
	fmt.Println(" 2. groupPubKey")
	fmt.Println(" 3. misbehavedMembersIndices")
	fmt.Println(" 4. signatures")
	fmt.Println(" 5. signingMembersIndices")
	fmt.Println(" 6. members")
	fmt.Println(" 7. membersHash")
}

