# Harbour Capital — private markets data platform

A Snowflake + dbt pipeline over synthetic private equity fund data:
commitments, capital calls, distributions, portfolio valuations and FX.

All data is synthetic and generated locally. No real or client data is used.

## Quickstart

    python scripts/generate_harbour_data.py --out ./data --seed 42

## Status

- [x] Synthetic data generator
- [ ] S3 landing + Snowflake external stage
- [ ] dbt staging layer
- [ ] Marts and SCD2 valuation snapshot
- [ ] Tests, CI, cost notes