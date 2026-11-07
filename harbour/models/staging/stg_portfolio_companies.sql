with source as (
    select * from {{ source('harbour_raw', 'raw_portfolio_companies') }}
),

renamed as (
    select
        company_id,
        trim(company_name)              as company_name,
        fund_id,
        trim(sector)                    as sector,
        nullif(upper(trim(country)), '') as country,
        entry_date,
        entry_cost,
        _source_file,
        _loaded_ts
    from source
)

select * from renamed
