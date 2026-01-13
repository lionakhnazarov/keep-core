// Code generated - DO NOT EDIT.
// This file is a generated command and any manual changes will be lost.

package cmd

import (
	"context"
	"fmt"
	"math/big"
	"sync"

	"github.com/ethereum/go-ethereum/common/hexutil"
	"github.com/ethereum/go-ethereum/core/types"
	"github.com/ethereum/go-ethereum/ethclient"

	chainutil "github.com/keep-network/keep-common/pkg/chain/ethereum/ethutil"
	"github.com/keep-network/keep-common/pkg/cmd"
	"github.com/keep-network/keep-common/pkg/utils/decode"
	"github.com/keep-network/keep-core/pkg/chain/ethereum/threshold/gen/contract"

	"github.com/spf13/cobra"
)

var TokenStakingCommand *cobra.Command

var tokenStakingDescription = `The token-staking command allows calling the TokenStaking contract on an
	Ethereum network. It has subcommands corresponding to each contract method,
	which respectively each take parameters based on the contract method's
	parameters.

	Subcommands will submit a non-mutating call to the network and output the
	result.

	All subcommands can be called against a specific block by passing the
	-b/--block flag.

	Subcommands for mutating methods may be submitted as a mutating transaction
	by passing the -s/--submit flag. In this mode, this command will terminate
	successfully once the transaction has been submitted, but will not wait for
	the transaction to be included in a block. They return the transaction hash.

	Calls that require ether to be paid will get 0 ether by default, which can
	be changed by passing the -v/--value flag.`

func init() {
	TokenStakingCommand := &cobra.Command{
		Use:   "token-staking",
		Short: `Provides access to the TokenStaking contract.`,
		Long:  tokenStakingDescription,
	}

	TokenStakingCommand.AddCommand(
		tsApplicationInfoCommand(),
		tsApplicationsCommand(),
		tsAuthorizationCeilingCommand(),
		tsAuthorizedStakeCommand(),
		tsCheckpointsCommand(),
		tsDelegatesCommand(),
		tsGetApplicationsLengthCommand(),
		tsGetAvailableToAuthorizeCommand(),
		tsGetMaxAuthorizationCommand(),
		tsGetPastTotalSupplyCommand(),
		tsGetPastVotesCommand(),
		tsGetStartStakingTimestampCommand(),
		tsGetVotesCommand(),
		tsGovernanceCommand(),
		tsMinTStakeAmountCommand(),
		tsNotifiersTreasuryCommand(),
		tsNumCheckpointsCommand(),
		tsRolesOfCommand(),
		tsStakeAmountCommand(),
		tsStakesCommand(),
		tsApproveAuthorizationDecreaseCommand(),
		tsDelegateVotingCommand(),
		tsDisableApplicationCommand(),
		tsForceDecreaseAuthorizationCommand(),
		tsInitializeCommand(),
		tsPauseApplicationCommand(),
		tsRequestAuthorizationDecreaseCommand(),
		tsSetAuthorizationCeilingCommand(),
		tsSetMinimumStakeAmountCommand(),
		tsSetPanicButtonCommand(),
		tsTransferGovernanceCommand(),
		tsUnstakeTCommand(),
		tsWithdrawNotificationRewardCommand(),
	)

	ModuleCommand.AddCommand(TokenStakingCommand)
}

/// ------------------- Const methods -------------------

func tsApplicationInfoCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "application-info [arg0]",
		Short:                 "Calls the view method applicationInfo on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsApplicationInfo,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsApplicationInfo(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg0, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg0, a address, from passed value %v",
			args[0],
		)
	}

	result, err := contract.ApplicationInfoAtBlock(
		arg0,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsApplicationsCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "applications [arg0]",
		Short:                 "Calls the view method applications on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsApplications,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsApplications(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg0, err := hexutil.DecodeBig(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg0, a uint256, from passed value %v",
			args[0],
		)
	}

	result, err := contract.ApplicationsAtBlock(
		arg0,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsAuthorizationCeilingCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "authorization-ceiling",
		Short:                 "Calls the view method authorizationCeiling on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(0),
		RunE:                  tsAuthorizationCeiling,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsAuthorizationCeiling(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	result, err := contract.AuthorizationCeilingAtBlock(
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsAuthorizedStakeCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "authorized-stake [arg_stakingProvider] [arg_application]",
		Short:                 "Calls the view method authorizedStake on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(2),
		RunE:                  tsAuthorizedStake,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsAuthorizedStake(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_stakingProvider, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_stakingProvider, a address, from passed value %v",
			args[0],
		)
	}
	arg_application, err := chainutil.AddressFromHex(args[1])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_application, a address, from passed value %v",
			args[1],
		)
	}

	result, err := contract.AuthorizedStakeAtBlock(
		arg_stakingProvider,
		arg_application,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsCheckpointsCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "checkpoints [arg_account] [arg_pos]",
		Short:                 "Calls the view method checkpoints on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(2),
		RunE:                  tsCheckpoints,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsCheckpoints(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_account, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_account, a address, from passed value %v",
			args[0],
		)
	}
	arg_pos, err := decode.ParseUint[uint32](args[1], 32)
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_pos, a uint32, from passed value %v",
			args[1],
		)
	}

	result, err := contract.CheckpointsAtBlock(
		arg_account,
		arg_pos,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsDelegatesCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "delegates [arg_account]",
		Short:                 "Calls the view method delegates on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsDelegates,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsDelegates(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_account, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_account, a address, from passed value %v",
			args[0],
		)
	}

	result, err := contract.DelegatesAtBlock(
		arg_account,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsGetApplicationsLengthCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "get-applications-length",
		Short:                 "Calls the view method getApplicationsLength on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(0),
		RunE:                  tsGetApplicationsLength,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsGetApplicationsLength(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	result, err := contract.GetApplicationsLengthAtBlock(
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsGetAvailableToAuthorizeCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "get-available-to-authorize [arg_stakingProvider] [arg_application]",
		Short:                 "Calls the view method getAvailableToAuthorize on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(2),
		RunE:                  tsGetAvailableToAuthorize,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsGetAvailableToAuthorize(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_stakingProvider, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_stakingProvider, a address, from passed value %v",
			args[0],
		)
	}
	arg_application, err := chainutil.AddressFromHex(args[1])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_application, a address, from passed value %v",
			args[1],
		)
	}

	result, err := contract.GetAvailableToAuthorizeAtBlock(
		arg_stakingProvider,
		arg_application,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsGetMaxAuthorizationCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "get-max-authorization [arg_stakingProvider]",
		Short:                 "Calls the view method getMaxAuthorization on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsGetMaxAuthorization,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsGetMaxAuthorization(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_stakingProvider, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_stakingProvider, a address, from passed value %v",
			args[0],
		)
	}

	result, err := contract.GetMaxAuthorizationAtBlock(
		arg_stakingProvider,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsGetPastTotalSupplyCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "get-past-total-supply [arg_blockNumber]",
		Short:                 "Calls the view method getPastTotalSupply on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsGetPastTotalSupply,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsGetPastTotalSupply(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_blockNumber, err := hexutil.DecodeBig(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_blockNumber, a uint256, from passed value %v",
			args[0],
		)
	}

	result, err := contract.GetPastTotalSupplyAtBlock(
		arg_blockNumber,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsGetPastVotesCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "get-past-votes [arg_account] [arg_blockNumber]",
		Short:                 "Calls the view method getPastVotes on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(2),
		RunE:                  tsGetPastVotes,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsGetPastVotes(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_account, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_account, a address, from passed value %v",
			args[0],
		)
	}
	arg_blockNumber, err := hexutil.DecodeBig(args[1])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_blockNumber, a uint256, from passed value %v",
			args[1],
		)
	}

	result, err := contract.GetPastVotesAtBlock(
		arg_account,
		arg_blockNumber,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsGetStartStakingTimestampCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "get-start-staking-timestamp [arg_stakingProvider]",
		Short:                 "Calls the view method getStartStakingTimestamp on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsGetStartStakingTimestamp,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsGetStartStakingTimestamp(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_stakingProvider, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_stakingProvider, a address, from passed value %v",
			args[0],
		)
	}

	result, err := contract.GetStartStakingTimestampAtBlock(
		arg_stakingProvider,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsGetVotesCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "get-votes [arg_account]",
		Short:                 "Calls the view method getVotes on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsGetVotes,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsGetVotes(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_account, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_account, a address, from passed value %v",
			args[0],
		)
	}

	result, err := contract.GetVotesAtBlock(
		arg_account,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsGovernanceCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "governance",
		Short:                 "Calls the view method governance on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(0),
		RunE:                  tsGovernance,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsGovernance(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	result, err := contract.GovernanceAtBlock(
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsMinTStakeAmountCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "min-t-stake-amount",
		Short:                 "Calls the view method minTStakeAmount on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(0),
		RunE:                  tsMinTStakeAmount,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsMinTStakeAmount(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	result, err := contract.MinTStakeAmountAtBlock(
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsNotifiersTreasuryCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "notifiers-treasury",
		Short:                 "Calls the view method notifiersTreasury on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(0),
		RunE:                  tsNotifiersTreasury,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsNotifiersTreasury(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	result, err := contract.NotifiersTreasuryAtBlock(
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsNumCheckpointsCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "num-checkpoints [arg_account]",
		Short:                 "Calls the view method numCheckpoints on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsNumCheckpoints,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsNumCheckpoints(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_account, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_account, a address, from passed value %v",
			args[0],
		)
	}

	result, err := contract.NumCheckpointsAtBlock(
		arg_account,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsRolesOfCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "roles-of [arg_stakingProvider]",
		Short:                 "Calls the view method rolesOf on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsRolesOf,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsRolesOf(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_stakingProvider, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_stakingProvider, a address, from passed value %v",
			args[0],
		)
	}

	result, err := contract.RolesOfAtBlock(
		arg_stakingProvider,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsStakeAmountCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "stake-amount [arg_stakingProvider]",
		Short:                 "Calls the view method stakeAmount on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsStakeAmount,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsStakeAmount(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_stakingProvider, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_stakingProvider, a address, from passed value %v",
			args[0],
		)
	}

	result, err := contract.StakeAmountAtBlock(
		arg_stakingProvider,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

func tsStakesCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "stakes [arg_stakingProvider]",
		Short:                 "Calls the view method stakes on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsStakes,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	cmd.InitConstFlags(c)

	return c
}

func tsStakes(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_stakingProvider, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_stakingProvider, a address, from passed value %v",
			args[0],
		)
	}

	result, err := contract.StakesAtBlock(
		arg_stakingProvider,
		cmd.BlockFlagValue.Int,
	)

	if err != nil {
		return err
	}

	cmd.PrintOutput(result)

	return nil
}

/// ------------------- Non-const methods -------------------

func tsApproveAuthorizationDecreaseCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "approve-authorization-decrease [arg_stakingProvider]",
		Short:                 "Calls the nonpayable method approveAuthorizationDecrease on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsApproveAuthorizationDecrease,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	c.PreRunE = cmd.NonConstArgsChecker
	cmd.InitNonConstFlags(c)

	return c
}

