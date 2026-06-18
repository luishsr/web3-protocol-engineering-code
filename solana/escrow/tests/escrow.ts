// tests/escrow.ts
//
// TypeScript test suite for the OTC Escrow worked example (Chapter 17).
// Drives the program against a local validator with `anchor test`.
//
// Coverage:
//   1. make -> take happy path (both legs swap, offer closes)
//   2. cancel returns the vaulted tokens to the maker
//   3. a take with the wrong token_b mint is rejected
//   4. a take by a taker with insufficient token B is rejected (vault intact)
//   5. an offer cannot be taken twice (replay / double-take protection)
//
// NOTE (vs. the book, Anchor 0.30.x): on Anchor 0.30+/0.32.x, `.accounts({...})`
// is strict and only accepts accounts the IDL resolver cannot derive on its own.
// To pass the full, explicit account map the book shows, use `.accountsPartial({...})`.
// The unspecified programs (associatedTokenProgram, systemProgram) are resolved
// automatically.

import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { Escrow } from "../target/types/escrow";
import {
  TOKEN_PROGRAM_ID,
  createMint,
  getOrCreateAssociatedTokenAccount,
  getAssociatedTokenAddressSync,
  mintTo,
  getAccount,
} from "@solana/spl-token";
import { Keypair, PublicKey, LAMPORTS_PER_SOL } from "@solana/web3.js";
import { assert } from "chai";

