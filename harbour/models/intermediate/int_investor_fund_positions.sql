-- Grain: one row per investor per fund.
--
-- This is where commitments and cashflows meet for the first time. It
-- answers, for each investor in each fund: what did you promise, how
-- much has been called, how much came back, and what is still
-- outstanding.
--
-- Commitments are converted to USD at the rate on commitment_date - the
-- rate in force when the promise was signed. An alternative is to
-- revalue at today's rate, which some reporting does, but then the
-- unfunded figure moves with FX even when nothing happened. Fixing it at
-- signing keeps the contractual amount stable.
--
-- ownership_pct is pro-rata by commitment: an investor who committed
-- 50m to a 500m fund owns 10% of it. This is the standard simplifying
-- assumption for a model of this size, and it is what drives each
-- investor's share of portfolio NAV downstream.
--
-- Worth being able to say out loud what this simplification leaves out:
-- real ownership tracks CALLED capital rather than commitments, so an
-- investor who has been called 30% while another has been called 50%
-- does not own a commitment-weighted share. Management fees and carried
-- interest also take a cut before value reaches the investor. Neither is
-- modelled here.

with commitments as (
    select * from {{ ref('stg_commitments') }}
),

fx as (
    select * from {{ ref('stg_fx_rates') }}
),

cashflows as (
    select * from {{ ref('int_cashflows_usd') }}
),

commitments_usd as (
    select
        commitments.commitment_id,
        commitments.investor_id,
        commitments.fund_id,
        commitments.commitment_date,
        commitments.commitment_amount               as commitment_amount_original,
        commitments.commitment_currency,
        round(commitments.commitment_amount * fx.rate, 2) as commitment_amount_usd
    from commitments
    inner join fx
        on  commitments.commitment_currency = fx.from_currency
        and commitments.commitment_date     = fx.rate_date
        and fx.to_currency                  = 'USD'
),

cashflow_rollup as (
    select
        investor_id,
        fund_id,
        sum(case when cashflow_type = 'CAPITAL_CALL'
                 then amount_usd else 0 end)    as total_called_usd,
        sum(case when cashflow_type = 'DISTRIBUTION'
                 then amount_usd else 0 end)    as total_distributed_usd,
        count(case when cashflow_type = 'CAPITAL_CALL'
                   then 1 end)                  as capital_call_count,
        count(case when cashflow_type = 'DISTRIBUTION'
                   then 1 end)                  as distribution_count,
        min(effective_date)                     as first_cashflow_date,
        max(effective_date)                     as last_cashflow_date
    from cashflows
    group by investor_id, fund_id
),

combined as (
    select
        commitments_usd.commitment_id,
        commitments_usd.investor_id,
        commitments_usd.fund_id,
        commitments_usd.commitment_date,
        commitments_usd.commitment_currency,
        commitments_usd.commitment_amount_original,
        commitments_usd.commitment_amount_usd,

        coalesce(cashflow_rollup.total_called_usd, 0)       as total_called_usd,
        coalesce(cashflow_rollup.total_distributed_usd, 0)  as total_distributed_usd,
        coalesce(cashflow_rollup.capital_call_count, 0)     as capital_call_count,
        coalesce(cashflow_rollup.distribution_count, 0)     as distribution_count,
        cashflow_rollup.first_cashflow_date,
        cashflow_rollup.last_cashflow_date,

        -- Still owed under the commitment. Floored at zero because an
        -- over-call would be a data problem, not a negative obligation.
        greatest(
            commitments_usd.commitment_amount_usd
              - coalesce(cashflow_rollup.total_called_usd, 0)
        , 0)                                                as unfunded_commitment_usd,

        -- Share of the fund, used downstream to allocate portfolio NAV.
        commitments_usd.commitment_amount_usd
          / nullif(sum(commitments_usd.commitment_amount_usd)
                   over (partition by commitments_usd.fund_id), 0)
                                                            as ownership_pct

    from commitments_usd
    left join cashflow_rollup
        on  commitments_usd.investor_id = cashflow_rollup.investor_id
        and commitments_usd.fund_id     = cashflow_rollup.fund_id
)

select * from combined
