// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {StakeVault} from "../src/StakeVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {HookToken, IRewardHook} from "./mocks/HookToken.sol";

contract StakeVaultTest is Test {
    StakeVault internal vault;
    MockERC20 internal staking;
    MockERC20 internal reward;

    address internal owner = address(this);
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    uint256 internal constant RATE = 1e18; // 1 reward token per second

    function setUp() public {
        staking = new MockERC20("Stake", "STK");
        reward = new MockERC20("Reward", "RWD");
        vault = new StakeVault(address(staking), address(reward), owner);

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

    // --- Happy paths ---------------------------------------------------------

    function test_StakeUpdatesBalances() public {
        vm.prank(alice);
        vault.stake(100e18);
        assertEq(vault.balanceOf(alice), 100e18);
        assertEq(vault.totalStaked(), 100e18);
        assertEq(staking.balanceOf(address(vault)), 100e18);
    }

    function test_WithdrawReturnsTokens() public {
        vm.startPrank(alice);
        vault.stake(100e18);
        vault.withdraw(40e18);
        vm.stopPrank();
        assertEq(vault.balanceOf(alice), 60e18);
        assertEq(staking.balanceOf(alice), 940e18);
    }

    function test_StakeEmitsStaked() public {
        vm.expectEmit(true, false, false, true, address(vault));
        emit StakeVault.Staked(alice, 100e18);
        vm.prank(alice);
        vault.stake(100e18);
    }

    // --- Reward math over time ----------------------------------------------

    function test_SoleStakerEarnsFullRate() public {
        vm.prank(alice);
        vault.stake(100e18);
        vm.warp(block.timestamp + 100);
        assertEq(vault.earned(alice), 100 * RATE); // 100e18, regardless of stake size
    }

    function test_RewardsSplitProRata() public {
        vm.prank(alice);
        vault.stake(100e18);
        vm.prank(bob);
        vault.stake(300e18);

        vm.warp(block.timestamp + 100);

        assertEq(vault.earned(alice), 25e18); // 1/4 of 100 tokens
        assertEq(vault.earned(bob), 75e18); // 3/4 of 100 tokens
    }

    function test_ClaimTransfersRewards() public {
        vm.prank(alice);
        vault.stake(100e18);
        vm.warp(block.timestamp + 100);

        vm.prank(alice);
        vault.claim();

        assertEq(reward.balanceOf(alice), 100e18);
        assertEq(vault.earned(alice), 0);
    }

    function test_Exit() public {
        vm.prank(alice);
        vault.stake(100e18);
        vm.warp(block.timestamp + 50);

        vm.prank(alice);
        vault.exit();

        assertEq(vault.balanceOf(alice), 0);
        assertEq(staking.balanceOf(alice), 1_000e18); // stake fully returned
        assertEq(reward.balanceOf(alice), 50e18); // 50 seconds of rewards
    }

    // --- Solvency: emissions cap at periodFinish -----------------------------

    function test_EmissionsStopAtPeriodFinish() public {
        vm.prank(alice);
        vault.stake(100e18);
        // Funded 10_000 seconds of runway; warp well past it.
        vm.warp(block.timestamp + 1_000_000);
        // Earned is capped at the funded amount, not the elapsed seconds.
        assertEq(vault.earned(alice), 10_000e18);
    }

    function test_SetRewardRatePreservesLeftover() public {
        // 10_000e18 funded at RATE=1e18 -> 10_000s of runway remaining.
        // Halving the rate should double the runway, same total tokens.
        vault.setRewardRate(RATE / 2);
        assertEq(vault.periodFinish(), block.timestamp + 20_000);
    }

    // --- Reverts: access control and bad input -------------------------------

    function test_RevertWhen_StakeZero() public {
        vm.prank(alice);
        vm.expectRevert(StakeVault.ZeroAmount.selector);
        vault.stake(0);
    }

    function test_RevertWhen_WithdrawTooMuch() public {
        vm.startPrank(alice);
        vault.stake(100e18);
        vm.expectRevert(StakeVault.InsufficientBalance.selector);
        vault.withdraw(101e18);
        vm.stopPrank();
    }

    function test_RevertWhen_SetRateNotOwner() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        vault.setRewardRate(5e18);
    }

    function test_RevertWhen_FundWithoutRate() public {
        // Fresh vault with no rate set.
        StakeVault fresh = new StakeVault(address(staking), address(reward), owner);
        reward.approve(address(fresh), type(uint256).max);
        vm.expectRevert(StakeVault.RewardRateNotSet.selector);
        fresh.fundRewards(1e18);
    }

    // --- Fuzzing -------------------------------------------------------------

    function testFuzz_StakeThenWithdraw(uint96 amount) public {
        vm.assume(amount > 0 && amount <= 1_000e18);
        vm.startPrank(alice);
        vault.stake(amount);
        assertEq(vault.balanceOf(alice), amount);
        vault.withdraw(amount);
        vm.stopPrank();
        assertEq(vault.balanceOf(alice), 0);
        assertEq(staking.balanceOf(alice), 1_000e18);
    }
}

/// @notice Attacker contract that stakes, then tries to re-enter the vault
///         through the reward token's transfer hook during `claim`.
contract ReentrancyAttacker is IRewardHook {
    StakeVault public vault;
    MockERC20 public staking;
    bool public attacking;

    constructor(StakeVault _vault, MockERC20 _staking) {
        vault = _vault;
        staking = _staking;
    }

    function stakeIn(uint256 amount) external {
        staking.approve(address(vault), type(uint256).max);
        vault.stake(amount);
    }

    function go() external {
        attacking = true;
        vault.claim();
    }

    function onReward() external override {
        if (attacking) {
            attacking = false;
            vault.withdraw(1); // cross-function re-entry attempt
        }
    }
}

/// @notice Dedicated harness: the reward token is a callback (HookToken) so the
///         attacker can attempt re-entry mid-`claim`.
contract StakeVaultReentrancyTest is Test {
    StakeVault internal vault;
    MockERC20 internal staking;
    HookToken internal reward;
    ReentrancyAttacker internal attacker;

    address internal owner = address(this);

    function setUp() public {
        staking = new MockERC20("Stake", "STK");
        reward = new HookToken();
        vault = new StakeVault(address(staking), address(reward), owner);
        attacker = new ReentrancyAttacker(vault, staking);

        // Fund the attacker with staking tokens and let it stake.
        staking.mint(address(attacker), 100e18);
        attacker.stakeIn(100e18);

        // Configure and fund the reward stream, then accrue some rewards.
        vault.setRewardRate(1e18);
        reward.mint(owner, 1_000e18);
        reward.approve(address(vault), type(uint256).max);
        vault.fundRewards(1_000e18);
        vm.warp(block.timestamp + 100);
    }

    function test_RevertWhen_ReentrantClaim() public {
        // claim holds the nonReentrant lock; the nested withdraw from the
        // reward-token hook hits the guard and unwinds the whole transaction.
        vm.expectRevert(); // ReentrancyGuardReentrantCall (bubbled through SafeERC20)
        attacker.go();
    }

    function test_AttackerCannotDrainVault() public {
        // Sanity: the attack reverts, so nothing leaves the vault.
        uint256 vaultStakeBefore = staking.balanceOf(address(vault));
        try attacker.go() {
            // unreachable: the call must revert
            assertTrue(false, "attack should revert");
        } catch {
            assertEq(staking.balanceOf(address(vault)), vaultStakeBefore);
        }
    }
}
