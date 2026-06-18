// tests/escrow-expiry.ts  — EXERCISE 01 SOLUTION test (Offer Expiry)
//
// Drop this into `tests/` alongside the base suite (or replace it) and run with
// `anchor test`. It assumes the program from
// exercises/01-offer-expiry/solution/lib.rs is built into target/.
//
// The local validator's Clock tracks real wall-clock time, so we test expiry
// with short real-time delays rather than a manipulated clock.
//
// Coverage:
//   1. make rejects an expiry in the past.
//   2. take succeeds before expiry (happy path).
//   3. take fails once the offer has expired, and then ANYONE may cancel it.
//   4. before expiry, a non-maker cannot cancel; the maker can.

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

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));
const nowSec = () => Math.floor(Date.now() / 1000);

describe("escrow — offer expiry", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const program = anchor.workspace.escrow as Program<Escrow>;
  const connection = provider.connection;
  const payer = (provider.wallet as anchor.Wallet).payer;

  let mintA: PublicKey;
  let mintB: PublicKey;
  const maker = Keypair.generate();
  const taker = Keypair.generate();
  const stranger = Keypair.generate();

  const DECIMALS = 6;
  const toBase = (n: number) => new anchor.BN(n * 10 ** DECIMALS);

  async function fund(pubkey: PublicKey, sol = 2) {
    const sig = await connection.requestAirdrop(pubkey, sol * LAMPORTS_PER_SOL);
    await connection.confirmTransaction(sig);
  }

  function offerPda(id: anchor.BN, makerKey: PublicKey): PublicKey {
    const [pda] = PublicKey.findProgramAddressSync(
      [Buffer.from("offer"), makerKey.toBuffer(), id.toArrayLike(Buffer, "le", 8)],
      program.programId
    );
    return pda;
  }

  before(async () => {
    await fund(maker.publicKey);
    await fund(taker.publicKey);
    await fund(stranger.publicKey);

    mintA = await createMint(connection, payer, payer.publicKey, null, DECIMALS);
    mintB = await createMint(connection, payer, payer.publicKey, null, DECIMALS);

    const makerA = await getOrCreateAssociatedTokenAccount(
      connection,
      payer,
      mintA,
      maker.publicKey
    );
    await mintTo(connection, payer, mintA, makerA.address, payer, 1_000 * 10 ** DECIMALS);

    const takerB = await getOrCreateAssociatedTokenAccount(
      connection,
      payer,
      mintB,
      taker.publicKey
    );
    await mintTo(connection, payer, mintB, takerB.address, payer, 1_000 * 10 ** DECIMALS);
  });

  it("rejects a make with an expiry in the past", async () => {
    const id = new anchor.BN(10);
    const offer = offerPda(id, maker.publicKey);
    const vault = getAssociatedTokenAddressSync(mintA, offer, true);
    const makerA = getAssociatedTokenAddressSync(mintA, maker.publicKey);

    try {
      await program.methods
        .make(id, toBase(100), toBase(50), new anchor.BN(nowSec() - 60))
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
      assert.fail("make with past expiry should revert");
    } catch (err) {
      assert.ok(err, "expected ExpiryInPast");
    }
  });

  it("take succeeds before expiry", async () => {
    const id = new anchor.BN(11);
    const offer = offerPda(id, maker.publicKey);
    const vault = getAssociatedTokenAddressSync(mintA, offer, true);
    const makerA = getAssociatedTokenAddressSync(mintA, maker.publicKey);

    await program.methods
      .make(id, toBase(100), toBase(50), new anchor.BN(nowSec() + 3600))
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

    assert.equal(
      (await getAccount(connection, takerA)).amount.toString(),
      toBase(100).toString()
    );
    assert.isNull(await connection.getAccountInfo(offer));
  });

  it("after expiry take fails and anyone may cancel", async () => {
    const id = new anchor.BN(12);
    const offer = offerPda(id, maker.publicKey);
    const vault = getAssociatedTokenAddressSync(mintA, offer, true);
    const makerA = getAssociatedTokenAddressSync(mintA, maker.publicKey);

    const before = (await getAccount(connection, makerA)).amount;

    // Expire ~2 seconds out.
    await program.methods
      .make(id, toBase(100), toBase(50), new anchor.BN(nowSec() + 2))
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

    await sleep(4000);

    const takerA = getAssociatedTokenAddressSync(mintA, taker.publicKey);
    const takerB = getAssociatedTokenAddressSync(mintB, taker.publicKey);
    const makerB = getAssociatedTokenAddressSync(mintB, maker.publicKey);

    // The taker can no longer take an expired offer.
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
      assert.fail("take after expiry should revert");
    } catch (err) {
      assert.ok(err, "expected OfferExpired");
    }

    // A stranger (not the maker) clears the expired offer; the maker is refunded.
    await program.methods
      .cancel()
      .accountsPartial({
        caller: stranger.publicKey,
        maker: maker.publicKey,
        tokenAMint: mintA,
        offer,
        vault,
        makerTokenA: makerA,
        tokenProgram: TOKEN_PROGRAM_ID,
      })
      .signers([stranger])
      .rpc();

    const after = (await getAccount(connection, makerA)).amount;
    assert.equal(after.toString(), before.toString());
    assert.isNull(await connection.getAccountInfo(offer));
  });

  it("before expiry only the maker may cancel", async () => {
    const id = new anchor.BN(13);
    const offer = offerPda(id, maker.publicKey);
    const vault = getAssociatedTokenAddressSync(mintA, offer, true);
    const makerA = getAssociatedTokenAddressSync(mintA, maker.publicKey);

    await program.methods
      .make(id, toBase(100), toBase(50), new anchor.BN(nowSec() + 3600))
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

    // A stranger cannot cancel a live offer.
    try {
      await program.methods
        .cancel()
        .accountsPartial({
          caller: stranger.publicKey,
          maker: maker.publicKey,
          tokenAMint: mintA,
          offer,
          vault,
          makerTokenA: makerA,
          tokenProgram: TOKEN_PROGRAM_ID,
        })
        .signers([stranger])
        .rpc();
      assert.fail("stranger cancel before expiry should revert");
    } catch (err) {
      assert.ok(err, "expected Unauthorized");
    }

    // The maker can.
    await program.methods
      .cancel()
      .accountsPartial({
        caller: maker.publicKey,
        maker: maker.publicKey,
        tokenAMint: mintA,
        offer,
        vault,
        makerTokenA: makerA,
        tokenProgram: TOKEN_PROGRAM_ID,
      })
      .signers([maker])
      .rpc();

    assert.isNull(await connection.getAccountInfo(offer));
  });
});
