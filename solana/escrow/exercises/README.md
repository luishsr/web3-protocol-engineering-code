# Escrow Exercises

Hands-on extensions to the Chapter 17 OTC Escrow (`code/solana/escrow`). Each
exercise is a **patch over the verified base program** — you edit a copy of
`programs/escrow/src/lib.rs`, not the canonical one. Toolchain matches the base
workspace: Anchor 0.32.1, Solana/Agave 3.1.9, Node 22.

| # | Exercise | Difficulty | One-liner |
|---|----------|-----------|-----------|
| 01 | [Offer Expiry](./01-offer-expiry/) | Intermediate | Add a Unix-timestamp expiry: `take` is refused after it, and `cancel` becomes permissionless once expired (maker-only before). Uses the `Clock` sysvar. |
| 02 | [Protocol Fee](./02-protocol-fee/) | Intermediate / Advanced | Add a bps protocol fee on the token-B leg of `take`, routed to a treasury ATA owned by a singleton `Config` PDA. Uses an extra CPI + fee arithmetic. |

Each folder contains:

- `README.md` — problem statement, concepts, acceptance criteria, a hint, and a
  pointer to the reference solution.
- `starter/lib.rs` — the base program with `// TODO:` holes. It is intentionally
  incomplete and will **not** build until you finish it.
- `solution/lib.rs` — the completed program.
- `solution/*.ts` — the added TypeScript test(s).

## Running an exercise

The exercises are **not** a standalone Anchor workspace; they patch the base
escrow. Work in a scratch copy so the canonical program stays pristine:

```bash
# from the repo root
cp -r code/solana/escrow /tmp/escrow-work
cd /tmp/escrow-work

# Exercise 01 — Offer Expiry
cp exercises/01-offer-expiry/solution/lib.rs           programs/escrow/src/lib.rs
cp exercises/01-offer-expiry/solution/escrow-expiry.ts tests/
rm tests/escrow.ts            # the base suite predates the new `make` signature
anchor test

# Exercise 02 — Protocol Fee  (start from a fresh copy)
cp exercises/02-protocol-fee/solution/lib.rs        programs/escrow/src/lib.rs
cp exercises/02-protocol-fee/solution/escrow-fee.ts tests/
anchor test
```

To *attempt* an exercise, copy its `starter/lib.rs` instead of the solution and
fill in the `// TODO:` holes, then write/run the tests.

> Note on Exercise 01: its `make` gains a fourth argument (`expiry`), so the
> original `tests/escrow.ts` no longer typechecks against the new IDL. Either
> remove it or update its `make(...)` calls. Exercise 02 keeps `make`'s
> signature, so the base suite still compiles (it just won't exercise the fee).

## What has been verified

For **both solutions**: `anchor build` succeeds cleanly and the added TS tests
pass `tsc --noEmit` against the generated IDL types. A full `anchor test` run
requires a local validator; the commands above reproduce it.
