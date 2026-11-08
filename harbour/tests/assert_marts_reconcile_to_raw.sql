-- RECONCILIATION TEST
--
-- The most important test in the project. Everything else checks a
-- property of one model; this one checks that four layers of
-- transformation did not lose or invent money.
--
-- It compares total called and distributed in the mart against the same
-- totals computed independently from the RAW table, deduplicated inline
-- and converted with the same FX join. If a model drops rows, double
-- counts a join, or converts at the wrong rate, the totals diverge and
-- this fails.
--
-- Tolerance is one dollar, to absorb rounding across ~1,400 rows each
-- rounded to cents. A real divergence will be far larger than a dollar;
-- a tolerance of zero would fail on arithmetic noise and teach everyone
-- to ignore the test.
--
-- Returns a row describing the mismatch, so a failure says what is
-- wrong rather than merely that something is.

with raw_deduplicated as (
    select
        cashflow_type,
        effective_date,
        amount,
        currency
    from {{ source('harbour_raw', 'raw_cashflows') }}
    qualify row_number() over (
        partition by cashflow_id
        order by loaded_at desc
    ) = 1
),

raw_totals as (
    select
        sum(case when raw_deduplicated.cashflow_type = 'CAPITAL_CALL'
                 then raw_deduplicated.amount * fx.rate else 0 end) as called_usd,
        sum(case when raw_deduplicated.cashflow_type = 'DISTRIBUTION'
                 then raw_deduplicated.amount * fx.rate else 0 end) as distributed_usd
    from raw_deduplicated
    inner join {{ ref('stg_fx_rates') }} as fx
        on  upper(trim(raw_deduplicated.currency)) = fx.from_currency
        and raw_deduplicated.effective_date        = fx.rate_date
        and fx.to_currency                         = 'USD'
),

mart_totals as (
    select
        sum(total_called_usd)       as called_usd,
        sum(total_distributed_usd)  as distributed_usd
    from {{ ref('fct_investor_capital_account') }}
),

comparison as (
    select
        'called' as measure,
        raw_totals.called_usd   as raw_value,
        mart_totals.called_usd  as mart_value,
        abs(raw_totals.called_usd - mart_totals.called_usd) as difference
    from raw_totals, mart_totals

    union all

    select
        'distributed',
        raw_totals.distributed_usd,
        mart_totals.distributed_usd,
        abs(raw_totals.distributed_usd - mart_totals.distributed_usd)
    from raw_totals, mart_totals
)

select * from comparison
where difference > 1
