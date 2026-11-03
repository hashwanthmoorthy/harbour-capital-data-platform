-- Harbour Capital: raw landing tables
--
-- Design notes:
--   - Permissive typing. A bad value in one column should not fail
--     the whole file; types are enforced in staging instead.
--   - Every table carries load lineage: _source_file, _file_row,
--     _loaded_ts. Answers "where did this row come from?" later.

use role sysadmin;
use database harbour_dev;
use schema raw;

create or replace table raw_funds (
  fund_id          varchar,
  fund_name        varchar,
  strategy         varchar,
  vintage_year     number,
  fund_currency    varchar,
  target_size_musd number,
  first_close_date date,
  _source_file     varchar,
  _file_row        number,
  _loaded_ts       timestamp_ntz
);

create or replace table raw_investors (
  investor_id      varchar,
  investor_name    varchar,
  investor_type    varchar,
  domicile_country varchar,
  tax_id           varchar,
  onboarded_date   date,
  _source_file     varchar,
  _file_row        number,
  _loaded_ts       timestamp_ntz
);

create or replace table raw_commitments (
  commitment_id       varchar,
  investor_id         varchar,
  fund_id             varchar,
  commitment_amount   number(18,2),
  commitment_currency varchar,
  commitment_date     date,
  _source_file        varchar,
  _file_row           number,
  _loaded_ts          timestamp_ntz
);

create or replace table raw_cashflows (
  cashflow_id    varchar,
  investor_id    varchar,
  fund_id        varchar,
  cashflow_type  varchar,
  effective_date date,
  amount         number(18,2),
  currency       varchar,
  loaded_at      date,
  _source_file   varchar,
  _file_row      number,
  _loaded_ts     timestamp_ntz
);

create or replace table raw_portfolio_companies (
  company_id   varchar,
  company_name varchar,
  fund_id      varchar,
  sector       varchar,
  country      varchar,
  entry_date   date,
  entry_cost   number(18,2),
  _source_file varchar,
  _file_row    number,
  _loaded_ts   timestamp_ntz
);

-- Note: raw grain is one row per valuation VERSION, not per valuation.
-- Restatements arrive as a second row with the same valuation_id and a
-- later reported_at. Both are kept - see README.
create or replace table raw_valuations (
  valuation_id      varchar,
  company_id        varchar,
  valuation_quarter varchar,
  valuation_date    date,
  nav_amount        number(18,2),
  currency          varchar,
  reported_at       date,
  _source_file      varchar,
  _file_row         number,
  _loaded_ts        timestamp_ntz
);

create or replace table raw_fx_rates (
  rate_date     date,
  from_currency varchar,
  to_currency   varchar,
  rate          number(18,6),
  _source_file  varchar,
  _file_row     number,
  _loaded_ts    timestamp_ntz
);

create or replace table raw_company_kpis (
  payload      variant,
  _source_file varchar,
  _loaded_ts   timestamp_ntz
);

show tables in schema harbour_dev.raw;