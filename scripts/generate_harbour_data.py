#!/usr/bin/env python3
"""
Harbour Capital - synthetic private markets dataset generator.

Produces CSV/JSON files for a Snowflake + dbt portfolio project.
Standard library only - no pip install required.

Usage:
    python generate_harbour_data.py            # writes to ./data
    python generate_harbour_data.py --out /tmp/data --seed 7
"""

import argparse
import csv
import json
import os
import random
from datetime import date, timedelta

# ----------------------------------------------------------------------
# Reference data
# ----------------------------------------------------------------------

STRATEGIES = ["Buyout", "Growth", "Real Estate", "Infrastructure", "Credit"]
INVESTOR_TYPES = ["Pension", "Endowment", "Sovereign Wealth", "Family Office",
                  "Insurance", "Fund of Funds"]
DOMICILES = ["US", "GB", "DE", "FR", "SG", "CA", "AE", "JP", "NL", "AU"]
SECTORS = ["Technology", "Healthcare", "Industrials", "Consumer",
           "Financial Services", "Energy", "Business Services"]
CURRENCIES = ["USD", "EUR", "GBP"]

FUNDS = [
    # (fund_id, name, strategy, vintage, currency, target_size_m)
    ("FUND001", "Harbour Capital Partners I",      "Buyout",         2016, "USD", 1200),
    ("FUND002", "Harbour Capital Partners II",     "Buyout",         2019, "USD", 2400),
    ("FUND003", "Harbour Growth Equity I",         "Growth",         2018, "USD",  800),
    ("FUND004", "Harbour European Real Assets I",  "Real Estate",    2020, "EUR",  950),
    ("FUND005", "Harbour Infrastructure Fund I",   "Infrastructure", 2021, "GBP",  700),
    ("FUND006", "Harbour Credit Opportunities I",  "Credit",         2022, "USD", 1500),
]

QUARTER_ENDS = []
for _y in range(2016, 2026):
    for _m, _d in ((3, 31), (6, 30), (9, 30), (12, 31)):
        QUARTER_ENDS.append(date(_y, _m, _d))


