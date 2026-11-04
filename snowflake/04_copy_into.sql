-- Harbour Capital: load raw tables from the S3 external stage
--
-- Pattern notes:
--   - COPY FROM (SELECT ...) rather than plain COPY, so we can append
--     metadata$ columns for load lineage.
--   - $1, $2 ... are positional columns in the staged file. Order must
--     match the CSV header order from the generator.
--   - ON_ERROR = ABORT_STATEMENT (the default) for well-formed sources:
--     we would rather fail loudly than load a partial file silently.
--   - COPY tracks loaded files for 64 days, so re-running this script
--     will not duplicate data unless FORCE = TRUE is set.

use role sysadmin;
use warehouse loading_wh;
use database harbour_dev;
use schema raw;


copy into raw_funds
from (
  select $1, $2, $3, $4, $5, $6, $7,
         metadata$filename, metadata$file_row_number, current_timestamp()
  from @harbour_raw_stage/funds/
)
file_format = (format_name = ff_csv);


copy into raw_investors
from (
  select $1, $2, $3, $4, $5, $6,
         metadata$filename, metadata$file_row_number, current_timestamp()
  from @harbour_raw_stage/investors/
)
file_format = (format_name = ff_csv);


copy into raw_commitments
from (
  select $1, $2, $3, $4, $5, $6,
         metadata$filename, metadata$file_row_number, current_timestamp()
  from @harbour_raw_stage/commitments/
)
file_format = (format_name = ff_csv);


copy into raw_cashflows
from (
  select $1, $2, $3, $4, $5, $6, $7, $8,
         metadata$filename, metadata$file_row_number, current_timestamp()
  from @harbour_raw_stage/cashflows/
)
file_format = (format_name = ff_csv);


copy into raw_portfolio_companies
from (
  select $1, $2, $3, $4, $5, $6, $7,
         metadata$filename, metadata$file_row_number, current_timestamp()
  from @harbour_raw_stage/portfolio_companies/
)
file_format = (format_name = ff_csv);


copy into raw_valuations
from (
  select $1, $2, $3, $4, $5, $6, $7,
         metadata$filename, metadata$file_row_number, current_timestamp()
  from @harbour_raw_stage/valuations/
)
file_format = (format_name = ff_csv);


copy into raw_fx_rates
from (
  select $1, $2, $3, $4,
         metadata$filename, metadata$file_row_number, current_timestamp()
  from @harbour_raw_stage/fx_rates/
)
file_format = (format_name = ff_csv);


-- JSON lands whole into a VARIANT column and is flattened in staging.
copy into raw_company_kpis
from (
  select $1, metadata$filename, current_timestamp()
  from @harbour_raw_stage/company_kpis/
)
file_format = (format_name = ff_json);