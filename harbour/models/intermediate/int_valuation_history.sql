-- Grain: one row per valuation VERSION, with the date range over which
-- that version was the firm's current view.
--
-- This is SCD2 history derived from the data rather than captured by a
-- dbt snapshot. The restatements already exist in the source, both
-- versions loaded together, so a snapshot would never witness a change
-- and would record only the latest version of each valuation.
--
-- reported_at tells us when each version became current, which is all
-- the information a snapshot would have recorded anyway. The window
-- function below reconstructs the same ranges.
--
-- valid_to is the next version's reported_at, or null if this is the
-- version still standing. Ranges are half-open: valid_from inclusive,
-- valid_to exclusive, so a point-in-time filter can never match two
-- versions of the same valuation.

with valuations as (
    select * from {{ ref('stg_valuations') }}
),

versioned as (
    select
        valuation_id,
        company_id,
        valuation_quarter,
        valuation_date,
        nav_amount,
        currency,
        reported_at                 as valid_from,

        lead(reported_at) over (
            partition by valuation_id
            order by reported_at
        )                           as valid_to,

        row_number() over (
            partition by valuation_id
            order by reported_at
        )                           as version_number,

        count(*) over (
            partition by valuation_id
        )                           as total_versions,

        _source_file,
        _loaded_ts
    from valuations
),

final as (
    select
        *,
        valid_to is null                as is_current_version,
        total_versions > 1              as was_restated
    from versioned
)

select * from final
