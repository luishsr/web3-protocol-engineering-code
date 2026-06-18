# StakeVault

The worked EVM example from **Web3 Protocol Engineering** (Example A in
`EXAMPLES.md`). A single-asset staking vault that streams a separate reward
token to stakers pro-rata using the **reward-accumulator pattern**
(Synthetix/MasterChef style): unbounded stakers paid in constant gas, no loops.

It demonstrates the chain-idiomatic EVM toolkit: `SafeERC20` token handling,
OpenZeppelin `Ownable` access control, a `ReentrancyGuard` plus
Checks-Effects-Interactions, custom errors, events, and a solvency mechanism
(`periodFinish`) that guarantees the vault never promises rewards it does not
hold.

## What it does

- `stake(amount)` / `withdraw(amount)` — deposit and remove `stakingToken`.
- `claim()` — transfer accrued `rewardToken` to the caller.
- `exit()` — `withdraw(all)` + `claim()` in one transaction.
- `earned(account)` — view accrued, unclaimed rewards.
- `setRewardRate(newRate)` — owner sets emissions per second.
- `fundRewards(amount)` — pull reward tokens in and extend the schedule.

Two invariants anchor the design and are enforced by the test suite:

1. **Conservation of stake** — the sum of balances equals `totalStaked`.
2. **Solvency** — the vault never pays out more rewards than were funded.

## Layout

```
src/StakeVault.sol              production contract (Chapter 13)
test/StakeVault.t.sol           unit + fuzz tests, live reentrancy attack
test/StakeVault.invariants.t.sol stateful invariants (Chapter 14)
test/handlers/                  invariant handler with ghost accounting
test/mocks/MockERC20.sol        minimal mintable ERC-20
test/mocks/HookToken.sol        ERC-777-style callback token (attack surface)
script/Deploy.s.sol             deploy script
```

## Build and test

Dependencies live in `lib/` (OpenZeppelin Contracts v5.1.0 and forge-std).

```bash
forge build          # compiles with solc 0.8.24, optimizer on, 200 runs
forge test -vv       # unit + fuzz + invariant suites
forge fmt --check    # formatting
```

Run a single layer:

```bash
forge test --match-contract StakeVaultTest          # unit + fuzz
forge test --match-contract StakeVaultReentrancyTest # live reentrancy attempt
forge test --match-contract StakeVaultInvariants     # stateful invariants
```

## Chapter mapping

- **Chapter 13 — A Worked EVM Protocol: StakeVault**: the contract, the
  reward-accumulator math, Checks-Effects-Interactions, `periodFinish` solvency,
  and the core unit/fuzz/invariant tests.
- **Chapter 14 — Testing and Tooling on EVM**: the fuzzing, invariant
  (handler + ghost variables), reentrancy regression, and fork-testing patterns
  applied to this same contract.

## Configuration

`foundry.toml` pins Solidity `0.8.24`, optimizer on at 200 runs, `fuzz.runs =
256`, and `invariant = { runs = 256, depth = 64 }` per the book's style guide.

## Security assumptions

StakeVault assumes **standard, non-fee-on-transfer** ERC-20s, and treats both
the staking and reward tokens as **trusted at deploy time**. Fee-on-transfer
hardening and an empty-pool reward sweep are left as exercises (Chapter 13). In
production the `owner` should be a multisig or timelock (Chapter 22).
