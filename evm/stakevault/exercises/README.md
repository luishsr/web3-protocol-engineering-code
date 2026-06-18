# StakeVault Exercises

Hands-on extensions to the canonical, verified **StakeVault** from Chapter 13 of
*Web3 Protocol Engineering*. Each exercise gives you a compiling `starter/`
contract with stubbed function bodies and `// TODO` markers, plus a `solution/`
with the reference implementation and a passing test suite.

These reinforce the book's reward-accumulator design (Chapters 13–14) and the
security/economics chapters (Chapters 19–21).

| # | Exercise | Difficulty | One-liner |
|---|----------|------------|-----------|
| 01 | [Emergency Withdraw](./01-emergency-withdraw) | Beginner | Add `emergencyWithdraw()` that returns stake but forfeits accrued rewards. |
| 02 | [Withdrawal Cooldown](./02-withdrawal-cooldown) | Intermediate | Gate withdrawals behind a per-user, `stake`-armed time lock (tested with `vm.warp`). |
| 03 | [Finite Rewards Duration](./03-rewards-duration) | Advanced | Replace the free-form rate setter with the Synthetix `rewardsDuration` + `notifyRewardAmount` model. |

## Layout

```
exercises/
  foundry.toml              shared config; reuses the parent project's lib/ and src/
  mocks/MockERC20.sol       minimal mintable ERC-20 for the tests
  0N-<slug>/
    README.md               problem statement, concepts, acceptance criteria, hints
    starter/                compiling stub — your starting point (`forge build`)
    solution/               reference solution + passing test
```

The shared `foundry.toml` remaps `@base/` to the parent project's `src/` and
points `libs` at `../lib`, so the exercises build against the exact same
OpenZeppelin and forge-std versions as the canonical vault — without copying or
modifying it.

## How to run

All commands run from this `exercises/` directory:

```bash
# Build everything (starters + solutions). Starters compile out of the box.
forge build

# Run every solution test suite.
forge test

# Run a single exercise's tests.
forge test --match-path '01-emergency-withdraw/solution/*'
forge test --match-contract CooldownStakeVaultTest
forge test --match-contract DurationStakeVaultTest

# Format new Solidity.
forge fmt
```

## Working an exercise

1. Read the exercise `README.md` for the problem and acceptance criteria.
2. Open `starter/` and implement the `// TODO`s (the stub reverts
   `NotImplemented()` or returns defaults so it always compiles).
3. Test against the solution's test file, or write your own, until green.
4. Compare with `solution/` — the reference is one valid answer, not the only one.
