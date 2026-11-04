with source as (
    select * from {{ source('harbour_raw', 'raw_funds') }}
),

renamed as (
    select
        fund_id,
        fund_name,
        strategy,
        vintage_year,
        upper(trim(fund_currency))  as fund_currency,
        target_size_musd * 1000000  as target_size,
        first_close_date,
        _source_file,
        _loaded_ts
    from source
)

select * from renamed