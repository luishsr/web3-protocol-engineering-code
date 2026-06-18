// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Hook called on a recipient after it receives tokens.
interface IRewardHook {
    function onReward() external;
}

/// @notice A malicious reward token that calls back the recipient after every
///         `transfer`, mimicking ERC-777-style transfer hooks. Used to mount a
///         live reentrancy attempt against StakeVault.claim (see Chapter 13).
contract HookToken is ERC20 {
    constructor() ERC20("Hook", "HOOK") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        bool ok = super.transfer(to, amount);
        if (to.code.length > 0) {
            IRewardHook(to).onReward(); // reentrancy surface
        }
        return ok;
    }
}
