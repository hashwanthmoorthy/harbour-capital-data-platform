
-- Harbour Capital: database, schemas and warehouses
-- Run as SYSADMIN. Idempotent - safe to re-run.

use role sysadmin;

create database if not exists harbour_dev;

create schema if not exists harbour_dev.raw;
create schema if not exists harbour_dev.marts;

-- Staging and intermediate are fully rebuildable from raw,
-- so they are transient: no Fail-safe, 1 day Time Travel.
create transient schema if not exists harbour_dev.staging;
create transient schema if not exists harbour_dev.intermediate;

create warehouse if not exists loading_wh
  warehouse_size = 'XSMALL'
  auto_suspend = 60
  auto_resume = true
  initially_suspended = true;

create warehouse if not exists transform_wh
  warehouse_size = 'XSMALL'
  auto_suspend = 60
  auto_resume = true
  initially_suspended = true;