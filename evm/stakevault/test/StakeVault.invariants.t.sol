// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {StakeVault} from "../src/StakeVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {StakeVaultHandler} from "./handlers/StakeVaultHandler.sol";

/// @notice Stateful invariant suite. The runner drives random sequences of the
///         handler's actions and checks core protocol properties after each.
contract StakeVaultInvariants is Test {
    StakeVault internal vault;
    MockERC20 internal staking;
    MockERC20 internal reward;
    StakeVaultHandler internal handler;

    uint256 internal constant FUNDED = 1_000_000e18;

    function setUp() public {
        staking = new MockERC20("Stake", "STK");
        reward = new MockERC20("Reward", "RWD");
        vault = new StakeVault(address(staking), address(reward), address(this));

        // Set a rate, then fund the reward pool.
        vault.setRewardRate(1e18);
        reward.mint(address(this), FUNDED);
        reward.approve(address(vault), FUNDED);
        vault.fundRewards(FUNDED);

        handler = new StakeVaultHandler(vault, staking, reward);
        targetContract(address(handler)); // fuzz only the handler
    }

    /// @notice Conservation of stake: the sum of recorded balances equals the
    ///         public total.
    function invariant_TotalStakedMatchesGhost() public view {
        assertEq(vault.totalStaked(), handler.ghost_totalStaked());
    }

    /// @notice The vault always holds at least the staking tokens owed to
    ///         stakers (standard, non-fee tokens).
    function invariant_VaultSolventForStakers() public view {
        assertGe(staking.balanceOf(address(vault)), vault.totalStaked());
    }

    /// @notice Solvency: the vault never pays out more reward tokens than were
    ///         funded into it.
    function invariant_NeverOverpaysRewards() public view {
        assertLe(handler.ghost_rewardsClaimed(), FUNDED);
    }
}
