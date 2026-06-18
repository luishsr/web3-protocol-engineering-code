// programs/escrow/src/lib.rs  — EXERCISE 01 STARTER: Offer Expiry
//
// This is a PATCH OVER THE BASE PROGRAM (code/solana/escrow). It will NOT build
// as-is: the `todo!()` calls and `// TODO:` holes are yours to fill in. Copy it
// over programs/escrow/src/lib.rs in a scratch copy of the workspace and run
// `anchor build` as you go. The reference answer is in ../solution/lib.rs.
//
// Goal: give each offer a Unix-timestamp expiry. `take` is refused after expiry;
// `cancel` is maker-only before expiry but PERMISSIONLESS after it.

use anchor_lang::prelude::*;
use anchor_spl::{
    associated_token::AssociatedToken,
    token::{
        close_account, transfer_checked, CloseAccount, Mint, Token, TokenAccount, TransferChecked,
    },
};

declare_id!("9AGrJRrLNiqoikrGRFDHxCSewZzpsNfYpuEaZ9e3CESL");

#[program]
pub mod escrow {
    use super::*;

    // TODO: add a fourth parameter `expiry: i64` to `make`.
    pub fn make(ctx: Context<Make>, id: u64, offer_amount: u64, wanted_amount: u64) -> Result<()> {
        require!(offer_amount > 0, EscrowError::ZeroAmount);
        require!(wanted_amount > 0, EscrowError::ZeroAmount);

        // TODO: read the current time from the Clock sysvar
        //   (`let now = Clock::get()?.unix_timestamp;`) and reject an expiry that
        //   is not strictly in the future with EscrowError::ExpiryInPast.

        ctx.accounts.offer.set_inner(Offer {
            id,
            maker: ctx.accounts.maker.key(),
            token_a_mint: ctx.accounts.token_a_mint.key(),
            token_b_mint: ctx.accounts.token_b_mint.key(),
            offer_amount,
            wanted_amount,
            // TODO: store `expiry` on the Offer.
            bump: ctx.bumps.offer,
        });

        let cpi_accounts = TransferChecked {
            from: ctx.accounts.maker_token_a.to_account_info(),
            mint: ctx.accounts.token_a_mint.to_account_info(),
            to: ctx.accounts.vault.to_account_info(),
            authority: ctx.accounts.maker.to_account_info(),
        };
        transfer_checked(
            CpiContext::new(ctx.accounts.token_program.to_account_info(), cpi_accounts),
            offer_amount,
            ctx.accounts.token_a_mint.decimals,
        )?;

        Ok(())
    }

    pub fn take(ctx: Context<Take>) -> Result<()> {
        // TODO: reject the take if the offer has expired
        //   (`now > offer.expiry`) with EscrowError::OfferExpired.

        let offer_amount = ctx.accounts.offer.offer_amount;
        let wanted_amount = ctx.accounts.offer.wanted_amount;

        // ... legs 1 and 2 are unchanged from the base program. Keep them. ...
        let _ = (offer_amount, wanted_amount);
        todo!("copy the unchanged take body (both transfer legs + vault close) from the base program");
    }

    pub fn cancel(ctx: Context<Cancel>) -> Result<()> {
        // TODO: authorization gate.
        //   * Read `now` from the Clock sysvar.
        //   * `is_maker = caller.key() == maker.key()`
        //   * `expired  = now > offer.expiry`
        //   * require!(is_maker || expired, EscrowError::Unauthorized);

        let offer_amount = ctx.accounts.offer.offer_amount;
        let _ = offer_amount;

        // ... the refund + vault-close body is unchanged from the base program;
        // the Offer PDA still signs with the same seeds. Keep it. ...
        todo!("copy the unchanged cancel body (refund leg + vault close) from the base program");
    }
}

#[account]
#[derive(InitSpace)]
pub struct Offer {
    pub id: u64,
    pub maker: Pubkey,
    pub token_a_mint: Pubkey,
    pub token_b_mint: Pubkey,
    pub offer_amount: u64,
    pub wanted_amount: u64,
    // TODO: add `pub expiry: i64,` (a Unix timestamp). InitSpace will size it.
    pub bump: u8,
}

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
    // Unchanged from the base program — copy it in.
    #[account(mut)]
    pub taker: Signer<'info>,
    #[account(mut)]
    pub maker: SystemAccount<'info>,
    pub token_a_mint: Box<Account<'info, Mint>>,
    pub token_b_mint: Box<Account<'info, Mint>>,
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
    pub associated_token_program: Program<'info, AssociatedToken>,
    pub token_program: Program<'info, Token>,
    pub system_program: Program<'info, System>,
}

#[derive(Accounts)]
pub struct Cancel<'info> {
    // TODO: restructure for permissionless-after-expiry cancellation.
    //   * Replace the `maker: Signer` with a `caller: Signer` (the actor) AND a
    //     separate `maker: SystemAccount` (the offer owner / refund + rent dest).
    //   * Keep `close = maker` and `has_one = maker` on the offer so the maker is
    //     always the one made whole, regardless of who triggered the cancel.
    //
    // #[account(mut)]
    // pub caller: Signer<'info>,
    // #[account(mut)]
    // pub maker: SystemAccount<'info>,

    #[account(mut)]
    pub maker: Signer<'info>, // TODO: replace per the note above

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
    // TODO: add the new variants you reference above:
    //   ExpiryInPast, OfferExpired, Unauthorized
}
