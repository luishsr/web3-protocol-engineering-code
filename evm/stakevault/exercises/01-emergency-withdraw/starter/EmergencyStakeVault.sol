// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StakeVault} from "@base/StakeVault.sol";

/// @title EmergencyStakeVault (STARTER)
/// @notice Exercise 01 — add an `emergencyWithdraw()` escape hatch.
/// @dev Extends the canonical, verified `StakeVault` from Chapter 13. The base
///      contract's accounting state (`balanceOf`, `totalStaked`, `rewards`,
///      ...) is inherited and writable from this subclass.
contract EmergencyStakeVault is StakeVault {
    using SafeERC20 for IERC20;

    error NotImplemented();

    /// @notice Emitted when a user pulls their stake but forfeits rewards.
    /// @param user The staker exiting.
    /// @param amount Staking tokens returned.
    /// @param forfeited Reward tokens left behind (donated back to the pool).
    event EmergencyWithdrawn(address indexed user, uint256 amount, uint256 forfeited);

    constructor(address _stakingToken, address _rewardToken, address _owner)
        StakeVault(_stakingToken, _rewardToken, _owner)
    {}

    /// @notice Return the caller's entire stake immediately, forfeiting any
    ///         accrued (but unclaimed) rewards.
    /// @dev Acceptance criteria:
    ///      - returns the full staked balance to the caller,
    ///      - sets the caller's accrued rewards to zero (forfeited),
    ///      - keeps `totalStaked` and `balanceOf` consistent,
    ///      - never transfers any reward tokens out,
    ///      - emits `EmergencyWithdrawn`.
    ///      Hint: the inherited `updateReward(msg.sender)` modifier settles the
    ///      caller's earnings into `rewards[msg.sender]` *before* the body runs;
    ///      forfeiting is then just zeroing that slot. Follow CEI and reuse the
    ///      inherited `nonReentrant` guard.
    function emergencyWithdraw() external {
        // TODO: implement the emergency exit described above.
        revert NotImplemented();
    }
}
