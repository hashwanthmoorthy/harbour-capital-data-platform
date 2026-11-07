with source as (
    select * from {{ source('harbour_raw', 'raw_investors') }}
),

renamed as (
    select
        investor_id,
        trim(investor_name)                     as investor_name,
        trim(investor_type)                     as investor_type,
        nullif(upper(trim(domicile_country)), '') as domicile_country,
        tax_id,
        onboarded_date,
        _source_file,
        _loaded_ts
    from source
)

select * from renamed
