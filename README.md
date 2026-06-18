# Web3 Protocol Engineering — Companion Code

Working, tested code for the book **_Web3 Protocol Engineering: Designing, Building,
and Securing Decentralized Protocols on Ethereum and Solana_** by Luis Soares.

> Repository: <https://github.com/luishsr/web3-protocol-engineering-code>

This repo lets you build and run the book's two worked protocols yourself, and work
through the hands-on exercises. The code here is the canonical version; the listings
in the book are excerpts from these files.

## What's inside

| Path | Chapter(s) | What it is |
|------|-----------|------------|
| [`evm/stakevault`](evm/stakevault) | 11–14 | **StakeVault** — a single-asset staking vault paying streaming rewards. Solidity + Foundry, with unit, fuzz, and invariant tests. |
| [`solana/escrow`](solana/escrow) | 15–18 | **OTC Escrow** — a peer-to-peer token-swap escrow. Rust + Anchor, with a TypeScript integration suite. |
| `evm/stakevault/exercises` | various | Starter stubs and reference solutions for the EVM exercises. |
| `solana/escrow/exercises` | various | Starter stubs and reference solutions for the Solana exercises. |

Each project has its own `README.md` with exact toolchain versions and run instructions.

## Prerequisites

- **EVM:** [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`).
- **Solana:** [Rust](https://rustup.rs), the [Solana CLI](https://docs.anza.xyz/cli/install),
  and [Anchor](https://www.anchor-lang.com/docs/installation) (via `avm`), plus Node 20+ and a package manager.

The exact versions each project is verified against are pinned in that project's README.

## Quick start

```bash
git clone https://github.com/luishsr/web3-protocol-engineering-code
cd web3-protocol-engineering-code

# EVM: build and run the full test suite (unit + fuzz + invariant)
cd evm/stakevault
forge install        # fetch dependencies
forge test -vv

# Solana: build the program and run the integration tests
cd ../../solana/escrow
yarn install         # or npm install
anchor test
```

## How the book and the repo fit together

Read a chapter, then open the matching directory and run it. The book explains *why*
the code is shaped the way it is; the repo lets you change it and watch the tests react.
Every exercise in the book that touches code can be completed against these projects.

## Security notice

This code is written to teach. It has been tested, but it has **not** been audited and
must not be deployed to a network holding real value without a professional review.
See Chapters 19–24 of the book for what that review involves.

## License

MIT — see [LICENSE](LICENSE). Use it freely, including in your own projects.
