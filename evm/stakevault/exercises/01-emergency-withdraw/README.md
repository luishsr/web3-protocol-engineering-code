# Exercise 01 — Emergency Withdraw

**Difficulty:** Beginner

## Problem

Stakers need an escape hatch. If the reward token misbehaves, the schedule
becomes uneconomical, or a user simply wants out *right now*, they should be able
to recover their principal in a single call — even at the cost of any rewards
they have accrued.

Add an `emergencyWithdraw()` function to a contract that extends the canonical
`StakeVault`. It returns the caller's **entire stake** and **forfeits all accrued
(unclaimed) rewards**. The forfeited rewards stay in the vault as unallocated
tokens (they are not paid out, and they are not stolen by anyone).

The starter (`starter/EmergencyStakeVault.sol`) is a small subclass of the
verified `StakeVault`; you only implement one function.

## Concepts exercised

- The reward-accumulator settlement pattern (`updateReward`) and *why* it must
  run before you touch a user's balance.
- Checks-Effects-Interactions ordering and reusing an inherited `nonReentrant`
  guard.
- Conservation-of-stake accounting: `totalStaked` and `balanceOf` must stay in
  lockstep.
- The difference between *forfeiting* rewards (zeroing the claim) and *paying*
  them.

## Acceptance criteria

- `emergencyWithdraw()` transfers the caller's full staked balance back to them.
- The caller's accrued rewards are set to zero; **no reward tokens are
  transferred** by the call.
- `totalStaked` decreases by exactly the withdrawn amount and the caller's
  `balanceOf` becomes `0`.
- Reverts when the caller has nothing staked.
- Emits an `EmergencyWithdrawn(user, amount, forfeited)` event.
- Other stakers' accounting is unaffected and continues to accrue correctly.

## Hint

The inherited `updateReward(msg.sender)` modifier settles the caller's earnings
into `rewards[msg.sender]` *before* the function body runs. Once that is banked,
"forfeiting" is just setting `rewards[msg.sender] = 0` before you transfer the
stake out. Mutate all state (rewards, `totalStaked`, `balanceOf`) before the
single `stakingToken.safeTransfer`, and apply the inherited `nonReentrant` guard.

## Reference solution

See [`solution/EmergencyStakeVault.sol`](./solution/EmergencyStakeVault.sol) and
the passing test in
[`solution/EmergencyStakeVault.t.sol`](./solution/EmergencyStakeVault.t.sol).

```bash
forge test --match-path '01-emergency-withdraw/solution/*' -vv
```
