-- Grain: one row per investor.
--
-- tax_id is carried through so a masking policy can be applied to the
-- column. The policy lives in Snowflake, not in dbt - masking is a
-- security control and belongs where it cannot be bypassed by writing a
-- different query.

with investors as (
    select * from {{ ref('stg_investors') }}
),

fund_counts as (
    select
        investor_id,
        count(distinct fund_id) as funds_invested_in
    from {{ ref('int_investor_fund_positions') }}
    group by investor_id
),

final as (
    select
        investors.investor_id,
        investors.investor_name,
        investors.investor_type,
        investors.domicile_country,
        investors.tax_id,
        investors.onboarded_date,

        -- Null rather than 'Unknown'. A null is honestly absent; a
        -- string sentinel looks like data and will eventually be
        -- grouped by, counted and reported as if it meant something.
        case
            when investors.domicile_country is null then false
            else true
        end                                     as has_domicile,

        coalesce(fund_counts.funds_invested_in, 0)
                                                as funds_invested_in
    from investors
    left join fund_counts
        on investors.investor_id = fund_counts.investor_id
)

select * from final