func tsApproveAuthorizationDecrease(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_stakingProvider, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_stakingProvider, a address, from passed value %v",
			args[0],
		)
	}

	var (
		transaction *types.Transaction
		result      *big.Int
	)

	if shouldSubmit, _ := c.Flags().GetBool(cmd.SubmitFlag); shouldSubmit {
		// Do a regular submission. Take payable into account.
		transaction, err = contract.ApproveAuthorizationDecrease(
			arg_stakingProvider,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput(transaction.Hash())
	} else {
		// Do a call.
		result, err = contract.CallApproveAuthorizationDecrease(
			arg_stakingProvider,
			cmd.BlockFlagValue.Int,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput(result)

		cmd.PrintOutput(
			"the transaction was not submitted to the chain; " +
				"please add the `--submit` flag",
		)
	}

	return nil
}

func tsDelegateVotingCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "delegate-voting [arg_stakingProvider] [arg_delegatee]",
		Short:                 "Calls the nonpayable method delegateVoting on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(2),
		RunE:                  tsDelegateVoting,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	c.PreRunE = cmd.NonConstArgsChecker
	cmd.InitNonConstFlags(c)

	return c
}

func tsDelegateVoting(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_stakingProvider, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_stakingProvider, a address, from passed value %v",
			args[0],
		)
	}
	arg_delegatee, err := chainutil.AddressFromHex(args[1])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_delegatee, a address, from passed value %v",
			args[1],
		)
	}

	var (
		transaction *types.Transaction
	)

	if shouldSubmit, _ := c.Flags().GetBool(cmd.SubmitFlag); shouldSubmit {
		// Do a regular submission. Take payable into account.
		transaction, err = contract.DelegateVoting(
			arg_stakingProvider,
			arg_delegatee,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput(transaction.Hash())
	} else {
		// Do a call.
		err = contract.CallDelegateVoting(
			arg_stakingProvider,
			arg_delegatee,
			cmd.BlockFlagValue.Int,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput("success")

		cmd.PrintOutput(
			"the transaction was not submitted to the chain; " +
				"please add the `--submit` flag",
		)
	}

	return nil
}

func tsDisableApplicationCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "disable-application [arg_application]",
		Short:                 "Calls the nonpayable method disableApplication on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsDisableApplication,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	c.PreRunE = cmd.NonConstArgsChecker
	cmd.InitNonConstFlags(c)

	return c
}

