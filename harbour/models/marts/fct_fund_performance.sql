-- Grain: one row per fund per quarter.
--
-- The fund-level view, and a time series rather than a snapshot, so you
-- can see DPI and TVPI develop over a fund's life.
--
-- Cashflow figures are CUMULATIVE as at each quarter end - that is what
-- the running sums do. DPI at 2020Q2 means distributions to that point
-- divided by calls to that point, which is how the measure is defined.
-- Using only that quarter's cashflows would produce a meaningless
-- number that swings wildly.
--
-- NAV uses the valuation version current as at that quarter's reporting
-- date, not today's version. So a restated quarter shows the figure
-- Harbour published at the time. This is the point-in-time property of
-- the history model doing real work: the series is reproducible, and
-- a report run today for 2020Q2 matches the one run in 2020.

with cashflows as (
    select
        fund_id,
        effective_quarter,
        sum(case when cashflow_type = 'CAPITAL_CALL'
                 then amount_usd else 0 end)    as called_usd,
        sum(case when cashflow_type = 'DISTRIBUTION'
                 then amount_usd else 0 end)    as distributed_usd
    from {{ ref('fct_cashflow') }}
    group by fund_id, effective_quarter
),

quarterly_nav as (
    select
        companies.fund_id,
        history.valuation_quarter,
        sum(history.nav_amount)     as fund_nav_original_ccy,
        count(*)                    as companies_valued
    from {{ ref('int_valuation_history') }} as history
    inner join {{ ref('stg_portfolio_companies') }} as companies
        on history.company_id = companies.company_id
    -- The version that was current when this quarter was reported.
    -- For an unrestated quarter there is only one version anyway.
    where history.version_number = 1
    group by companies.fund_id, history.valuation_quarter
),

-- Every fund-quarter combination that appears in either source, so a
-- quarter with valuations but no cashflows still gets a row.
spine as (
    select fund_id, effective_quarter as quarter from cashflows
    union
    select fund_id, valuation_quarter as quarter from quarterly_nav
),

combined as (
    select
        spine.fund_id,
        spine.quarter,
        coalesce(cashflows.called_usd, 0)       as called_this_quarter_usd,
        coalesce(cashflows.distributed_usd, 0)  as distributed_this_quarter_usd,
        quarterly_nav.fund_nav_original_ccy     as fund_nav_usd,
        quarterly_nav.companies_valued
    from spine
    left join cashflows
        on  spine.fund_id = cashflows.fund_id
        and spine.quarter = cashflows.effective_quarter
    left join quarterly_nav
        on  spine.fund_id = quarterly_nav.fund_id
        and spine.quarter = quarterly_nav.valuation_quarter
),

cumulative as (
    select
        *,
        sum(called_this_quarter_usd) over (
            partition by fund_id order by quarter
            rows between unbounded preceding and current row
        )                                       as cumulative_called_usd,
        sum(distributed_this_quarter_usd) over (
            partition by fund_id order by quarter
            rows between unbounded preceding and current row
        )                                       as cumulative_distributed_usd
    from combined
),

final as (
    select
        fund_id,
        quarter,
        called_this_quarter_usd,
        distributed_this_quarter_usd,
        cumulative_called_usd,
        cumulative_distributed_usd,
        fund_nav_usd,
        companies_valued,

        round(
            cumulative_distributed_usd
            / nullif(cumulative_called_usd, 0)
        , 4)                                    as dpi,

        round(
            (cumulative_distributed_usd + coalesce(fund_nav_usd, 0))
            / nullif(cumulative_called_usd, 0)
        , 4)                                    as tvpi,

        -- RVPI: the unrealised half of TVPI. TVPI minus DPI, in effect.
        round(
            coalesce(fund_nav_usd, 0)
            / nullif(cumulative_called_usd, 0)
        , 4)                                    as rvpi
    from cumulative
)

select * from final
