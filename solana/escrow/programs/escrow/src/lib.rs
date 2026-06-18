// programs/escrow/src/lib.rs
//
// OTC Escrow — the worked Solana protocol from Chapter 17 of
// "Web3 Protocol Engineering". Anchor 0.32.x / Solana (Agave) toolchain.
//
// A peer-to-peer token swap. The maker locks `offer_amount` of token A in a
// program-owned vault and states a price in token B; a taker delivers token B
// to the maker and receives token A atomically; the maker can cancel an
// untaken offer to reclaim the vaulted tokens. See README for the full mapping
// back to the book.

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

    pub fn make(ctx: Context<Make>, id: u64, offer_amount: u64, wanted_amount: u64) -> Result<()> {
        require!(offer_amount > 0, EscrowError::ZeroAmount);
        require!(wanted_amount > 0, EscrowError::ZeroAmount);

        ctx.accounts.offer.set_inner(Offer {
            id,
            maker: ctx.accounts.maker.key(),
            token_a_mint: ctx.accounts.token_a_mint.key(),
            token_b_mint: ctx.accounts.token_b_mint.key(),
            offer_amount,
            wanted_amount,
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
        let offer_amount = ctx.accounts.offer.offer_amount;
        let wanted_amount = ctx.accounts.offer.wanted_amount;

        // Leg 1: taker pays the maker in token B (taker is a real signer).
        let pay = TransferChecked {
            from: ctx.accounts.taker_token_b.to_account_info(),
            mint: ctx.accounts.token_b_mint.to_account_info(),
            to: ctx.accounts.maker_token_b.to_account_info(),
            authority: ctx.accounts.taker.to_account_info(),
        };
        transfer_checked(
            CpiContext::new(ctx.accounts.token_program.to_account_info(), pay),
            wanted_amount,
            ctx.accounts.token_b_mint.decimals,
        )?;

        // PDA signer seeds: namespace, maker, id, bump.
        let maker_key = ctx.accounts.maker.key();
        let id_bytes = ctx.accounts.offer.id.to_le_bytes();
        let signer_seeds: &[&[&[u8]]] = &[&[
            b"offer",
            maker_key.as_ref(),
            id_bytes.as_ref(),
            &[ctx.accounts.offer.bump],
        ]];

        // Leg 2: vault releases token A to the taker; the Offer PDA signs.
        let release = TransferChecked {
            from: ctx.accounts.vault.to_account_info(),
            mint: ctx.accounts.token_a_mint.to_account_info(),
            to: ctx.accounts.taker_token_a.to_account_info(),
            authority: ctx.accounts.offer.to_account_info(),
        };
        transfer_checked(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                release,
                signer_seeds,
            ),
            offer_amount,
            ctx.accounts.token_a_mint.decimals,
        )?;

        // Close the now-empty vault, refunding its rent to the maker.
        let close = CloseAccount {
            account: ctx.accounts.vault.to_account_info(),
            destination: ctx.accounts.maker.to_account_info(),
            authority: ctx.accounts.offer.to_account_info(),
        };
        close_account(CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            close,
            signer_seeds,
        ))?;

        Ok(())
    }

    pub fn cancel(ctx: Context<Cancel>) -> Result<()> {
        let offer_amount = ctx.accounts.offer.offer_amount;

        let maker_key = ctx.accounts.maker.key();
        let id_bytes = ctx.accounts.offer.id.to_le_bytes();
        let signer_seeds: &[&[&[u8]]] = &[&[
            b"offer",
            maker_key.as_ref(),
            id_bytes.as_ref(),
            &[ctx.accounts.offer.bump],
        ]];

        // Return the vaulted token A to the maker; the Offer PDA signs.
        let refund = TransferChecked {
            from: ctx.accounts.vault.to_account_info(),
            mint: ctx.accounts.token_a_mint.to_account_info(),
            to: ctx.accounts.maker_token_a.to_account_info(),
            authority: ctx.accounts.offer.to_account_info(),
        };
        transfer_checked(
            CpiContext::new_with_signer(
                ctx.accounts.token_program.to_account_info(),
                refund,
                signer_seeds,
            ),
            offer_amount,
            ctx.accounts.token_a_mint.decimals,
        )?;

        // Close the empty vault, rent back to the maker.
        let close = CloseAccount {
            account: ctx.accounts.vault.to_account_info(),
            destination: ctx.accounts.maker.to_account_info(),
            authority: ctx.accounts.offer.to_account_info(),
        };
        close_account(CpiContext::new_with_signer(
            ctx.accounts.token_program.to_account_info(),
            close,
            signer_seeds,
        ))?;

        Ok(())
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
    pub bump: u8,
}

#[derive(Accounts)]
#[instruction(id: u64)]
pub struct Make<'info> {
    #[account(mut)]
    pub maker: Signer<'info>,

    pub token_a_mint: Box<Account<'info, Mint>>,
    pub token_b_mint: Box<Account<'info, Mint>>,

    // The maker's own token-A account, which they spend from.
    #[account(
        mut,
        associated_token::mint = token_a_mint,
        associated_token::authority = maker,
    )]
    pub maker_token_a: Box<Account<'info, TokenAccount>>,

    // The Offer PDA: created here, sized by InitSpace, address fixed by seeds.
    #[account(
        init,
        payer = maker,
        space = 8 + Offer::INIT_SPACE,
        seeds = [b"offer", maker.key().as_ref(), id.to_le_bytes().as_ref()],
        bump,
    )]
    pub offer: Box<Account<'info, Offer>>,

    // The vault: an ATA for token A, owned/authorized by the Offer PDA.
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

    // The maker is not a signer here — the taker drives the trade — but we
    // need the account to refund rent and verify the offer's owner.
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

    // Taker receives token A here (created if they don't have an ATA yet).
    #[account(
        init_if_needed,
        payer = taker,
        associated_token::mint = token_a_mint,
        associated_token::authority = taker,
    )]
    pub taker_token_a: Box<Account<'info, TokenAccount>>,

    // Taker pays token B from here.
    #[account(
        mut,
        associated_token::mint = token_b_mint,
        associated_token::authority = taker,
    )]
    pub taker_token_b: Box<Account<'info, TokenAccount>>,

    // Maker receives token B here (created if needed).
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
}
