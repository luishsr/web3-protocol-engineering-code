// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {DurationStakeVault} from "./DurationStakeVault.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

contract DurationStakeVaultTest is Test {
    DurationStakeVault internal vault;
    MockERC20 internal staking;
    MockERC20 internal reward;

    address internal owner = address(this);
    address internal alice = makeAddr("alice");
    uint256 internal constant DURATION = 1_000; // seconds
    uint256 internal constant POT = 1_000e18; // -> rate 1e18/s over DURATION

    function setUp() public {
        staking = new MockERC20("Stake", "STK");
        reward = new MockERC20("Reward", "RWD");
        vault = new DurationStakeVault(address(staking), address(reward), owner, DURATION);

        staking.mint(alice, 1_000e18);
        reward.mint(owner, 1_000_000e18);

        vm.prank(alice);
        staking.approve(address(vault), type(uint256).max);
        reward.approve(address(vault), type(uint256).max);

        vm.warp(1_000_000);
    }

    function _notify(uint256 amount) internal {
        vault.notifyRewardAmount(amount);
    }

    function test_NotifyDerivesRateAndFinish() public {
        _notify(POT);
        assertEq(vault.rewardRate(), POT / DURATION); // 1e18 per second
        assertEq(vault.periodFinish(), block.timestamp + DURATION);
    }

    function test_SoleStakerEarnsOverDuration() public {
        _notify(POT);
        vm.prank(alice);
        vault.stake(100e18);

        vm.warp(block.timestamp + 100);
        assertEq(vault.earned(alice), 100e18); // 100s * 1e18/s
    }

    function test_EmissionsCapAtPeriodFinish() public {
        _notify(POT);
        vm.prank(alice);
        vault.stake(100e18);

        vm.warp(block.timestamp + 10 * DURATION); // long past the window
        assertEq(vault.earned(alice), POT); // capped at the funded pot
    }

    function test_RevertWhen_SetDurationDuringActivePeriod() public {
        _notify(POT);
        vm.expectRevert(DurationStakeVault.RewardPeriodActive.selector);
        vault.setRewardsDuration(2_000);
    }

    function test_SetDurationAfterPeriodEnds() public {
        _notify(POT);
        vm.warp(block.timestamp + DURATION); // period elapsed
        vault.setRewardsDuration(2_000);
        assertEq(vault.rewardsDuration(), 2_000);
    }

    function test_TopUpRollsLeftoverIntoRate() public {
        _notify(POT); // rate 1e18/s, periodFinish = T0 + 1000

        // Halfway through: 500s remain, leftover = 500 * 1e18 = 500e18.
        vm.warp(block.timestamp + 500);

        _notify(POT); // (1000e18 + 500e18) / 1000 = 1.5e18/s
        assertEq(vault.rewardRate(), 1.5e18);
        assertEq(vault.periodFinish(), block.timestamp + DURATION);
    }

    function test_RevertWhen_NotifyBeforeDurationSet() public {
        // Fresh vault with zero duration.
        DurationStakeVault fresh = new DurationStakeVault(address(staking), address(reward), owner, 0);
        reward.approve(address(fresh), type(uint256).max);
        vm.expectRevert(DurationStakeVault.ZeroDuration.selector);
        fresh.notifyRewardAmount(POT);
    }

    function test_SolvencyInvariantHoldsAfterNotify() public {
        // The whole schedule must be backed by tokens actually held: the funded
        // pot covers every token the period can emit.
        _notify(POT);
        assertLe(vault.rewardRate() * vault.rewardsDuration(), reward.balanceOf(address(vault)));

        // Still true after a mid-period top-up rolls leftover into the rate.
        vm.warp(block.timestamp + 500);
        _notify(POT);
        assertLe(vault.rewardRate() * vault.rewardsDuration(), reward.balanceOf(address(vault)));
    }

    function test_RevertWhen_NotifyNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.notifyRewardAmount(POT);
    }
}
