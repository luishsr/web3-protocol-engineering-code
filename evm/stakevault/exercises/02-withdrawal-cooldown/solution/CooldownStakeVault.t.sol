// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CooldownStakeVault} from "./CooldownStakeVault.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";

contract CooldownStakeVaultTest is Test {
    CooldownStakeVault internal vault;
    MockERC20 internal staking;
    MockERC20 internal reward;

    address internal owner = address(this);
    address internal alice = makeAddr("alice");
    uint256 internal constant RATE = 1e18;
    uint256 internal constant COOLDOWN = 7 days;

    function setUp() public {
        staking = new MockERC20("Stake", "STK");
        reward = new MockERC20("Reward", "RWD");
        vault = new CooldownStakeVault(address(staking), address(reward), owner, COOLDOWN);

        staking.mint(alice, 1_000e18);
        reward.mint(owner, 100_000_000e18);

        vm.prank(alice);
        staking.approve(address(vault), type(uint256).max);

        // Start at a non-zero timestamp so `unlockAt` math is unambiguous, then
        // fund a runway long enough to cover the whole test window.
        vm.warp(1_000_000);
        vault.setRewardRate(RATE);
        reward.approve(address(vault), type(uint256).max);
        vault.fundRewards(10_000_000e18);
    }

    function test_StakeArmsCooldown() public {
        vm.prank(alice);
        vault.stake(100e18);
        assertEq(vault.unlockAt(alice), block.timestamp + COOLDOWN);
    }

    function test_RevertWhen_WithdrawDuringCooldown() public {
        vm.prank(alice);
        vault.stake(100e18);

        uint256 expectedUnlock = block.timestamp + COOLDOWN;
        vm.warp(block.timestamp + COOLDOWN - 1); // one second short

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CooldownStakeVault.WithdrawalLocked.selector, expectedUnlock));
        vault.withdraw(100e18);
    }

    function test_WithdrawSucceedsAtUnlock() public {
        vm.prank(alice);
        vault.stake(100e18);

        vm.warp(block.timestamp + COOLDOWN); // exactly at the boundary

        vm.prank(alice);
        vault.withdraw(100e18);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(staking.balanceOf(alice), 1_000e18);
    }

    function test_RestakeResetsCooldown() public {
        vm.prank(alice);
        vault.stake(100e18);

        // Wait almost the whole window, then top up.
        vm.warp(block.timestamp + COOLDOWN - 1);
        vm.prank(alice);
        vault.stake(50e18);

        uint256 newUnlock = block.timestamp + COOLDOWN;
        assertEq(vault.unlockAt(alice), newUnlock);

        // The original near-expiry timer no longer helps: still locked.
        vm.warp(newUnlock - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(CooldownStakeVault.WithdrawalLocked.selector, newUnlock));
        vault.withdraw(10e18);

        // ...but it unlocks once the new window elapses.
        vm.warp(newUnlock);
        vm.prank(alice);
        vault.withdraw(150e18);
        assertEq(vault.balanceOf(alice), 0);
    }

    function test_ClaimIsNotGatedByCooldown() public {
        vm.prank(alice);
        vault.stake(100e18);

        // Mid-cooldown: principal is locked but rewards have accrued.
        vm.warp(block.timestamp + 100);
        assertEq(vault.earned(alice), 100e18);

        vm.prank(alice);
        vault.claim(); // must NOT revert
        assertEq(reward.balanceOf(alice), 100e18);

        // Withdrawing principal is still locked.
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(100e18);
    }

    function test_SetCooldownPeriod() public {
        vault.setCooldownPeriod(1 days);
        assertEq(vault.cooldownPeriod(), 1 days);

        vm.prank(alice);
        vault.stake(100e18);
        assertEq(vault.unlockAt(alice), block.timestamp + 1 days);
    }

    function test_RevertWhen_SetCooldownNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.setCooldownPeriod(1 days);
    }
}
