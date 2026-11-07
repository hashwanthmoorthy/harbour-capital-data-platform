-- Grain: one row per valuation VERSION.
--
-- DO NOT DEDUPLICATE. A restated NAV arrives as a second row with the
-- same valuation_id and a later reported_at. Both versions are the point
-- of this project: the snapshot in snapshots/ turns them into SCD2
-- history, and collapsing them here would destroy exactly the thing we
-- want to demonstrate.
--
-- 18 of the 620 valuations currently carry a restatement.
--
-- "Which version was current as at date X" is a point-in-time question
-- and belongs in the intermediate layer, not here.

with source as (
    select * from {{ source('harbour_raw', 'raw_valuations') }}
),

renamed as (
    select
        valuation_id,
        company_id,
        upper(trim(valuation_quarter))  as valuation_quarter,
        valuation_date,
        nav_amount,
        upper(trim(currency))           as currency,
        reported_at,
        _source_file,
        _loaded_ts
    from source
)

select * from renamed
