# Exercise 02 — Withdrawal Cooldown

**Difficulty:** Intermediate

## Problem

Many staking systems want to discourage mercenary capital and mute bank-run
dynamics by making the *principal* sticky: once you stake, you must wait a fixed
cooldown before you can withdraw. Rewards, however, should stay liquid — a user
can keep claiming throughout the lock.

Starting from a copy of the canonical `StakeVault`
(`starter/CooldownStakeVault.sol`), add a per-user withdrawal cooldown:

- a `cooldownPeriod` (seconds), set at construction and tunable by the owner;
- a per-user `unlockAt` timestamp, **(re)armed on every `stake`**;
- a time gate in `withdraw` that blocks until the cooldown elapses.

## Concepts exercised

- Time-based access control and testing it deterministically with `vm.warp`.
- Reverting with a *parameterized* custom error (`WithdrawalLocked(unlockAt)`).
- Choosing which actions a gate should cover: `withdraw`/`exit` are gated, but
  `claim` is intentionally **not** — rewards stay liquid.
- The subtle anti-gaming choice of resetting the timer on every deposit so a user
  can't keep an old position "warm" to dodge the lock on a fresh top-up.

## Acceptance criteria

- Each `stake` sets `unlockAt[msg.sender] = block.timestamp + cooldownPeriod`.
- `withdraw` reverts with `WithdrawalLocked(unlockAt)` while
  `block.timestamp < unlockAt[msg.sender]`, and succeeds at or after that
  timestamp.
- A fresh `stake` re-arms the timer (an already-warm position does not let a
  top-up withdraw early).
- `claim` works during the lock and rewards continue to accrue.
- `setCooldownPeriod` is `onlyOwner` and emits `CooldownUpdated`.

## Hint

Three small edits to the copied vault: write `unlockAt[msg.sender]` in `stake`,
add the `if (block.timestamp < unlockAt[msg.sender]) revert WithdrawalLocked(...)`
check at the top of `withdraw` (after the balance check, before effects), and
implement the trivial `setCooldownPeriod` setter. In tests, drive the clock with
`vm.warp` and assert both the revert (one second short) and success (exactly at
the boundary, since the gate uses `<`).

## Reference solution

See [`solution/CooldownStakeVault.sol`](./solution/CooldownStakeVault.sol) and
the passing test in
[`solution/CooldownStakeVault.t.sol`](./solution/CooldownStakeVault.t.sol).

```bash
forge test --match-contract CooldownStakeVaultTest -vv
```
