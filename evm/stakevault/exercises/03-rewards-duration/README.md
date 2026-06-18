# Exercise 03 — Finite Rewards Duration (Synthetix model)

**Difficulty:** Advanced

## Problem

The canonical `StakeVault` exposes two free-form levers: the owner sets
`rewardRate` directly and tops up with `fundRewards`. That is flexible but puts
the solvency burden on the operator's discipline — nothing stops them from
setting a rate the contract cannot back.

This exercise refactors the contract to the **Synthetix finite-period model**
(see Chapter 13, Exercise 2). Instead of setting a rate, the owner:

1. picks a fixed `rewardsDuration` (only changeable *between* periods), and
2. calls `notifyRewardAmount(reward)`, which pulls the tokens in, **derives** the
   rate as `(reward + leftover) / rewardsDuration`, and pins
   `periodFinish = now + rewardsDuration`.

A balance check (`rewardRate <= balance / rewardsDuration`) makes "funded" and
"scheduled" the same fact, so emissions can never outrun the tokens held.

Starting point: `starter/DurationStakeVault.sol`, a copy of the vault with
`setRewardRate`/`fundRewards` already replaced by stubbed
`setRewardsDuration`/`notifyRewardAmount`.

## Concepts exercised

- Designing for solvency: bounding emissions by the contract's real token
  balance rather than operator promises.
- Rolling leftover emissions from an in-flight period into a new rate (the
  classic Synthetix top-up arithmetic).
- Lifecycle invariants: a duration may only change once a period has fully
  elapsed (`block.timestamp >= periodFinish`).
- Reusing the unchanged reward-accumulator core (`rewardPerToken`,
  `updateReward`, `lastTimeRewardApplicable`) — the emission *cap* at
  `periodFinish` comes for free.

## Acceptance criteria

- `setRewardsDuration(d)` is `onlyOwner`, reverts `RewardPeriodActive` while a
  period is live, reverts `ZeroDuration` on `d == 0`, else stores `d` and emits
  `RewardsDurationUpdated`.
- `notifyRewardAmount(reward)` is `onlyOwner`, runs `updateReward(address(0))`,
  transfers `reward` in, and sets:
  - `rewardRate = reward / rewardsDuration` when no period is active, or
  - `rewardRate = (reward + remaining * rewardRate) / rewardsDuration` mid-period;
  then `periodFinish = now + rewardsDuration` and `lastUpdateTime = now`.
- Reverts `RewardTooHigh` if `rewardRate > rewardToken.balanceOf(this) /
  rewardsDuration`, and `ZeroDuration` if no duration has been set.
- Emissions still cap at `periodFinish` (inherited behavior).

## Hint

Port the canonical Synthetix `notifyRewardAmount` almost verbatim, but
`safeTransferFrom` the reward tokens **before** computing the rate so the balance
check sees the new funds. The leftover term is `remaining * rewardRate` where
`remaining = periodFinish - block.timestamp`. Because tokens already in the vault
exactly back the leftover, a normal top-up always satisfies the balance check —
the guard is your defensive floor against rounding/under-funding.

## Reference solution

See [`solution/DurationStakeVault.sol`](./solution/DurationStakeVault.sol) and
the passing test in
[`solution/DurationStakeVault.t.sol`](./solution/DurationStakeVault.t.sol).

```bash
forge test --match-contract DurationStakeVaultTest -vv
```
