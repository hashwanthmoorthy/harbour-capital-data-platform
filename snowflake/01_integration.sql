-- Harbour Capital: S3 storage integration
-- Run as ACCOUNTADMIN.
--
-- MANUAL STEP REQUIRED:
--   1. Create IAM role snowflake_harbour_role in AWS with a read-only
--      policy on s3://harbour-capital-raw-hashwanth/raw/*
--   2. Run the CREATE STORAGE INTEGRATION below.
--   3. Run DESC INTEGRATION harbour_s3_int.
--   4. Paste STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID
--      into the IAM role's trust policy (see README).
--
-- No AWS keys are stored in Snowflake. Access is via STS role
-- assumption, protected by an external ID.

use role accountadmin;

create or replace storage integration harbour_s3_int
  type = external_stage
  storage_provider = 'S3'
  enabled = true
  storage_aws_role_arn = 'arn:aws:iam::654654538132:role/snowflake_harbour_role'
  storage_allowed_locations = ('s3://harbour-capital-raw-hashwanth/raw/');

desc integration harbour_s3_int;

grant usage on integration harbour_s3_int to role sysadmin;