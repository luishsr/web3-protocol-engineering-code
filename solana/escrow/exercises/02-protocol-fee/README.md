# Exercise 02 — Protocol Fee on `take`

**Difficulty:** Intermediate / Advanced
**Builds on:** the Chapter 17 OTC Escrow (`code/solana/escrow`)
**Book reference:** extends the Chapter 17 protocol; relates to the value-flow
and accounting discipline of Chapter 8.

## Problem

Add a **protocol fee** charged in basis points on the token-B leg of every
`take`, routed to a protocol treasury.

1. Introduce a singleton **`Config` PDA** (`seeds = [b"config"]`) holding the
   protocol `admin` and the fee rate `fee_bps: u16`. A new `initialize_config`
   instruction creates it once and rejects a rate above a 10% ceiling
   (`MAX_FEE_BPS = 1000`).
2. On `take`, compute `fee = wanted_amount * fee_bps / 10_000` and transfer it
   in token B to the **treasury**, an ATA owned by the `Config` PDA.
3. **Design choice (documented):** the fee is charged *on top of* the maker's
   quoted `wanted_amount`. The maker still receives exactly `wanted_amount`; the
   taker pays `wanted_amount + fee`. (A valid alternative is to take the fee out
   of the maker's proceeds — pick one and state it. The solution uses on-top.)

## Concepts exercised

- A **singleton config PDA** and a one-time `init` instruction.
- **PDA-owned token accounts**: the treasury is an ATA whose authority is the
  `Config` PDA, so fees accrue to a program-controlled account.
- An **additional CPI** (`transfer_checked`) inside `take`, and `init_if_needed`
  to lazily create the treasury ATA per token-B mint.
- **Fee arithmetic and rounding**: u128 intermediate math to avoid overflow;
  integer division rounds the fee *down*.
- Constraint design: a `seeds`-validated read-only `config` account.

## Acceptance criteria

- `anchor build` succeeds.
- `initialize_config` stores the rate; a rate `> MAX_FEE_BPS` reverts
  (`FeeTooHigh`).
- After a `take`, the maker's token-B balance increased by exactly
  `wanted_amount`, and the treasury ATA increased by `wanted_amount * fee_bps /
  10_000`.
- The taker's total token-B spend equals `wanted_amount + fee`.
- The token-A leg, vault close, and `cancel`/`make` are unchanged.

## Hint

Keep the existing maker-payment transfer exactly as in the base program, then
add a *second* `transfer_checked` for the fee with the **taker** as authority
(the taker signs, so no PDA seeds are needed for the fee leg):

```rust
let fee = ((wanted_amount as u128) * (config.fee_bps as u128) / 10_000) as u64;
```

The treasury is just `getAssociatedTokenAddressSync(mintB, configPda, true)` on
the client side; on-chain declare it with
`associated_token::authority = config`. Guard the transfer with `if fee > 0`
so a zero-fee config issues no redundant CPI.

## Files

- `starter/lib.rs` — the base program with `// TODO:` holes to fill in. It is a
  patch over `code/solana/escrow`; it will not build until completed.
- `solution/lib.rs` — the completed program.
- `solution/escrow-fee.ts` — the added TypeScript tests (drop into `tests/`).

## How to run

```bash
# from a scratch copy of code/solana/escrow:
cp exercises/02-protocol-fee/solution/lib.rs    programs/escrow/src/lib.rs
cp exercises/02-protocol-fee/solution/escrow-fee.ts tests/
anchor test
```

The test suite calls `initialize_config` once in its `before` hook (tolerating
"already initialized" so it can re-run against a warm validator).

## Reference solution

`solution/lib.rs` and `solution/escrow-fee.ts`.
