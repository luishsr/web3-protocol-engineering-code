// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {StakeVault} from "../src/StakeVault.sol";

/// @notice Minimal deploy script for StakeVault.
/// @dev Configure via environment variables:
///   STAKING_TOKEN  - address of the ERC-20 users stake
///   REWARD_TOKEN   - address of the ERC-20 paid as rewards
///   VAULT_OWNER    - initial owner (use a multisig/timelock in production)
///
/// Run, e.g.:
///   forge script script/Deploy.s.sol:Deploy \
///     --rpc-url <url> --broadcast --private-key <key>
contract Deploy is Script {
    function run() external returns (StakeVault vault) {
        address stakingToken = vm.envAddress("STAKING_TOKEN");
        address rewardToken = vm.envAddress("REWARD_TOKEN");
        address owner = vm.envAddress("VAULT_OWNER");

        vm.startBroadcast();
        vault = new StakeVault(stakingToken, rewardToken, owner);
        vm.stopBroadcast();

        console2.log("StakeVault deployed at:", address(vault));
        return vault;
    }
}