func tsDisableApplication(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_application, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_application, a address, from passed value %v",
			args[0],
		)
	}

	var (
		transaction *types.Transaction
	)

	if shouldSubmit, _ := c.Flags().GetBool(cmd.SubmitFlag); shouldSubmit {
		// Do a regular submission. Take payable into account.
		transaction, err = contract.DisableApplication(
			arg_application,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput(transaction.Hash())
	} else {
		// Do a call.
		err = contract.CallDisableApplication(
			arg_application,
			cmd.BlockFlagValue.Int,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput("success")

		cmd.PrintOutput(
			"the transaction was not submitted to the chain; " +
				"please add the `--submit` flag",
		)
	}

	return nil
}

func tsForceDecreaseAuthorizationCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "force-decrease-authorization [arg_stakingProvider] [arg_application]",
		Short:                 "Calls the nonpayable method forceDecreaseAuthorization on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(2),
		RunE:                  tsForceDecreaseAuthorization,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	c.PreRunE = cmd.NonConstArgsChecker
	cmd.InitNonConstFlags(c)

	return c
}

func tsForceDecreaseAuthorization(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_stakingProvider, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_stakingProvider, a address, from passed value %v",
			args[0],
		)
	}
	arg_application, err := chainutil.AddressFromHex(args[1])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_application, a address, from passed value %v",
			args[1],
		)
	}

	var (
		transaction *types.Transaction
	)

	if shouldSubmit, _ := c.Flags().GetBool(cmd.SubmitFlag); shouldSubmit {
		// Do a regular submission. Take payable into account.
		transaction, err = contract.ForceDecreaseAuthorization(
			arg_stakingProvider,
			arg_application,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput(transaction.Hash())
	} else {
		// Do a call.
		err = contract.CallForceDecreaseAuthorization(
			arg_stakingProvider,
			arg_application,
			cmd.BlockFlagValue.Int,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput("success")

		cmd.PrintOutput(
			"the transaction was not submitted to the chain; " +
				"please add the `--submit` flag",
		)
	}

	return nil
}

func tsInitializeCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "initialize",
		Short:                 "Calls the nonpayable method initialize on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(0),
		RunE:                  tsInitialize,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	c.PreRunE = cmd.NonConstArgsChecker
	cmd.InitNonConstFlags(c)

	return c
}

