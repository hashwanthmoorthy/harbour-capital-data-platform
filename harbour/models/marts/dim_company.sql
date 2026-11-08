-- Grain: one row per portfolio company.
--
-- Joins the KPI pack on company_id only. The KPI file spells roughly
-- 10% of company names differently from the finance system - "Avonmere
-- Ind." against "Avonmere Industries" - so joining on name would
-- silently drop those rows. The KPI spelling is kept in its own column
-- rather than reconciled, so the discrepancy stays visible.

with companies as (
    select * from {{ ref('stg_portfolio_companies') }}
),

latest_kpis as (
    select
        company_id,
        kpi_company_name,
        reporting_period,
        revenue,
        ebitda_margin,
        headcount
    from {{ ref('stg_company_kpis') }}
    qualify row_number() over (
        partition by company_id
        order by reporting_period desc
    ) = 1
),

final as (
    select
        companies.company_id,
        companies.company_name,
        companies.fund_id,
        companies.sector,
        companies.country,
        companies.entry_date,
        companies.entry_cost,

        datediff('year', companies.entry_date, current_date())
                                        as holding_period_years,

        latest_kpis.reporting_period    as latest_kpi_period,
        latest_kpis.revenue             as latest_revenue,
        latest_kpis.ebitda_margin       as latest_ebitda_margin,
        latest_kpis.headcount           as latest_headcount,

        -- Kept deliberately. Shows where the KPI pack disagrees with
        -- the finance system on naming.
        latest_kpis.kpi_company_name,
        case
            when latest_kpis.kpi_company_name is null then null
            when latest_kpis.kpi_company_name = companies.company_name
                then false
            else true
        end                             as kpi_name_differs
    from companies
    left join latest_kpis
        on companies.company_id = latest_kpis.company_id
)

select * from final
