-- Harbour Capital: file formats and external stage

use role sysadmin;
use warehouse transform_wh;
use database harbour_dev;
use schema raw;

create or replace file format ff_csv
  type = csv
  field_delimiter = ','
  skip_header = 1
  field_optionally_enclosed_by = '"'
  null_if = ('', 'NULL', 'null')
  empty_field_as_null = true
  trim_space = true;

-- Generator writes newline-delimited JSON (one object per line),
-- not a single array, so no outer array to strip.
create or replace file format ff_json
  type = json
  strip_outer_array = false;

create or replace stage harbour_raw_stage
  storage_integration = harbour_s3_int
  url = 's3://harbour-capital-raw-hashwanth/raw/';

list @harbour_raw_stage;