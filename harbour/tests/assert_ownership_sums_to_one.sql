-- Every fund's investor ownership shares must sum to 1.
--
-- Tolerance of 0.000001 absorbs floating point drift across 45
-- investors. Anything larger means a commitment went missing from the
-- window partition, which would silently understate or overstate every
-- investor's NAV share downstream.
--
-- Returns the offending fund_ids with their actual total.

select
    fund_id,
    sum(ownership_pct) as total_ownership
from {{ ref('int_investor_fund_positions') }}
group by fund_id
having abs(sum(ownership_pct) - 1) > 0.000001
