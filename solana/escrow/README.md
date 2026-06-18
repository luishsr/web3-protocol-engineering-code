# OTC Escrow — Solana worked example

The companion Anchor project for **Web3 Protocol Engineering**, Chapter 17
(*A Worked Solana Protocol: OTC Escrow*). It is the Solana half of the book's
two running examples (the EVM half is **StakeVault**).

A peer-to-peer, trustless token swap. The **maker** locks `offer_amount` of
token A in a program-owned vault and names a price in token B; a **taker**
delivers `wanted_amount` of token B to the maker and atomically receives the
vaulted token A; the maker can **cancel** an untaken offer to reclaim the funds.
No admin, no fee, no privileged key — the only authority over a vault is the
`Offer` PDA, and the only rules it follows are compiled into `take`/`cancel`.

## What it demonstrates

- A **PDA** (`Offer`) doing triple duty: trade-terms state, on-chain identity,
  and the signing authority over the vault.
- A program-owned **vault** token account (the ATA of `(token_a_mint, offer)`).
- **SPL Token CPIs** — `transfer_checked` and `close_account` — including
  **PDA-signed** CPIs via `CpiContext::new_with_signer`.
- Declarative validation with Anchor constraints: `has_one`, `seeds`/`bump`,
  `associated_token::mint`/`authority`, `init`, `init_if_needed`, `close`.
- Typed errors with `#[error_code]`.

## Toolchain (exact versions used to build and test this repo)

| Tool                   | Version                                  |
| ---------------------- | ---------------------------------------- |
| `anchor-cli`           | 0.32.1                                    |
| `anchor-lang` crate    | 0.32.1 (feature `init-if-needed`)        |
| `anchor-spl` crate     | 0.32.1                                    |
| Solana CLI (Agave)     | 3.1.9                                     |
| platform-tools / BPF rustc | v1.52 (rustc 1.89.0)                 |
| host `rustc`           | 1.95.0                                    |
| Node                   | 22.x                                      |
| `@coral-xyz/anchor`    | ^0.32.1                                   |
| `@solana/spl-token`    | ^0.4.9                                    |

> **Note on the book's pin.** The book text (STYLE_GUIDE §8 and the chapter
> prose) pins **Anchor 0.30.x / Solana 1.18.x**. This repo is built and verified
> on the newer **Anchor 0.32.1 / Agave 3.1.9** toolchain that ships today, so it
> genuinely compiles and the tests pass on a current machine. The on-chain logic
> and account model are identical across these versions. The only reader-visible
> differences are in the TypeScript client and a couple of crate-feature lines —
> see **"Differences from the book (0.30.x → 0.32.x)"** below.

## Layout

```
escrow/
├── Anchor.toml                  # localnet config + test script
├── Cargo.toml                   # Rust workspace
├── package.json                 # JS deps (anchor, spl-token, mocha/chai)
├── tsconfig.json
├── programs/escrow/
│   ├── Cargo.toml               # anchor-lang + anchor-spl, init-if-needed
│   └── src/lib.rs               # the program: make / take / cancel
└── tests/escrow.ts              # 5 tests (1 happy path, 1 cancel, 3 adversarial)
```

## Build

```bash
anchor build          # compiles to BPF (target/deploy/escrow.so) and emits the IDL
anchor keys sync      # only if you regenerate the program keypair
```

The program ID is `9AGrJRrLNiqoikrGRFDHxCSewZzpsNfYpuEaZ9e3CESL` (the keypair in
`target/deploy/escrow-keypair.json`). It is already wired into `declare_id!` and
`Anchor.toml`.

## Test

```bash
anchor test           # builds, boots solana-test-validator, runs tests/escrow.ts
```

Expected output: **5 passing**.

```
escrow
  ✔ make -> take swaps both legs and closes the offer
  ✔ cancel returns the vaulted tokens to the maker
  ✔ rejects a take that uses the wrong token_b mint
  ✔ rejects a take when the taker lacks enough token B
  ✔ rejects taking the same offer twice
```

Three of the five are adversarial — on a public chain the rejection tests matter
more than the happy path.

## Chapter mapping

| Chapter | What it covers                                                       |
| ------- | ------------------------------------------------------------------- |
| Ch 15   | The Solana programming model: accounts, PDAs, rent, SPL Token, CPIs |
| Ch 16   | Anchor mechanics: `#[program]`, `#[derive(Accounts)]`, constraints  |
| **Ch 17** | **This program** — `make`/`take`/`cancel`, the vault, PDA signing |
| Ch 18   | Testing tooling: the validator, fuzzing, CI                         |

The `Offer` account, instruction signatures, and PDA seeds match the canonical
spec in `book/EXAMPLES.md` → "Example B — Solana: OTC Escrow".

## Differences from the book (0.30.x → 0.32.x)

The book's prose targets Anchor 0.30.x. To compile and pass tests on the
installed 0.32.1 toolchain, this repo differs in a few non-behavioral ways:

1. **Crate versions.** `programs/escrow/Cargo.toml` uses
   `anchor-lang = { version = "0.32.1", features = ["init-if-needed"] }` and
   `anchor-spl = "0.32.1"` (the book shows `0.30.1`). The program's `idl-build`
   feature must also list `anchor-spl/idl-build` for the IDL to generate.
2. **TypeScript client uses `.accountsPartial(...)`.** The book uses
   `.accounts({ ... })` with a full, explicit account map. On Anchor 0.30+ the
   `.accounts()` method is strict and only accepts accounts the IDL resolver
   *cannot* derive; passing the full map there is a type error. `.accountsPartial()`
   accepts the explicit map the book shows. (Readers could instead trim the maps
   down to just the non-derivable accounts and keep `.accounts()`.)
3. **Workspace key is `anchor.workspace.escrow`** (lower-case program name) in
   the generated types, not `anchor.workspace.Escrow`. The `Program<Escrow>`
   *type* import is unchanged.

The on-chain `lib.rs` is otherwise the book's code verbatim, formatted with
`cargo fmt`.
