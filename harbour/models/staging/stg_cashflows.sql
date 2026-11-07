-- Grain: one row per cashflow_id.
--
-- raw_cashflows contains a simulated partial double-load: 25 cashflow_ids
-- appear twice with differing loaded_at. We keep the most recently loaded
-- version, which is the conventional "latest wins" rule and the one that
-- survives a genuine restatement of the row's contents.
--
-- Worth knowing the trade-off: if the duplicate is a pure double-load
-- rather than a correction, the EARLIEST loaded_at is the truthful
-- arrival date, and keeping the latest slightly overstates how late the
-- row reached the warehouse. That matters only for lookback-window
-- tuning downstream, not for the amounts.

with source as (
    select * from {{ source('harbour_raw', 'raw_cashflows') }}
),

renamed as (
    select
        cashflow_id,
        investor_id,
        fund_id,
        upper(trim(cashflow_type))      as cashflow_type,
        effective_date,
        amount,
        upper(trim(currency))           as currency,
        loaded_at,
        datediff('day', effective_date, loaded_at) as arrival_lag_days,
        _source_file,
        _loaded_ts
    from source
),

deduplicated as (
    select *
    from renamed
    qualify row_number() over (
        partition by cashflow_id
        order by loaded_at desc, _loaded_ts desc
    ) = 1
)

select * from deduplicated