func tsInitialize(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	var (
		transaction *types.Transaction
	)

	if shouldSubmit, _ := c.Flags().GetBool(cmd.SubmitFlag); shouldSubmit {
		// Do a regular submission. Take payable into account.
		transaction, err = contract.Initialize()
		if err != nil {
			return err
		}

		cmd.PrintOutput(transaction.Hash())
	} else {
		// Do a call.
		err = contract.CallInitialize(
			cmd.BlockFlagValue.Int,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput("success")

		cmd.PrintOutput(
			"the transaction was not submitted to the chain; " +
				"please add the `--submit` flag",
		)
	}

	return nil
}

func tsPauseApplicationCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "pause-application [arg_application]",
		Short:                 "Calls the nonpayable method pauseApplication on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsPauseApplication,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	c.PreRunE = cmd.NonConstArgsChecker
	cmd.InitNonConstFlags(c)

	return c
}

func tsPauseApplication(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_application, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_application, a address, from passed value %v",
			args[0],
		)
	}

	var (
		transaction *types.Transaction
	)

	if shouldSubmit, _ := c.Flags().GetBool(cmd.SubmitFlag); shouldSubmit {
		// Do a regular submission. Take payable into account.
		transaction, err = contract.PauseApplication(
			arg_application,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput(transaction.Hash())
	} else {
		// Do a call.
		err = contract.CallPauseApplication(
			arg_application,
			cmd.BlockFlagValue.Int,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput("success")

		cmd.PrintOutput(
			"the transaction was not submitted to the chain; " +
				"please add the `--submit` flag",
		)
	}

	return nil
}

func tsRequestAuthorizationDecreaseCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "request-authorization-decrease [arg_stakingProvider] [arg_application] [arg_amount]",
		Short:                 "Calls the nonpayable method requestAuthorizationDecrease on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(3),
		RunE:                  tsRequestAuthorizationDecrease,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	c.PreRunE = cmd.NonConstArgsChecker
	cmd.InitNonConstFlags(c)

	return c
}

func tsRequestAuthorizationDecrease(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_stakingProvider, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_stakingProvider, a address, from passed value %v",
			args[0],
		)
	}
	arg_application, err := chainutil.AddressFromHex(args[1])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_application, a address, from passed value %v",
			args[1],
		)
	}
	arg_amount, err := hexutil.DecodeBig(args[2])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_amount, a uint96, from passed value %v",
			args[2],
		)
	}

	var (
		transaction *types.Transaction
	)

	if shouldSubmit, _ := c.Flags().GetBool(cmd.SubmitFlag); shouldSubmit {
		// Do a regular submission. Take payable into account.
		transaction, err = contract.RequestAuthorizationDecrease(
			arg_stakingProvider,
			arg_application,
			arg_amount,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput(transaction.Hash())
	} else {
		// Do a call.
		err = contract.CallRequestAuthorizationDecrease(
			arg_stakingProvider,
			arg_application,
			arg_amount,
			cmd.BlockFlagValue.Int,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput("success")

		cmd.PrintOutput(
			"the transaction was not submitted to the chain; " +
				"please add the `--submit` flag",
		)
	}

	return nil
}

func tsSetAuthorizationCeilingCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "set-authorization-ceiling [arg_ceiling]",
		Short:                 "Calls the nonpayable method setAuthorizationCeiling on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsSetAuthorizationCeiling,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	c.PreRunE = cmd.NonConstArgsChecker
	cmd.InitNonConstFlags(c)

	return c
}

func tsSetAuthorizationCeiling(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_ceiling, err := hexutil.DecodeBig(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_ceiling, a uint256, from passed value %v",
			args[0],
		)
	}

	var (
		transaction *types.Transaction
	)

	if shouldSubmit, _ := c.Flags().GetBool(cmd.SubmitFlag); shouldSubmit {
		// Do a regular submission. Take payable into account.
		transaction, err = contract.SetAuthorizationCeiling(
			arg_ceiling,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput(transaction.Hash())
	} else {
		// Do a call.
		err = contract.CallSetAuthorizationCeiling(
			arg_ceiling,
			cmd.BlockFlagValue.Int,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput("success")

		cmd.PrintOutput(
			"the transaction was not submitted to the chain; " +
				"please add the `--submit` flag",
		)
	}

	return nil
}

func tsSetMinimumStakeAmountCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "set-minimum-stake-amount [arg_amount]",
		Short:                 "Calls the nonpayable method setMinimumStakeAmount on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsSetMinimumStakeAmount,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	c.PreRunE = cmd.NonConstArgsChecker
	cmd.InitNonConstFlags(c)

	return c
}

