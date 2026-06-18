// programs/escrow/src/lib.rs  — EXERCISE 02 STARTER: Protocol Fee on take
//
// This is a PATCH OVER THE BASE PROGRAM (code/solana/escrow). It will NOT build
// as-is: fill in the `todo!()` calls and `// TODO:` holes. Copy it over
// programs/escrow/src/lib.rs in a scratch copy of the workspace and run
// `anchor build` as you go. The reference answer is in ../solution/lib.rs.
//
// Goal: charge a protocol fee (in basis points) on the token-B leg of `take`,
// routed to a treasury account owned by a singleton Config PDA.
//
// Design choice (document yours): the fee is charged ON TOP of the maker's
// `wanted_amount` so the maker is paid exactly what they quoted.

use anchor_lang::prelude::*;
use anchor_spl::{
    associated_token::AssociatedToken,
    token::{
        close_account, transfer_checked, CloseAccount, Mint, Token, TokenAccount, TransferChecked,
    },
};

declare_id!("9AGrJRrLNiqoikrGRFDHxCSewZzpsNfYpuEaZ9e3CESL");

const MAX_FEE_BPS: u16 = 1_000; // 10% ceiling
const BPS_DENOMINATOR: u128 = 10_000;

#[program]
pub mod escrow {
    use super::*;

    // TODO: implement `initialize_config(ctx, fee_bps: u16)`.
    //   * require!(fee_bps <= MAX_FEE_BPS, EscrowError::FeeTooHigh);
    //   * set Config { admin: admin.key(), fee_bps, bump: ctx.bumps.config }.
    pub fn initialize_config(ctx: Context<InitializeConfig>, fee_bps: u16) -> Result<()> {
        let _ = (ctx, fee_bps);
        todo!("set the Config PDA's admin + fee_bps");
    }

    // Unchanged from the base program — copy the body in.
    pub fn make(ctx: Context<Make>, id: u64, offer_amount: u64, wanted_amount: u64) -> Result<()> {
        let _ = (ctx, id, offer_amount, wanted_amount);
        todo!("copy `make` unchanged from the base program");
    }

    pub fn take(ctx: Context<Take>) -> Result<()> {
        let offer_amount = ctx.accounts.offer.offer_amount;
        let wanted_amount = ctx.accounts.offer.wanted_amount;

        // TODO: compute the fee with u128 math (rounds down):
        //   let fee_bps = ctx.accounts.config.fee_bps as u128;
        //   let fee = ((wanted_amount as u128) * fee_bps / BPS_DENOMINATOR) as u64;

        // Leg 1a (unchanged): taker pays the maker the full `wanted_amount` in
        //   token B. Copy this transfer_checked from the base program.

        // TODO Leg 1b: if fee > 0, transfer `fee` token B from `taker_token_b`
        //   to `treasury_token_b` (taker is the authority/signer).

        // Leg 2 (unchanged): vault releases `offer_amount` token A to the taker,
        //   signed by the Offer PDA; then close the vault to the maker. Copy
        //   both from the base program.
        let _ = (offer_amount, wanted_amount, BPS_DENOMINATOR);
        todo!("assemble the three transfers + vault close");
    }

    // Unchanged from the base program — copy the body in.
    pub fn cancel(ctx: Context<Cancel>) -> Result<()> {
        let _ = ctx;
        todo!("copy `cancel` unchanged from the base program");
    }
}

// TODO: define the Config account.
//   #[account]
//   #[derive(InitSpace)]
//   pub struct Config { pub admin: Pubkey, pub fee_bps: u16, pub bump: u8 }

#[account]
#[derive(InitSpace)]
pub struct Offer {
    pub id: u64,
    pub maker: Pubkey,
    pub token_a_mint: Pubkey,
    pub token_b_mint: Pubkey,
    pub offer_amount: u64,
    pub wanted_amount: u64,
    pub bump: u8,
}

// TODO: define `InitializeConfig` accounts.
//   * admin: mut Signer (payer)
//   * config: init, payer = admin, space = 8 + Config::INIT_SPACE,
//             seeds = [b"config"], bump
//   * system_program

