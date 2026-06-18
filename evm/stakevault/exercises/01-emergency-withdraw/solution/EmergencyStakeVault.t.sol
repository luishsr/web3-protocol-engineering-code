// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StakeVault} from "@base/StakeVault.sol";
import {EmergencyStakeVault} from "./EmergencyStakeVault.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

contract EmergencyWithdrawTest is Test {
    EmergencyStakeVault internal vault;
    MockERC20 internal staking;
    MockERC20 internal reward;

    address internal owner = address(this);
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    uint256 internal constant RATE = 1e18; // 1 reward token per second

    function setUp() public {
        staking = new MockERC20("Stake", "STK");
        reward = new MockERC20("Reward", "RWD");
        vault = new EmergencyStakeVault(address(staking), address(reward), owner);

        staking.mint(alice, 1_000e18);
        staking.mint(bob, 1_000e18);
        reward.mint(owner, 1_000_000e18);

        vm.prank(alice);
        staking.approve(address(vault), type(uint256).max);
        vm.prank(bob);
        staking.approve(address(vault), type(uint256).max);

        vault.setRewardRate(RATE);
        reward.approve(address(vault), type(uint256).max);
        vault.fundRewards(10_000e18);
    }

    function test_EmergencyWithdrawReturnsStakeForfeitsRewards() public {
        vm.prank(alice);
        vault.stake(100e18);
        vm.warp(block.timestamp + 100);

        // Rewards have accrued and are real.
        assertEq(vault.earned(alice), 100e18);
        uint256 vaultRewardBefore = reward.balanceOf(address(vault));

        vm.expectEmit(true, false, false, true, address(vault));
        emit EmergencyStakeVault.EmergencyWithdrawn(alice, 100e18, 100e18);
        vm.prank(alice);
        vault.emergencyWithdraw();

        // Stake fully returned.
        assertEq(vault.balanceOf(alice), 0);
        assertEq(staking.balanceOf(alice), 1_000e18);

        // Rewards forfeited: nothing transferred, nothing left owed.
        assertEq(reward.balanceOf(alice), 0);
        assertEq(vault.earned(alice), 0);

        // Forfeited reward tokens remain in the vault (unallocated).
        assertEq(reward.balanceOf(address(vault)), vaultRewardBefore);

        // Accounting stays consistent.
        assertEq(vault.totalStaked(), 0);
    }

    function test_AccountingStaysConsistentForOtherStakers() public {
        vm.prank(alice);
        vault.stake(100e18);
        vm.prank(bob);
        vault.stake(100e18);

        vm.warp(block.timestamp + 100);
        assertEq(vault.earned(alice), 50e18);
        assertEq(vault.earned(bob), 50e18);

        vm.prank(alice);
        vault.emergencyWithdraw();

        // Conservation of stake: only bob's stake remains.
        assertEq(vault.totalStaked(), 100e18);
        assertEq(vault.balanceOf(bob), 100e18);

        // Bob keeps his accrued rewards and now earns at the full rate.
        vm.warp(block.timestamp + 100);
        assertEq(vault.earned(bob), 150e18); // 50 banked + 100 as sole staker

        vm.prank(bob);
        vault.claim();
        assertEq(reward.balanceOf(bob), 150e18);
    }

    function test_RevertWhen_EmergencyWithdrawWithNoStake() public {
        vm.prank(alice);
        vm.expectRevert(StakeVault.ZeroAmount.selector);
        vault.emergencyWithdraw();
    }

    function testFuzz_EmergencyWithdrawNeverPaysRewards(uint96 amount, uint32 elapsed) public {
        vm.assume(amount > 0 && amount <= 1_000e18);
        vm.prank(alice);
        vault.stake(amount);
        vm.warp(block.timestamp + elapsed);

        vm.prank(alice);
        vault.emergencyWithdraw();

        assertEq(reward.balanceOf(alice), 0); // rewards always forfeited
        assertEq(staking.balanceOf(alice), 1_000e18); // stake always returned
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.totalStaked(), 0);
    }
}