def quarter_label(d):
    return "%dQ%d" % (d.year, (d.month - 1) // 3 + 1)


# ----------------------------------------------------------------------
# Generators
# ----------------------------------------------------------------------

def gen_funds():
    rows = []
    for fid, name, strat, vintage, ccy, target in FUNDS:
        rows.append({
            "fund_id": fid,
            "fund_name": name,
            "strategy": strat,
            "vintage_year": vintage,
            "fund_currency": ccy,
            "target_size_musd": target,
            "first_close_date": date(vintage, random.choice([1, 3, 6]), 15).isoformat(),
        })
    return rows


def gen_investors(n):
    rows = []
    for i in range(1, n + 1):
        domicile = random.choice(DOMICILES)
        # deliberate nulls: ~8% missing domicile
        if random.random() < 0.08:
            domicile = ""
        rows.append({
            "investor_id": "LP%04d" % i,
            "investor_name": "%s %s" % (
                random.choice(["Northgate", "Redwood", "Castleford", "Kestrel",
                               "Brightwater", "Stonebridge", "Lakeside", "Arden",
                               "Whitfield", "Merrow", "Calder", "Pemberton"]),
                random.choice(["Pension Trust", "Endowment Fund", "Capital",
                               "Investments", "Holdings", "Asset Management"]),
            ),
            "investor_type": random.choice(INVESTOR_TYPES),
            "domicile_country": domicile,
            "tax_id": "TX-%s-%06d" % (domicile or "XX", random.randint(1, 999999)),
            "onboarded_date": (date(2015, 1, 1)
                               + timedelta(days=random.randint(0, 3000))).isoformat(),
        })
    return rows


def gen_commitments(investors, funds):
    rows = []
    cid = 0
    for inv in investors:
        for fund in random.sample(funds, random.randint(1, 3)):
            cid += 1
            amount = random.choice([5, 10, 15, 20, 25, 40, 50, 75, 100]) * 1_000_000
            rows.append({
                "commitment_id": "CM%05d" % cid,
                "investor_id": inv["investor_id"],
                "fund_id": fund["fund_id"],
                "commitment_amount": amount,
                "commitment_currency": fund["fund_currency"],
                "commitment_date": fund["first_close_date"],
            })
    return rows


def gen_cashflows(commitments, funds):
    """Capital calls and distributions, pro-rata to commitment."""
    fund_by_id = {f["fund_id"]: f for f in funds}
    rows = []
    cf = 0

    for c in commitments:
        fund = fund_by_id[c["fund_id"]]
        start = date.fromisoformat(c["commitment_date"])
        quarters = [q for q in QUARTER_ENDS if q > start and q <= date(2025, 12, 31)]

        called_pct = 0.0
        for idx, q in enumerate(quarters):
            # Capital calls front-loaded over the first ~5 years
            if called_pct < 0.92 and random.random() < 0.55:
                pct = round(random.uniform(0.03, 0.12), 4)
                pct = min(pct, 0.95 - called_pct)
                if pct > 0.005:
                    called_pct += pct
                    cf += 1
                    effective = q - timedelta(days=random.randint(0, 20))
                    # ~4% arrive late relative to their effective date
                    late = random.random() < 0.04
                    loaded = (effective + timedelta(days=random.randint(5, 12))
                              if late else effective + timedelta(days=1))
                    rows.append({
                        "cashflow_id": "CF%07d" % cf,
                        "investor_id": c["investor_id"],
                        "fund_id": c["fund_id"],
                        "cashflow_type": "CAPITAL_CALL",
                        "effective_date": effective.isoformat(),
                        "amount": round(c["commitment_amount"] * pct, 2),
                        "currency": fund["fund_currency"],
                        "loaded_at": loaded.isoformat(),
                    })

            # Distributions begin roughly 3 years in
            if idx > 11 and random.random() < 0.30:
                cf += 1
                effective = q - timedelta(days=random.randint(0, 20))
                rows.append({
                    "cashflow_id": "CF%07d" % cf,
                    "investor_id": c["investor_id"],
                    "fund_id": c["fund_id"],
                    "cashflow_type": "DISTRIBUTION",
                    "effective_date": effective.isoformat(),
                    "amount": round(c["commitment_amount"]
                                    * random.uniform(0.02, 0.15), 2),
                    "currency": fund["fund_currency"],
                    "loaded_at": (effective + timedelta(days=1)).isoformat(),
                })

    # Deliberate dirt: simulate a partial double-load of one batch.
    dupes = random.sample(rows, min(25, len(rows)))
    for d in dupes:
        copy = dict(d)
        copy["loaded_at"] = (date.fromisoformat(d["loaded_at"])
                             + timedelta(days=1)).isoformat()
        rows.append(copy)

    random.shuffle(rows)
    return rows


def gen_portfolio_companies(funds, n):
    rows = []
    names = ["Avonmere", "Birchall", "Calderwood", "Dunmore", "Eastvale",
             "Fairhaven", "Glenmore", "Hartley", "Ingleby", "Jarrow",
             "Kinnaird", "Lyndhurst", "Marchwood", "Netherby", "Oakfield",
             "Pendleton", "Quarrington", "Rosslyn", "Southwell", "Thorndale",
             "Underwood", "Vexley", "Westbury", "Yarrow", "Zennor",
             "Alderney", "Brackley", "Chevington", "Dalmore", "Ellesmere"]
    for i in range(n):
        fund = random.choice(funds)
        vintage = fund["vintage_year"]
        rows.append({
            "company_id": "PC%04d" % (i + 1),
            "company_name": "%s %s" % (names[i % len(names)],
                                       random.choice(["Group", "Holdings",
                                                      "Technologies", "Systems",
                                                      "Industries"])),
            "fund_id": fund["fund_id"],
            "sector": random.choice(SECTORS),
            "country": random.choice(DOMICILES),
            "entry_date": date(vintage + random.randint(0, 3),
                               random.randint(1, 12), 15).isoformat(),
            "entry_cost": round(random.uniform(20, 400) * 1_000_000, 2),
        })
    return rows


def gen_valuations(companies):
    """Quarterly NAV per company, with some quarters restated later."""
    rows = []
    vid = 0
    for c in companies:
        entry = date.fromisoformat(c["entry_date"])
        quarters = [q for q in QUARTER_ENDS
                    if q > entry and q <= date(2025, 9, 30)]
        value = c["entry_cost"]
        for q in quarters:
            value *= random.uniform(0.95, 1.14)
            vid += 1
            rows.append({
                "valuation_id": "VAL%06d" % vid,
                "company_id": c["company_id"],
                "valuation_quarter": quarter_label(q),
                "valuation_date": q.isoformat(),
                "nav_amount": round(value, 2),
                "currency": "USD",
                "reported_at": (q + timedelta(days=45)).isoformat(),
            })

    # Deliberate dirt: restate ~3% of valuations, reported a quarter or two later.
    restated = random.sample(rows, max(1, int(len(rows) * 0.03)))
    extra = []
    for r in restated:
        new = dict(r)
        new["nav_amount"] = round(r["nav_amount"] * random.uniform(0.80, 1.20), 2)
        new["reported_at"] = (date.fromisoformat(r["reported_at"])
                              + timedelta(days=random.choice([90, 180]))).isoformat()
        extra.append(new)
    rows.extend(extra)

    rows.sort(key=lambda r: (r["company_id"], r["valuation_date"], r["reported_at"]))
    return rows


def gen_fx_rates():
    rows = []
    rates = {"EUR": 1.10, "GBP": 1.27}
    d = date(2016, 1, 1)
    while d <= date(2025, 12, 31):
        for ccy, base in rates.items():
            rates[ccy] = max(0.5, base * random.uniform(0.995, 1.005))
            rows.append({
                "rate_date": d.isoformat(),
                "from_currency": ccy,
                "to_currency": "USD",
                "rate": round(rates[ccy], 6),
            })
        rows.append({
            "rate_date": d.isoformat(),
            "from_currency": "USD",
            "to_currency": "USD",
            "rate": 1.0,
        })
        d += timedelta(days=1)
    return rows


def gen_company_kpis(companies):
    """Nested JSON, one object per line (NDJSON) for VARIANT loading."""
    out = []
    for c in companies:
        # Deliberate dirt: a few names differ slightly from the company file,
        # forcing a small entity-resolution step.
        name = c["company_name"]
        if random.random() < 0.10:
            name = name.replace(" Group", " Grp").replace(" Holdings", " Hldgs")
        out.append({
            "company_id": c["company_id"],
            "company_name": name,
            "reporting": {
                "frequency": "quarterly",
                "last_submitted": "2025-10-15",
            },
            "metrics": [
                {"period": "2025Q1", "revenue": round(random.uniform(10, 500) * 1e6, 2),
                 "ebitda_margin": round(random.uniform(0.05, 0.35), 4),
                 "headcount": random.randint(50, 5000)},
                {"period": "2025Q2", "revenue": round(random.uniform(10, 500) * 1e6, 2),
                 "ebitda_margin": round(random.uniform(0.05, 0.35), 4),
                 "headcount": random.randint(50, 5000)},
            ],
            "tags": random.sample(["esg_reporting", "buy_and_build", "carve_out",
                                   "founder_led", "platform"], 2),
        })
    return out


# ----------------------------------------------------------------------
# Writers
# ----------------------------------------------------------------------

def write_csv(path, rows):
    if not rows:
        return
    with open(path, "w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print("  %-28s %7d rows" % (os.path.basename(path), len(rows)))


def write_ndjson(path, rows):
    with open(path, "w", encoding="utf-8") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")
    print("  %-28s %7d rows" % (os.path.basename(path), len(rows)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="data")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--investors", type=int, default=45)
    ap.add_argument("--companies", type=int, default=30)
    args = ap.parse_args()

    random.seed(args.seed)
    os.makedirs(args.out, exist_ok=True)

    print("Generating Harbour Capital dataset -> %s/" % args.out)

    funds = gen_funds()
    investors = gen_investors(args.investors)
    commitments = gen_commitments(investors, funds)
    cashflows = gen_cashflows(commitments, funds)
    companies = gen_portfolio_companies(funds, args.companies)
    valuations = gen_valuations(companies)
    fx = gen_fx_rates()
    kpis = gen_company_kpis(companies)

    write_csv(os.path.join(args.out, "funds.csv"), funds)
    write_csv(os.path.join(args.out, "investors.csv"), investors)
    write_csv(os.path.join(args.out, "commitments.csv"), commitments)
    write_csv(os.path.join(args.out, "cashflows.csv"), cashflows)
    write_csv(os.path.join(args.out, "portfolio_companies.csv"), companies)
    write_csv(os.path.join(args.out, "valuations.csv"), valuations)
    write_csv(os.path.join(args.out, "fx_rates.csv"), fx)
    write_ndjson(os.path.join(args.out, "company_kpis.json"), kpis)

    print("\nDeliberate data issues included:")
    print("  - duplicate cashflow rows (differing loaded_at)")
    print("  - restated valuations (same company + quarter, later reported_at)")
    print("  - EUR/GBP cashflows needing point-in-time FX conversion")
    print("  - ~8% of investors missing domicile_country")
    print("  - some cashflows loaded days after effective_date (late arrivals)")
    print("  - some KPI company names abbreviated vs the company file")


if __name__ == "__main__":
    main()
