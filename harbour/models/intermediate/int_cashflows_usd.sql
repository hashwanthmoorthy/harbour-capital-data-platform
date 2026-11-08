-- Grain: one row per cashflow_id. Same as stg_cashflows - this model
-- adds columns, it does not change the grain.
--
-- Every amount is converted to USD so that funds in three currencies can
-- be summed together.
--
-- FX is joined on effective_date, not loaded_at. The rate that matters
-- is the one on the day the cashflow applied, not the day it happened to
-- reach the warehouse. Using loaded_at would make a late-arriving row
-- convert at a different rate from an identical row that arrived on
-- time, which would be indefensible to an auditor.
--
-- The join is an inner join, which is a deliberate choice: fx_rates is
-- dense across every date in the range including weekends, so a missing
-- rate would mean something is genuinely wrong rather than merely
-- absent. Failing loudly beats silently producing nulls. If the FX
-- source ever became sparse, the fix is an as-of join to the most recent
-- rate on or before the date - not a left join.
--
-- USD rows convert at 1.0 because the source includes USD -> USD, so no
-- coalesce or case is needed for the base currency.

with cashflows as (
    select * from {{ ref('stg_cashflows') }}
),

fx as (
    select * from {{ ref('stg_fx_rates') }}
),

converted as (
    select
        cashflows.cashflow_id,
        cashflows.investor_id,
        cashflows.fund_id,
        cashflows.cashflow_type,
        cashflows.effective_date,

        cashflows.amount                        as amount_original,
        cashflows.currency                      as currency_original,
        fx.rate                                 as fx_rate,
        round(cashflows.amount * fx.rate, 2)    as amount_usd,

        -- Signed amount: calls are money leaving the investor, so they
        -- are negative from the investor's point of view. Makes net
        -- position a simple sum downstream.
        round(
            case
                when cashflows.cashflow_type = 'CAPITAL_CALL'
                    then -1 * cashflows.amount * fx.rate
                else cashflows.amount * fx.rate
            end
        , 2)                                    as signed_amount_usd,

        cashflows.loaded_at,
        cashflows.arrival_lag_days,
        cashflows._source_file,
        cashflows._loaded_ts
    from cashflows
    inner join fx
        on  cashflows.currency      = fx.from_currency
        and cashflows.effective_date = fx.rate_date
        and fx.to_currency           = 'USD'
)

select * from converted
