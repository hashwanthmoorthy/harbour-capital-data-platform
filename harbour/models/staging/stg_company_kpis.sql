-- Grain: one row per company per reporting period.
--
-- raw_company_kpis holds one VARIANT document per company. The metrics
-- array is flattened with LATERAL FLATTEN, which turns each array element
-- into its own row while keeping the parent document's columns alongside.
--
-- company_name here is the KPI pack's own spelling, and roughly 10% are
-- abbreviated relative to raw_portfolio_companies. Deliberately NOT
-- reconciled here: joining on company_id is correct, and the name
-- mismatch is kept visible so it can be demonstrated rather than quietly
-- papered over. Never join these two sources on name.

with source as (
    select * from {{ source('harbour_raw', 'raw_company_kpis') }}
),

flattened as (
    select
        source.payload:company_id::varchar                  as company_id,
        trim(source.payload:company_name::varchar)          as kpi_company_name,
        source.payload:reporting.frequency::varchar         as reporting_frequency,
        source.payload:reporting.last_submitted::date       as last_submitted_date,
        upper(trim(m.value:period::varchar))                as reporting_period,
        m.value:revenue::number(18,2)                       as revenue,
        m.value:ebitda_margin::number(9,4)                  as ebitda_margin,
        m.value:headcount::number                           as headcount,
        source._source_file,
        source._loaded_ts
    from source,
         lateral flatten(input => source.payload:metrics) as m
)

select * from flattened
