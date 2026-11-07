-- Every valuation must have exactly one version with no end date.
-- Zero would mean history with no present; two would mean overlapping
-- ranges and a point-in-time query that returns duplicates.
--
-- Returns the offending valuation_ids, so a failure names the problem.

select
    valuation_id,
    count(*) as current_versions
from {{ ref('int_valuation_history') }}
where valid_to is null
group by valuation_id
having count(*) <> 1
