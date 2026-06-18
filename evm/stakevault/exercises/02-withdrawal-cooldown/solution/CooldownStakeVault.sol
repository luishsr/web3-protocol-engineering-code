// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title CooldownStakeVault (SOLUTION)
/// @notice Exercise 02 — a per-user withdrawal cooldown layered onto the
///         canonical StakeVault. Each `stake` (re)arms a timer; `withdraw` (and
///         therefore `exit`) is gated until it elapses. `claim` is deliberately
///         *not* gated: staying liquid on rewards while the principal is locked
///         is the whole point of a cooldown.
/// @dev A near-verbatim copy of the Chapter 13 vault; the only additions are
///      `cooldownPeriod`, `unlockAt`, the time gate in `withdraw`, and the
///      `setCooldownPeriod` admin lever.
contract CooldownStakeVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant PRECISION = 1e18;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public rewardRate;
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    uint256 public totalStaked;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    // --- Cooldown state ------------------------------------------------------

    /// @notice Seconds a fresh (or topped-up) stake must wait before withdrawal.
    uint256 public cooldownPeriod;
    /// @notice Per-user timestamp at which withdrawals unlock.
    mapping(address => uint256) public unlockAt;

    error ZeroAmount();
    error InsufficientBalance();
    error RewardRateNotSet();
    error WithdrawalLocked(uint256 unlockAt);

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRate, uint256 periodFinish);
    event RewardsFunded(address indexed funder, uint256 amount, uint256 periodFinish);
    event CooldownUpdated(uint256 cooldownPeriod);

    constructor(address _stakingToken, address _rewardToken, address _owner, uint256 _cooldownPeriod) Ownable(_owner) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        cooldownPeriod = _cooldownPeriod;
    }

    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        uint256 elapsed = lastTimeRewardApplicable() - lastUpdateTime;
        return rewardPerTokenStored + (elapsed * rewardRate * PRECISION) / totalStaked;
    }

    function earned(address account) public view returns (uint256) {
        uint256 delta = rewardPerToken() - userRewardPerTokenPaid[account];
        return (balanceOf[account] * delta) / PRECISION + rewards[account];
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTime = lastTimeRewardApplicable();
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function stake(uint256 amount) external nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        totalStaked += amount;
        balanceOf[msg.sender] += amount;
        // (Re)arm the cooldown: every fresh deposit resets the timer so a user
        // cannot dodge the lock by topping up an already-unlocked position.
        unlockAt[msg.sender] = block.timestamp + cooldownPeriod;
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();
        // The time gate. Rewards are unaffected; only principal is locked.
        if (block.timestamp < unlockAt[msg.sender]) {
            revert WithdrawalLocked(unlockAt[msg.sender]);
        }
        totalStaked -= amount;
        balanceOf[msg.sender] -= amount;
        stakingToken.safeTransfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function claim() public nonReentrant updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function exit() external {
        uint256 staked = balanceOf[msg.sender];
        if (staked > 0) {
            withdraw(staked);
        }
        claim();
    }

    function fundRewards(uint256 amount) external nonReentrant updateReward(address(0)) {
        if (amount == 0) revert ZeroAmount();
        if (rewardRate == 0) revert RewardRateNotSet();
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 remaining = periodFinish > block.timestamp ? periodFinish - block.timestamp : 0;
        uint256 leftover = remaining * rewardRate;
        periodFinish = block.timestamp + (leftover + amount) / rewardRate;
        emit RewardsFunded(msg.sender, amount, periodFinish);
    }

    function setRewardRate(uint256 newRate) external onlyOwner updateReward(address(0)) {
        uint256 remaining = periodFinish > block.timestamp ? periodFinish - block.timestamp : 0;
        uint256 leftover = remaining * rewardRate;
        rewardRate = newRate;
        periodFinish = newRate > 0 ? block.timestamp + leftover / newRate : block.timestamp;
        emit RewardRateUpdated(newRate, periodFinish);
    }

    /// @notice Owner lever for the cooldown length. Existing locks already
    ///         written into `unlockAt` are unaffected; only future stakes use
    ///         the new value.
    function setCooldownPeriod(uint256 _cooldownPeriod) external onlyOwner {
        cooldownPeriod = _cooldownPeriod;
        emit CooldownUpdated(_cooldownPeriod);
    }
}
