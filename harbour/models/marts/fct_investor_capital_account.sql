-- Grain: one row per investor per fund.
--
-- The headline table: what every investor's position is worth today.
--
-- Current NAV is built in three steps. First, take the valuation
-- version that stands TODAY for each company - that is is_current_version
-- from the SCD2 history, which is why the history model exists. Second,
-- keep only each company's most recent quarter. Third, sum to fund level
-- and allocate to investors by ownership_pct.
--
-- Note what the first step buys: because NAV comes from the history
-- model rather than the raw table, the same logic with a date filter
-- produces the capital account AS AT any past date. Restatements are
-- handled by construction, not by a special case.
--
-- NAV is converted to USD at TODAY's rate, not the valuation date's.
-- This is a real choice and differs from the cashflow treatment:
-- cashflows are historical events fixed at the rate when they happened,
-- while NAV is a current estimate of present worth, so it converts at
-- the current rate. Mixing the two up is a common error.

with positions as (
    select * from {{ ref('int_investor_fund_positions') }}
),

current_valuations as (
    select
        company_id,
        valuation_quarter,
        nav_amount,
        currency
    from {{ ref('int_valuation_history') }}
    where is_current_version
    qualify row_number() over (
        partition by company_id
        order by valuation_quarter desc
    ) = 1
),

latest_fx as (
    select
        from_currency,
        rate
    from {{ ref('stg_fx_rates') }}
    where to_currency = 'USD'
    qualify row_number() over (
        partition by from_currency
        order by rate_date desc
    ) = 1
),

fund_nav as (
    select
        companies.fund_id,
        sum(current_valuations.nav_amount * latest_fx.rate) as fund_nav_usd,
        count(*)                                           as companies_valued
    from current_valuations
    inner join {{ ref('stg_portfolio_companies') }} as companies
        on current_valuations.company_id = companies.company_id
    inner join latest_fx
        on current_valuations.currency = latest_fx.from_currency
    group by companies.fund_id
),

final as (
    select
        positions.investor_id,
        positions.fund_id,

        positions.commitment_amount_usd,
        positions.total_called_usd,
        positions.total_distributed_usd,
        positions.unfunded_commitment_usd,
        positions.ownership_pct,

        round(coalesce(fund_nav.fund_nav_usd, 0)
              * positions.ownership_pct, 2)         as current_value_usd,

        -- DPI: Distributions to Paid-In. Cash actually returned per
        -- dollar called. Below 1.0 means the investor is still down on
        -- a cash basis, which is normal for a young fund.
        round(
            positions.total_distributed_usd
            / nullif(positions.total_called_usd, 0)
        , 4)                                        as dpi,

        -- TVPI: Total Value to Paid-In. Cash returned PLUS what the
        -- remaining stake is estimated to be worth, per dollar called.
        -- Part realised, part estimate - which is exactly why the NAV
        -- behind it has to be defensible.
        round(
            (positions.total_distributed_usd
             + coalesce(fund_nav.fund_nav_usd, 0) * positions.ownership_pct)
            / nullif(positions.total_called_usd, 0)
        , 4)                                        as tvpi,

        -- How much of the promise has actually been drawn.
        round(
            positions.total_called_usd
            / nullif(positions.commitment_amount_usd, 0)
        , 4)                                        as called_pct,

        positions.capital_call_count,
        positions.distribution_count,
        positions.first_cashflow_date,
        positions.last_cashflow_date,
        fund_nav.companies_valued,

        current_timestamp()                         as calculated_at
    from positions
    left join fund_nav
        on positions.fund_id = fund_nav.fund_id
)

select * from final