func tsSetMinimumStakeAmount(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_amount, err := hexutil.DecodeBig(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_amount, a uint96, from passed value %v",
			args[0],
		)
	}

	var (
		transaction *types.Transaction
	)

	if shouldSubmit, _ := c.Flags().GetBool(cmd.SubmitFlag); shouldSubmit {
		// Do a regular submission. Take payable into account.
		transaction, err = contract.SetMinimumStakeAmount(
			arg_amount,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput(transaction.Hash())
	} else {
		// Do a call.
		err = contract.CallSetMinimumStakeAmount(
			arg_amount,
			cmd.BlockFlagValue.Int,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput("success")

		cmd.PrintOutput(
			"the transaction was not submitted to the chain; " +
				"please add the `--submit` flag",
		)
	}

	return nil
}

func tsSetPanicButtonCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "set-panic-button [arg_application] [arg_panicButton]",
		Short:                 "Calls the nonpayable method setPanicButton on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(2),
		RunE:                  tsSetPanicButton,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	c.PreRunE = cmd.NonConstArgsChecker
	cmd.InitNonConstFlags(c)

	return c
}

func tsSetPanicButton(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_application, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_application, a address, from passed value %v",
			args[0],
		)
	}
	arg_panicButton, err := chainutil.AddressFromHex(args[1])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_panicButton, a address, from passed value %v",
			args[1],
		)
	}

	var (
		transaction *types.Transaction
	)

	if shouldSubmit, _ := c.Flags().GetBool(cmd.SubmitFlag); shouldSubmit {
		// Do a regular submission. Take payable into account.
		transaction, err = contract.SetPanicButton(
			arg_application,
			arg_panicButton,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput(transaction.Hash())
	} else {
		// Do a call.
		err = contract.CallSetPanicButton(
			arg_application,
			arg_panicButton,
			cmd.BlockFlagValue.Int,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput("success")

		cmd.PrintOutput(
			"the transaction was not submitted to the chain; " +
				"please add the `--submit` flag",
		)
	}

	return nil
}

func tsTransferGovernanceCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "transfer-governance [arg_newGuvnor]",
		Short:                 "Calls the nonpayable method transferGovernance on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(1),
		RunE:                  tsTransferGovernance,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	c.PreRunE = cmd.NonConstArgsChecker
	cmd.InitNonConstFlags(c)

	return c
}

func tsTransferGovernance(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_newGuvnor, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_newGuvnor, a address, from passed value %v",
			args[0],
		)
	}

	var (
		transaction *types.Transaction
	)

	if shouldSubmit, _ := c.Flags().GetBool(cmd.SubmitFlag); shouldSubmit {
		// Do a regular submission. Take payable into account.
		transaction, err = contract.TransferGovernance(
			arg_newGuvnor,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput(transaction.Hash())
	} else {
		// Do a call.
		err = contract.CallTransferGovernance(
			arg_newGuvnor,
			cmd.BlockFlagValue.Int,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput("success")

		cmd.PrintOutput(
			"the transaction was not submitted to the chain; " +
				"please add the `--submit` flag",
		)
	}

	return nil
}

func tsUnstakeTCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "unstake-t [arg_stakingProvider] [arg_amount]",
		Short:                 "Calls the nonpayable method unstakeT on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(2),
		RunE:                  tsUnstakeT,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	c.PreRunE = cmd.NonConstArgsChecker
	cmd.InitNonConstFlags(c)

	return c
}

