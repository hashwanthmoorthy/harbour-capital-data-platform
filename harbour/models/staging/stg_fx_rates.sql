-- Grain: one row per rate_date per currency pair.
--
-- The source includes USD -> USD at 1.0, so downstream conversion joins
-- need no coalesce or case for the base currency. Every amount joins the
-- same way regardless of its currency.
--
-- Rates are daily and dense across the full history. A cashflow dated on
-- a weekend or holiday will still find a rate; if that stops being true
-- for a new source, the fix is an as-of join to the most recent rate on
-- or before the date, not a left join with a null rate.

with source as (
    select * from {{ source('harbour_raw', 'raw_fx_rates') }}
),

renamed as (
    select
        rate_date,
        upper(trim(from_currency))  as from_currency,
        upper(trim(to_currency))    as to_currency,
        rate,
        _source_file,
        _loaded_ts
    from source
)

select * from renamed
