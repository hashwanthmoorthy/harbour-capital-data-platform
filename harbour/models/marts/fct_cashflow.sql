{{
    config(
        materialized = 'incremental',
        unique_key = 'cashflow_id',
        incremental_strategy = 'merge',
        on_schema_change = 'append_new_columns'
    )
}}

-- Grain: one row per cashflow.
--
-- INCREMENTAL, and the interesting part is the filter at the bottom.
--
-- The naive incremental filter is "where effective_date > the max
-- effective_date I already have". That is WRONG here, and the data
-- proves it: around 4% of cashflows reach the warehouse days after the
-- date they apply to. A cashflow dated the 18th might arrive on the
-- 25th. By then the model's max effective_date is already past the
-- 18th, so the row is filtered out and never loads. It is missed
-- silently and permanently - no error, just a total that is quietly
-- short.
--
-- Two fixes, and this model uses both:
--
-- 1. Filter on loaded_at, not effective_date. loaded_at only ever moves
--    forwards, so nothing can arrive "behind" the watermark.
--
-- 2. Subtract a lookback window anyway. Reprocessing a few extra days
--    costs almost nothing and covers restated or re-sent rows whose
--    loaded_at did not advance as expected.
--
-- The window is sized from observed behaviour, not guessed: the
-- arrival_lag_days column in staging shows the real distribution of how
-- late rows arrive. 7 days covers it with room to spare. If the lag
-- distribution changed, the window should change with it.
--
-- merge strategy plus unique_key means a reprocessed row UPDATES rather
-- than duplicates, which is what makes the overlapping window safe.

with cashflows as (
    select * from {{ ref('int_cashflows_usd') }}
),

final as (
    select
        cashflow_id,
        investor_id,
        fund_id,
        cashflow_type,
        effective_date,

        amount_original,
        currency_original,
        fx_rate,
        amount_usd,
        signed_amount_usd,

        -- Quarter key, for joining to quarterly performance.
        to_char(effective_date, 'YYYY') || 'Q' ||
            to_char(quarter(effective_date))    as effective_quarter,

        loaded_at,
        arrival_lag_days,
        arrival_lag_days > 3                    as was_late_arriving,

        _source_file,
        _loaded_ts
    from cashflows

    {% if is_incremental() %}
    -- Only on incremental runs. On a full refresh this block is absent
    -- and everything is reprocessed.
    where loaded_at >= (
        select dateadd('day', -7, coalesce(max(loaded_at), '1900-01-01'))
        from {{ this }}
    )
    {% endif %}
)

select * from final
