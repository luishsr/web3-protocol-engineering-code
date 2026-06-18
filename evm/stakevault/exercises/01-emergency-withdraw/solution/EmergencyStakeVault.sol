// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StakeVault} from "@base/StakeVault.sol";

/// @title EmergencyStakeVault (SOLUTION)
/// @notice Exercise 01 — add an `emergencyWithdraw()` escape hatch.
/// @dev Extends the canonical, verified `StakeVault` from Chapter 13.
contract EmergencyStakeVault is StakeVault {
    using SafeERC20 for IERC20;

    /// @notice Emitted when a user pulls their stake but forfeits rewards.
    event EmergencyWithdrawn(address indexed user, uint256 amount, uint256 forfeited);

    constructor(address _stakingToken, address _rewardToken, address _owner)
        StakeVault(_stakingToken, _rewardToken, _owner)
    {}

    /// @notice Return the caller's entire stake immediately, forfeiting any
    ///         accrued (but unclaimed) rewards.
    /// @dev `updateReward` first banks the caller's earnings into
    ///      `rewards[msg.sender]`; we then zero that slot so the rewards stay in
    ///      the vault as unallocated tokens (recoverable by the owner sweep in
    ///      the Chapter 13 exercise). Checks-Effects-Interactions: all state is
    ///      mutated before the single external token transfer, and the inherited
    ///      `nonReentrant` guard backstops the interaction.
    function emergencyWithdraw() external nonReentrant updateReward(msg.sender) {
        uint256 amount = balanceOf[msg.sender];
        if (amount == 0) revert ZeroAmount();

        uint256 forfeited = rewards[msg.sender];

        // Effects: drop the stake and burn the reward claim.
        rewards[msg.sender] = 0;
        totalStaked -= amount;
        balanceOf[msg.sender] = 0;

        // Interaction: only the staking token moves; no reward tokens leave.
        stakingToken.safeTransfer(msg.sender, amount);

        emit EmergencyWithdrawn(msg.sender, amount, forfeited);
    }
}
