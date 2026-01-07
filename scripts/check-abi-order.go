package main

import (
	"encoding/json"
	"fmt"
	"os"
	
	ecdsaabi "github.com/keep-network/keep-core/pkg/chain/ethereum/ecdsa/gen/abi"
)

func main() {
	// Get the ABI from metadata
	abiJSON := ecdsaabi.WalletRegistryMetaData.ABI
	
	// Parse the ABI
	var abi []map[string]interface{}
	if err := json.Unmarshal([]byte(abiJSON), &abi); err != nil {
		fmt.Fprintf(os.Stderr, "Error parsing ABI: %v\n", err)
		os.Exit(1)
	}
	
	// Find approveDkgResult
	for _, item := range abi {
		if name, ok := item["name"].(string); ok && name == "approveDkgResult" {
			if inputs, ok := item["inputs"].([]interface{}); ok {
				for _, input := range inputs {
					if inp, ok := input.(map[string]interface{}); ok {
						if typ, ok := inp["type"].(string); ok && typ == "tuple" {
							if components, ok := inp["components"].([]interface{}); ok {
								fmt.Println("ABI JSON component order for approveDkgResult:")
								fmt.Println("============================================================")
								for i, comp := range components {
									if c, ok := comp.(map[string]interface{}); ok {
										name := c["name"].(string)
										typ := c["type"].(string)
										fmt.Printf("%2d. %-30s (%s)\n", i+1, name, typ)
									}
								}
								
								// Also check submitDkgResult for comparison
								fmt.Println("\nABI JSON component order for submitDkgResult:")
								fmt.Println("============================================================")
								for _, item2 := range abi {
									if name2, ok := item2["name"].(string); ok && name2 == "submitDkgResult" {
										if inputs2, ok := item2["inputs"].([]interface{}); ok {
											for _, input2 := range inputs2 {
												if inp2, ok := input2.(map[string]interface{}); ok {
													if typ2, ok := inp2["type"].(string); ok && typ2 == "tuple" {
														if components2, ok := inp2["components"].([]interface{}); ok {
															for i, comp := range components2 {
																if c, ok := comp.(map[string]interface{}); ok {
																	name := c["name"].(string)
																	typ := c["type"].(string)
																	fmt.Printf("%2d. %-30s (%s)\n", i+1, name, typ)
																}
															}
														}
													}
												}
											}
										}
									}
								}
								
								return
							}
						}
					}
				}
			}
		}
	}
	fmt.Println("Could not find approveDkgResult in ABI")
	os.Exit(1)
}

