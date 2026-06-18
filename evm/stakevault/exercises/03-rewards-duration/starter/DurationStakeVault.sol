// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title DurationStakeVault (STARTER)
/// @notice Exercise 03 — swap the free-form rate/funding levers for the
///         Synthetix finite-period model. The reward-accumulator core below is
///         the verified Chapter 13 code; implement `setRewardsDuration` and
///         `notifyRewardAmount` where marked `// TODO`.
/// @dev Acceptance criteria:
///      - `setRewardsDuration` only succeeds when no period is active
///        (`block.timestamp >= periodFinish`) and the duration is non-zero,
///      - `notifyRewardAmount(reward)` pulls `reward` tokens in, sets
///        `rewardRate = (reward + leftover) / rewardsDuration`, pins
///        `periodFinish = now + rewardsDuration`, and reverts `RewardTooHigh`
///        if the rate is not fully backed by the contract's token balance,
///      - emissions still cap at `periodFinish` (inherited from the core math).
contract DurationStakeVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 private constant PRECISION = 1e18;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public rewardRate;
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;

    /// @notice Length of every emission period, in seconds.
    uint256 public rewardsDuration;

    uint256 public totalStaked;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    error ZeroAmount();
    error InsufficientBalance();
    error ZeroDuration();
    error RewardPeriodActive();
    error RewardTooHigh();
    error NotImplemented();

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event RewardAdded(uint256 reward, uint256 periodFinish);
    event RewardsDurationUpdated(uint256 rewardsDuration);

    constructor(address _stakingToken, address _rewardToken, address _owner, uint256 _rewardsDuration) Ownable(_owner) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardsDuration = _rewardsDuration;
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
        stakingToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public nonReentrant updateReward(msg.sender) {
        if (amount == 0) revert ZeroAmount();
        if (balanceOf[msg.sender] < amount) revert InsufficientBalance();
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

    /// @notice Set the emission window length. Only allowed between periods.
    function setRewardsDuration(uint256 _rewardsDuration) external onlyOwner {
        // TODO: require no active period, require non-zero duration, then set
        //       `rewardsDuration` and emit `RewardsDurationUpdated`.
        revert NotImplemented();
    }

    /// @notice Pull `reward` tokens in and (re)start a `rewardsDuration` period.
    function notifyRewardAmount(uint256 reward) external onlyOwner updateReward(address(0)) {
        // TODO: implement the Synthetix-style notify:
        //       1. transferFrom the reward tokens in,
        //       2. compute rewardRate from reward (+ leftover if mid-period),
        //       3. bound it by balance / rewardsDuration (else RewardTooHigh),
        //       4. set lastUpdateTime and periodFinish, emit RewardAdded.
        revert NotImplemented();
    }
}