func tsUnstakeT(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_stakingProvider, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_stakingProvider, a address, from passed value %v",
			args[0],
		)
	}
	arg_amount, err := hexutil.DecodeBig(args[1])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_amount, a uint96, from passed value %v",
			args[1],
		)
	}

	var (
		transaction *types.Transaction
	)

	if shouldSubmit, _ := c.Flags().GetBool(cmd.SubmitFlag); shouldSubmit {
		// Do a regular submission. Take payable into account.
		transaction, err = contract.UnstakeT(
			arg_stakingProvider,
			arg_amount,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput(transaction.Hash())
	} else {
		// Do a call.
		err = contract.CallUnstakeT(
			arg_stakingProvider,
			arg_amount,
			cmd.BlockFlagValue.Int,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput("success")

		cmd.PrintOutput(
			"the transaction was not submitted to the chain; " +
				"please add the `--submit` flag",
		)
	}

	return nil
}

func tsWithdrawNotificationRewardCommand() *cobra.Command {
	c := &cobra.Command{
		Use:                   "withdraw-notification-reward [arg_recipient] [arg_amount]",
		Short:                 "Calls the nonpayable method withdrawNotificationReward on the TokenStaking contract.",
		Args:                  cmd.ArgCountChecker(2),
		RunE:                  tsWithdrawNotificationReward,
		SilenceUsage:          true,
		DisableFlagsInUseLine: true,
	}

	c.PreRunE = cmd.NonConstArgsChecker
	cmd.InitNonConstFlags(c)

	return c
}

func tsWithdrawNotificationReward(c *cobra.Command, args []string) error {
	contract, err := initializeTokenStaking(c)
	if err != nil {
		return err
	}

	arg_recipient, err := chainutil.AddressFromHex(args[0])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_recipient, a address, from passed value %v",
			args[0],
		)
	}
	arg_amount, err := hexutil.DecodeBig(args[1])
	if err != nil {
		return fmt.Errorf(
			"couldn't parse parameter arg_amount, a uint96, from passed value %v",
			args[1],
		)
	}

	var (
		transaction *types.Transaction
	)

	if shouldSubmit, _ := c.Flags().GetBool(cmd.SubmitFlag); shouldSubmit {
		// Do a regular submission. Take payable into account.
		transaction, err = contract.WithdrawNotificationReward(
			arg_recipient,
			arg_amount,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput(transaction.Hash())
	} else {
		// Do a call.
		err = contract.CallWithdrawNotificationReward(
			arg_recipient,
			arg_amount,
			cmd.BlockFlagValue.Int,
		)
		if err != nil {
			return err
		}

		cmd.PrintOutput("success")

		cmd.PrintOutput(
			"the transaction was not submitted to the chain; " +
				"please add the `--submit` flag",
		)
	}

	return nil
}

/// ------------------- Initialization -------------------

func initializeTokenStaking(c *cobra.Command) (*contract.TokenStaking, error) {
	cfg := *ModuleCommand.GetConfig()

	client, err := ethclient.Dial(cfg.URL)
	if err != nil {
		return nil, fmt.Errorf("error connecting to host chain node: [%v]", err)
	}

	chainID, err := client.ChainID(context.Background())
	if err != nil {
		return nil, fmt.Errorf(
			"failed to resolve host chain id: [%v]",
			err,
		)
	}

	key, err := chainutil.DecryptKeyFile(
		cfg.Account.KeyFile,
		cfg.Account.KeyFilePassword,
	)
	if err != nil {
		return nil, fmt.Errorf(
			"failed to read KeyFile: %s: [%v]",
			cfg.Account.KeyFile,
			err,
		)
	}

	miningWaiter := chainutil.NewMiningWaiter(client, cfg)

	blockCounter, err := chainutil.NewBlockCounter(client)
	if err != nil {
		return nil, fmt.Errorf(
			"failed to create block counter: [%v]",
			err,
		)
	}

	address, err := cfg.ContractAddress("TokenStaking")
	if err != nil {
		return nil, fmt.Errorf(
			"failed to get %s address: [%w]",
			"TokenStaking",
			err,
		)
	}

	return contract.NewTokenStaking(
		address,
		chainID,
		key,
		client,
		chainutil.NewNonceManager(client, key.Address),
		miningWaiter,
		blockCounter,
		&sync.Mutex{},
	)
}