#[derive(Accounts)]
#[instruction(id: u64)]
pub struct Make<'info> {
    // Unchanged from the base program — copy it in.
    #[account(mut)]
    pub maker: Signer<'info>,
    pub token_a_mint: Box<Account<'info, Mint>>,
    pub token_b_mint: Box<Account<'info, Mint>>,
    #[account(
        mut,
        associated_token::mint = token_a_mint,
        associated_token::authority = maker,
    )]
    pub maker_token_a: Box<Account<'info, TokenAccount>>,
    #[account(
        init,
        payer = maker,
        space = 8 + Offer::INIT_SPACE,
        seeds = [b"offer", maker.key().as_ref(), id.to_le_bytes().as_ref()],
        bump,
    )]
    pub offer: Box<Account<'info, Offer>>,
    #[account(
        init,
        payer = maker,
        associated_token::mint = token_a_mint,
        associated_token::authority = offer,
    )]
    pub vault: Box<Account<'info, TokenAccount>>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Take<'info> {
    #[account(mut)]
    pub taker: Signer<'info>,
    #[account(mut)]
    pub maker: SystemAccount<'info>,
    pub token_a_mint: Box<Account<'info, Mint>>,
    pub token_b_mint: Box<Account<'info, Mint>>,

    // TODO: add the Config PDA (read-only) carrying the fee rate:
    //   #[account(seeds = [b"config"], bump = config.bump)]
    //   pub config: Box<Account<'info, Config>>,

    #[account(
        mut,
        close = maker,
        has_one = maker,
        has_one = token_a_mint,
        has_one = token_b_mint,
        seeds = [b"offer", maker.key().as_ref(), offer.id.to_le_bytes().as_ref()],
        bump = offer.bump,
    )]
    pub offer: Box<Account<'info, Offer>>,
    #[account(
        mut,
        associated_token::mint = token_a_mint,
        associated_token::authority = offer,
    )]
    pub vault: Box<Account<'info, TokenAccount>>,
    #[account(
        init_if_needed,
        payer = taker,
        associated_token::mint = token_a_mint,
        associated_token::authority = taker,
    )]
    pub taker_token_a: Box<Account<'info, TokenAccount>>,
    #[account(
        mut,
        associated_token::mint = token_b_mint,
        associated_token::authority = taker,
    )]
    pub taker_token_b: Box<Account<'info, TokenAccount>>,
    #[account(
        init_if_needed,
        payer = taker,
        associated_token::mint = token_b_mint,
        associated_token::authority = maker,
    )]
    pub maker_token_b: Box<Account<'info, TokenAccount>>,

    // TODO: add the treasury ATA, owned by the Config PDA:
    //   #[account(
    //       init_if_needed,
    //       payer = taker,
    //       associated_token::mint = token_b_mint,
    //       associated_token::authority = config,
    //   )]
    //   pub treasury_token_b: Box<Account<'info, TokenAccount>>,

    pub associated_token_program: Program<'info, AssociatedToken>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Cancel<'info> {
    // Unchanged from the base program — copy it in.
    #[account(mut)]
    pub maker: Signer<'info>,
    pub token_a_mint: Box<Account<'info, Mint>>,
    #[account(
        mut,
        close = maker,
        has_one = maker,
        has_one = token_a_mint,
        seeds = [b"offer", maker.key().as_ref(), offer.id.to_le_bytes().as_ref()],
        bump = offer.bump,
    )]
    pub offer: Box<Account<'info, Offer>>,
    #[account(
        mut,
        associated_token::mint = token_a_mint,
        associated_token::authority = offer,
    )]
    pub vault: Box<Account<'info, TokenAccount>>,
    #[account(
        mut,
        associated_token::mint = token_a_mint,
        associated_token::authority = maker,
    )]
    pub maker_token_a: Box<Account<'info, TokenAccount>>,
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[error_code]
pub enum EscrowError {
    #[msg("Amount must be greater than zero")]
    ZeroAmount,
    // TODO: add `FeeTooHigh`.
}