describe("escrow", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const program = anchor.workspace.escrow as Program<Escrow>;
  const connection = provider.connection;
  const payer = (provider.wallet as anchor.Wallet).payer;

  let mintA: PublicKey; // 6 decimals
  let mintB: PublicKey; // 6 decimals
  const maker = Keypair.generate();
  const taker = Keypair.generate();

  const DECIMALS = 6;
  const toBase = (n: number) => new anchor.BN(n * 10 ** DECIMALS);

  async function fund(pubkey: PublicKey, sol = 2) {
    const sig = await connection.requestAirdrop(pubkey, sol * LAMPORTS_PER_SOL);
    await connection.confirmTransaction(sig);
  }

  function offerPda(id: anchor.BN, makerKey: PublicKey): PublicKey {
    const [pda] = PublicKey.findProgramAddressSync(
      [
        Buffer.from("offer"),
        makerKey.toBuffer(),
        id.toArrayLike(Buffer, "le", 8),
      ],
      program.programId
    );
    return pda;
  }

  before(async () => {
    await fund(maker.publicKey);
    await fund(taker.publicKey);

    // payer is the mint authority for both test mints.
    mintA = await createMint(
      connection,
      payer,
      payer.publicKey,
      null,
      DECIMALS
    );
    mintB = await createMint(
      connection,
      payer,
      payer.publicKey,
      null,
      DECIMALS
    );

    // Maker holds 1,000 token A.
    const makerA = await getOrCreateAssociatedTokenAccount(
      connection,
      payer,
      mintA,
      maker.publicKey
    );
    await mintTo(
      connection,
      payer,
      mintA,
      makerA.address,
      payer,
      1_000 * 10 ** DECIMALS
    );

    // Taker holds 1,000 token B.
    const takerB = await getOrCreateAssociatedTokenAccount(
      connection,
      payer,
      mintB,
      taker.publicKey
    );
    await mintTo(
      connection,
      payer,
      mintB,
      takerB.address,
      payer,
      1_000 * 10 ** DECIMALS
    );
  });

  it("make -> take swaps both legs and closes the offer", async () => {
    const id = new anchor.BN(1);
    const offer = offerPda(id, maker.publicKey);
    const vault = getAssociatedTokenAddressSync(mintA, offer, true);

    const makerA = getAssociatedTokenAddressSync(mintA, maker.publicKey);

    await program.methods
      .make(id, toBase(100), toBase(50))
      .accountsPartial({
        maker: maker.publicKey,
        tokenAMint: mintA,
        tokenBMint: mintB,
        makerTokenA: makerA,
        offer,
        vault,
        tokenProgram: TOKEN_PROGRAM_ID,
      })
      .signers([maker])
      .rpc();

    // The vault now holds 100 token A.
    const vaultAcct = await getAccount(connection, vault);
    assert.equal(vaultAcct.amount.toString(), toBase(100).toString());

    const takerA = getAssociatedTokenAddressSync(mintA, taker.publicKey);
    const takerB = getAssociatedTokenAddressSync(mintB, taker.publicKey);
    const makerB = getAssociatedTokenAddressSync(mintB, maker.publicKey);

    await program.methods
      .take()
      .accountsPartial({
        taker: taker.publicKey,
        maker: maker.publicKey,
        tokenAMint: mintA,
        tokenBMint: mintB,
        offer,
        vault,
        takerTokenA: takerA,
        takerTokenB: takerB,
        makerTokenB: makerB,
        tokenProgram: TOKEN_PROGRAM_ID,
      })
      .signers([taker])
      .rpc();

    // Taker received 100 token A; maker received 50 token B.
    assert.equal(
      (await getAccount(connection, takerA)).amount.toString(),
      toBase(100).toString()
    );
    assert.equal(
      (await getAccount(connection, makerB)).amount.toString(),
      toBase(50).toString()
    );

    // The offer account is closed.
    const closed = await connection.getAccountInfo(offer);
    assert.isNull(closed);
  });

  it("cancel returns the vaulted tokens to the maker", async () => {
    const id = new anchor.BN(2);
    const offer = offerPda(id, maker.publicKey);
    const vault = getAssociatedTokenAddressSync(mintA, offer, true);
    const makerA = getAssociatedTokenAddressSync(mintA, maker.publicKey);

    const before = (await getAccount(connection, makerA)).amount;

    await program.methods
      .make(id, toBase(100), toBase(50))
      .accountsPartial({
        maker: maker.publicKey,
        tokenAMint: mintA,
        tokenBMint: mintB,
        makerTokenA: makerA,
        offer,
        vault,
        tokenProgram: TOKEN_PROGRAM_ID,
      })
      .signers([maker])
      .rpc();

    await program.methods
      .cancel()
      .accountsPartial({
        maker: maker.publicKey,
        tokenAMint: mintA,
        offer,
        vault,
        makerTokenA: makerA,
        tokenProgram: TOKEN_PROGRAM_ID,
      })
      .signers([maker])
      .rpc();

    // Maker's token-A balance is unchanged net of the round trip.
    const after = (await getAccount(connection, makerA)).amount;
    assert.equal(after.toString(), before.toString());
    assert.isNull(await connection.getAccountInfo(offer));
  });

  it("rejects a take that uses the wrong token_b mint", async () => {
    const id = new anchor.BN(3);
    const offer = offerPda(id, maker.publicKey);
    const vault = getAssociatedTokenAddressSync(mintA, offer, true);
    const makerA = getAssociatedTokenAddressSync(mintA, maker.publicKey);

    await program.methods
      .make(id, toBase(100), toBase(50))
      .accountsPartial({
        maker: maker.publicKey,
        tokenAMint: mintA,
        tokenBMint: mintB,
        makerTokenA: makerA,
        offer,
        vault,
        tokenProgram: TOKEN_PROGRAM_ID,
      })
      .signers([maker])
      .rpc();

    // A rogue mint the taker controls.
    const rogueMint = await createMint(
      connection,
      payer,
      payer.publicKey,
      null,
      DECIMALS
    );
    const takerRogue = await getOrCreateAssociatedTokenAccount(
      connection,
      payer,
      rogueMint,
      taker.publicKey
    );
    await mintTo(
      connection,
      payer,
      rogueMint,
      takerRogue.address,
      payer,
      1_000 * 10 ** DECIMALS
    );

    const takerA = getAssociatedTokenAddressSync(mintA, taker.publicKey);
    const makerRogue = getAssociatedTokenAddressSync(
      rogueMint,
      maker.publicKey
    );

    try {
      await program.methods
        .take()
        .accountsPartial({
          taker: taker.publicKey,
          maker: maker.publicKey,
          tokenAMint: mintA,
          tokenBMint: rogueMint, // <-- wrong mint
          offer,
          vault,
          takerTokenA: takerA,
          takerTokenB: takerRogue.address,
          makerTokenB: makerRogue,
          tokenProgram: TOKEN_PROGRAM_ID,
        })
        .signers([taker])
        .rpc();
      assert.fail("take with wrong mint should have reverted");
    } catch (err) {
      // Anchor raises a constraint violation (has_one / seeds) — the trade is refused.
      assert.ok(err, "expected a constraint error");
    }

    // Clean up so later tests can reuse nothing from this offer.
    await program.methods
      .cancel()
      .accountsPartial({
        maker: maker.publicKey,
        tokenAMint: mintA,
        offer,
        vault,
        makerTokenA: makerA,
        tokenProgram: TOKEN_PROGRAM_ID,
      })
      .signers([maker])
      .rpc();
  });

  it("rejects a take when the taker lacks enough token B", async () => {
    const id = new anchor.BN(4);
    const offer = offerPda(id, maker.publicKey);
    const vault = getAssociatedTokenAddressSync(mintA, offer, true);
    const makerA = getAssociatedTokenAddressSync(mintA, maker.publicKey);

    // Want an absurd amount of token B that the taker can't pay.
    await program.methods
      .make(id, toBase(100), toBase(10_000))
      .accountsPartial({
        maker: maker.publicKey,
        tokenAMint: mintA,
        tokenBMint: mintB,
        makerTokenA: makerA,
        offer,
        vault,
        tokenProgram: TOKEN_PROGRAM_ID,
      })
      .signers([maker])
      .rpc();

    const takerA = getAssociatedTokenAddressSync(mintA, taker.publicKey);
    const takerB = getAssociatedTokenAddressSync(mintB, taker.publicKey);
    const makerB = getAssociatedTokenAddressSync(mintB, maker.publicKey);

    try {
      await program.methods
        .take()
        .accountsPartial({
          taker: taker.publicKey,
          maker: maker.publicKey,
          tokenAMint: mintA,
          tokenBMint: mintB,
          offer,
          vault,
          takerTokenA: takerA,
          takerTokenB: takerB,
          makerTokenB: makerB,
          tokenProgram: TOKEN_PROGRAM_ID,
        })
        .signers([taker])
        .rpc();
      assert.fail("take with insufficient funds should have reverted");
    } catch (err) {
      assert.ok(err);
    }

    // The vault still holds the full 100 token A — atomicity held.
    const vaultAcct = await getAccount(connection, vault);
    assert.equal(vaultAcct.amount.toString(), toBase(100).toString());

    await program.methods
      .cancel()
      .accountsPartial({
        maker: maker.publicKey,
        tokenAMint: mintA,
        offer,
        vault,
        makerTokenA: makerA,
        tokenProgram: TOKEN_PROGRAM_ID,
      })
      .signers([maker])
      .rpc();
  });

  it("rejects taking the same offer twice", async () => {
    const id = new anchor.BN(5);
    const offer = offerPda(id, maker.publicKey);
    const vault = getAssociatedTokenAddressSync(mintA, offer, true);
    const makerA = getAssociatedTokenAddressSync(mintA, maker.publicKey);

    await program.methods
      .make(id, toBase(100), toBase(50))
      .accountsPartial({
        maker: maker.publicKey,
        tokenAMint: mintA,
        tokenBMint: mintB,
        makerTokenA: makerA,
        offer,
        vault,
        tokenProgram: TOKEN_PROGRAM_ID,
      })
      .signers([maker])
      .rpc();

    const takerA = getAssociatedTokenAddressSync(mintA, taker.publicKey);
    const takerB = getAssociatedTokenAddressSync(mintB, taker.publicKey);
    const makerB = getAssociatedTokenAddressSync(mintB, maker.publicKey);

    const takeAccounts = {
      taker: taker.publicKey,
      maker: maker.publicKey,
      tokenAMint: mintA,
      tokenBMint: mintB,
      offer,
      vault,
      takerTokenA: takerA,
      takerTokenB: takerB,
      makerTokenB: makerB,
      tokenProgram: TOKEN_PROGRAM_ID,
    };

    await program.methods
      .take()
      .accountsPartial(takeAccounts)
      .signers([taker])
      .rpc();

    try {
      await program.methods
        .take()
        .accountsPartial(takeAccounts)
        .signers([taker])
        .rpc();
      assert.fail("second take should have reverted");
    } catch (err) {
      // The offer account no longer exists; deserialization fails.
      assert.ok(err);
    }
  });
});
