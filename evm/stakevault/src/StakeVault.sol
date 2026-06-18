// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title StakeVault
/// @notice Single-asset staking vault that streams a separate reward token to
///         stakers pro-rata using the reward-accumulator (Synthetix/MasterChef)
///         pattern. See Chapter 13 of "Web3 Protocol Engineering".
/// @dev Assumes standard, non-fee-on-transfer ERC-20s for both tokens. The
///      reward and staking tokens are trusted at deploy time.
contract StakeVault is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Fixed-point scale for the reward accumulator; keeps the fractional
    ///      part of "reward per token" alive through integer truncation.
    uint256 private constant PRECISION = 1e18;

    IERC20 public immutable stakingToken;
    IERC20 public immutable rewardToken;

    uint256 public rewardRate; // reward tokens emitted per second
    uint256 public periodFinish; // timestamp when current funding runs dry
    uint256 public lastUpdateTime; // last time the accumulator was settled
    uint256 public rewardPerTokenStored; // the global accumulator, scaled by 1e18

    uint256 public totalStaked;
    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards; // settled, unclaimed rewards

    error ZeroAmount();
    error InsufficientBalance();
    error RewardRateNotSet();

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);
    event RewardRateUpdated(uint256 newRate, uint256 periodFinish);
    event RewardsFunded(address indexed funder, uint256 amount, uint256 periodFinish);

    constructor(address _stakingToken, address _rewardToken, address _owner) Ownable(_owner) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
    }

    /// @notice The accrual clock, capped at `periodFinish` so emissions never
    ///         exceed funded tokens.
    function lastTimeRewardApplicable() public view returns (uint256) {
        return block.timestamp < periodFinish ? block.timestamp : periodFinish;
    }

    /// @notice The live reward accumulator: the stored value plus the
    ///         contribution of time elapsed since the last settlement.
    function rewardPerToken() public view returns (uint256) {
        if (totalStaked == 0) {
            return rewardPerTokenStored;
        }
        uint256 elapsed = lastTimeRewardApplicable() - lastUpdateTime;
        return rewardPerTokenStored + (elapsed * rewardRate * PRECISION) / totalStaked;
    }

    /// @notice Rewards earned by `account` but not yet claimed.
    function earned(address account) public view returns (uint256) {
        uint256 delta = rewardPerToken() - userRewardPerTokenPaid[account];
        return (balanceOf[account] * delta) / PRECISION + rewards[account];
    }

    /// @dev Settle the global accumulator, then (for a real user) bank their
    ///      earnings before their balance changes. Pass address(0) for admin
    ///      actions that touch global parameters but no specific user.
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

    /// @notice Withdraw the full stake and claim rewards in one transaction.
    /// @dev Intentionally NOT `nonReentrant`: it only orchestrates the already
    ///      guarded `withdraw` and `claim`. Guarding it too would make those
    ///      inner calls revert against the lock this wrapper would hold.
    function exit() external {
        uint256 staked = balanceOf[msg.sender];
        if (staked > 0) {
            withdraw(staked);
        }
        claim();
    }

    /// @notice Pull reward tokens in and extend `periodFinish` to cover them at
    ///         the current rate. Requires a non-zero rate to attach a schedule.
    function fundRewards(uint256 amount) external nonReentrant updateReward(address(0)) {
        if (amount == 0) revert ZeroAmount();
        if (rewardRate == 0) revert RewardRateNotSet();
        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        uint256 remaining = periodFinish > block.timestamp ? periodFinish - block.timestamp : 0;
        uint256 leftover = remaining * rewardRate; // undistributed funded tokens
        periodFinish = block.timestamp + (leftover + amount) / rewardRate;
        emit RewardsFunded(msg.sender, amount, periodFinish);
    }

    /// @notice Owner lever for the emission rate. Preserves the pool of already
    ///         funded-but-undistributed tokens, only stretching or compressing
    ///         the timeline. Setting the rate to zero pauses emissions.
    function setRewardRate(uint256 newRate) external onlyOwner updateReward(address(0)) {
        uint256 remaining = periodFinish > block.timestamp ? periodFinish - block.timestamp : 0;
        uint256 leftover = remaining * rewardRate; // value before changing rate
        rewardRate = newRate;
        periodFinish = newRate > 0 ? block.timestamp + leftover / newRate : block.timestamp;
        emit RewardRateUpdated(newRate, periodFinish);
    }
}
