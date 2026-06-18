# Exercise 01 — Offer Expiry

**Difficulty:** Intermediate
**Builds on:** the Chapter 17 OTC Escrow (`code/solana/escrow`)
**Book reference:** Chapter 17, *Exercises*, item 2.

## Problem

An untaken offer in the base program lives forever: the maker's token A stays
vaulted until the maker themselves calls `cancel`. If the maker disappears,
the funds are stranded, and a stale quoted price can be hit at any future time.

Add a per-offer **expiry**:

1. `make` takes a new `expiry: i64` argument (a Unix timestamp) and stores it on
   the `Offer`. Reject an expiry that is not strictly in the future.
2. `take` is **refused once the offer has expired** — a stale price can no
   longer be filled. Use Anchor's `Clock` sysvar to read the time on-chain.
3. `cancel` becomes **permissionless after expiry**: anyone may trigger the
   refund-and-close of an expired offer so vaulted funds are never stranded.
   **Before** expiry, only the maker may cancel. In all cases the maker is the
   refund and rent-return destination.

## Concepts exercised

- The **`Clock` sysvar** (`Clock::get()?.unix_timestamp`) for on-chain time.
- **Account constraints vs. handler logic**: `has_one`/`close = maker` keep the
  maker whole, while the maker-or-expired authorization is enforced in code.
- Re-shaping an `#[derive(Accounts)]` struct: splitting the single `maker:
  Signer` of `cancel` into a `caller: Signer` (the actor) and a `maker:
  SystemAccount` (the owner / refund target).
- `#[derive(InitSpace)]` automatically resizing the `Offer` for the new field.

## Acceptance criteria

- `anchor build` succeeds.
- `make` with a past `expiry` reverts (`ExpiryInPast`).
- `take` before expiry succeeds; `take` after expiry reverts (`OfferExpired`).
- After expiry, a non-maker `cancel` succeeds and refunds the **maker**.
- Before expiry, a non-maker `cancel` reverts (`Unauthorized`); the maker's
  `cancel` succeeds.
- The Offer PDA and vault are closed after a successful cancel/take.

## Hint

The `Offer` PDA seeds are unchanged, so the PDA still signs the vault transfers
with `[b"offer", maker.key().as_ref(), id.to_le_bytes().as_ref(), &[bump]]` —
note this uses the *maker's* key, not the caller's. Keep `close = maker` and
`has_one = maker` on the `offer` account so a third party clearing an expired
offer cannot redirect the refund or rent to themselves. The only new
authorization lives in the handler:

```rust
let now = Clock::get()?.unix_timestamp;
let is_maker = ctx.accounts.caller.key() == ctx.accounts.maker.key();
require!(is_maker || now > ctx.accounts.offer.expiry, EscrowError::Unauthorized);
```

## Files

- `starter/lib.rs` — the base program with `// TODO:` holes to fill in. It is a
  patch over `code/solana/escrow`; it will not build until completed.
- `solution/lib.rs` — the completed program.
- `solution/escrow-expiry.ts` — the added TypeScript tests (drop into `tests/`).

## How to run

```bash
# from a scratch copy of code/solana/escrow:
cp exercises/01-offer-expiry/solution/lib.rs        programs/escrow/src/lib.rs
cp exercises/01-offer-expiry/solution/escrow-expiry.ts tests/
anchor test
```

The tests use short real-time delays (the local validator's `Clock` tracks wall
time); the book's alternative is to manipulate the validator clock directly.

## Reference solution

`solution/lib.rs` and `solution/escrow-expiry.ts`.
