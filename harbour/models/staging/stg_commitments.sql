with source as (
    select * from {{ source('harbour_raw', 'raw_commitments') }}
),

renamed as (
    select
        commitment_id,
        investor_id,
        fund_id,
        commitment_amount,
        upper(trim(commitment_currency))    as commitment_currency,
        commitment_date,
        _source_file,
        _loaded_ts
    from source
)

select * from renamed
