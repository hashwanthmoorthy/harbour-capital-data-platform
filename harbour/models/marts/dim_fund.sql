-- Grain: one row per fund.
--
-- Dimensions carry descriptive attributes, not measures. Committed and
-- called totals live in the fact tables, not here - otherwise the same
-- number exists in two places and they drift.

with funds as (
    select * from {{ ref('stg_funds') }}
),

companies as (
    select
        fund_id,
        count(*)            as portfolio_company_count,
        min(entry_date)     as first_investment_date,
        sum(entry_cost)     as total_entry_cost
    from {{ ref('stg_portfolio_companies') }}
    group by fund_id
),

final as (
    select
        funds.fund_id,
        funds.fund_name,
        funds.strategy,
        funds.vintage_year,
        funds.fund_currency,
        funds.target_size,
        funds.first_close_date,

        -- Fund age in years, a standard grouping for performance
        -- comparison. A 2016 fund and a 2022 fund are not comparable.
        datediff('year', funds.first_close_date, current_date())
                                        as fund_age_years,

        coalesce(companies.portfolio_company_count, 0)
                                        as portfolio_company_count,
        companies.first_investment_date,
        companies.total_entry_cost
    from funds
    left join companies
        on funds.fund_id = companies.fund_id
)

select * from final
