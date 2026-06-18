// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {StakeVault} from "../../src/StakeVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @notice Thin wrapper the invariant runner is allowed to drive. It owns a set
///         of actors, bounds inputs so calls usually land, and keeps ghost
///         accounting the invariants compare against on-chain state.
contract StakeVaultHandler is Test {
    StakeVault public vault;
    MockERC20 public staking;
    MockERC20 public reward;

    address[] public actors;
    address internal currentActor;

    // Ghost variables: independent off-chain accounting.
    uint256 public ghost_totalStaked;
    uint256 public ghost_rewardsClaimed;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }

    constructor(StakeVault _vault, MockERC20 _staking, MockERC20 _reward) {
        vault = _vault;
        staking = _staking;
        reward = _reward;
        for (uint256 i; i < 3; i++) {
            address a = makeAddr(string(abi.encode("actor", i)));
            actors.push(a);
            staking.mint(a, 1_000_000e18);
            vm.prank(a);
            staking.approve(address(vault), type(uint256).max);
        }
    }

    function actorsLength() external view returns (uint256) {
        return actors.length;
    }

    function stake(uint256 seed, uint256 amount) external useActor(seed) {
        uint256 bal = staking.balanceOf(currentActor);
        if (bal == 0) return;
        amount = bound(amount, 1, bal);
        vault.stake(amount);
        ghost_totalStaked += amount;
    }

    function withdraw(uint256 seed, uint256 amount) external useActor(seed) {
        uint256 staked = vault.balanceOf(currentActor);
        if (staked == 0) return;
        amount = bound(amount, 1, staked);
        vault.withdraw(amount);
        ghost_totalStaked -= amount;
    }

    function claim(uint256 seed) external useActor(seed) {
        uint256 before = reward.balanceOf(currentActor);
        vault.claim();
        ghost_rewardsClaimed += reward.balanceOf(currentActor) - before;
    }

    function warp(uint256 secs) external {
        vm.warp(block.timestamp + bound(secs, 1, 7 days));
    }
}
