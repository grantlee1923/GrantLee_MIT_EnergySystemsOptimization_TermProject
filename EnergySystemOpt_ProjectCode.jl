using JuMP, Gurobi, DataFrames, XLSX, HiGHS

# ── Constants ──────────────────────────────────────────────────────────────────
const HOURS_PER_YEAR        = 8760
const MT_TO_LBS             = 2_204_622_621.8488   # lbs per megatonne CO₂
const BASELINE_EMISSIONS_MT = 3.8                  # Ontario 2022 grid emissions (MT CO₂e)
const OPEX_YEARS            = 20                   # effective operating years (2024–2050 approximation)

# ── Energy sources ─────────────────────────────────────────────────────────────
const ENERGY_SOURCES = ["Coal", "Nuclear", "NGCC", "NGCT", "NGCC with CCS",
                        "Hydro", "Onshore Wind", "Solar"]

# ── Load data ──────────────────────────────────────────────────────────────────
CF_df     = DataFrame(XLSX.readtable("Data/OntarioCFdata.xlsx", "Sheet1"))
demand_df = DataFrame(XLSX.readtable("Data/OntarioLoadData.xlsx", "LoadDatafromRAfile"))

# ── Technology parameters ──────────────────────────────────────────────────────
# Marginal costs ($/MWh): variable O&M + heat rate × fuel cost
marginal_cost = Dict(
    "Coal"          => 28.5480,
    "Nuclear"       => 10.2524,
    "NGCC"          => 23.2424,
    "NGCT"          => 37.4648,
    "NGCC with CCS" => 27.4428,
    "Hydro"         =>  0.0,
    "Onshore Wind"  =>  0.0,
    "Solar"         =>  0.0,
)

# CO₂ emissions intensity (lbs/MWh)
# Source: EIA https://www.eia.gov/tools/faqs/faq.php?id=74&t=11
# CCS value applies 95% capture rate to NGCC baseline
carbon_intensity = Dict(
    "Coal"          => 2300.0,
    "Nuclear"       =>    0.0,
    "NGCC"          =>  970.0,
    "NGCT"          => 1300.0,
    "NGCC with CCS" =>   48.5,
    "Hydro"         =>    0.0,
    "Onshore Wind"  =>    0.0,
    "Solar"         =>    0.0,
)

# Capital cost ($/MW)
inv_cost = Dict(
    "Coal"          => 4_790_826,
    "Nuclear"       => 8_750_300,
    "NGCC"          => 1_426_275,
    "NGCT"          =>   766_338,
    "NGCC with CCS" => 2_966_581,
    "Hydro"         => 9_999_999_999_999_999,  # prohibitively high: no new hydro buildout
    "Onshore Wind"  =>   902_500,
    "Solar"         =>   741_340,
)

# Existing installed capacity (MW), Ontario 2024
existing_cap = Dict(
    "Coal"          =>      0,
    "Nuclear"       => 13_144,
    "NGCC"          =>  5_470,
    "NGCT"          =>  5_000,
    "NGCC with CCS" =>      0,
    "Hydro"         =>  8_748,   # reservoir + run-of-river
    "Onshore Wind"  =>  4_883,
    "Solar"         =>    648,
)

# Ramp rate (fraction of rated capacity per hour)
ramp_rate = Dict(
    "Coal"          => 0.57,
    "Nuclear"       => 0.25,
    "NGCC"          => 1.00,
    "NGCT"          => 3.78,
    "NGCC with CCS" => 0.64,
    "Hydro"         => 0.50,
    "Onshore Wind"  => 1.00,
    "Solar"         => 1.00,
)

# Aggregate annual emissions cap: 10% of Ontario's 2022 baseline
# Source: https://www.cer-rec.gc.ca/en/data-analysis/energy-markets/provincial-territorial-energy-profiles/provincial-territorial-energy-profiles-ontario.html
emissions_cap_lbs = 0.1 * BASELINE_EMISSIONS_MT * MT_TO_LBS

# ── Model ──────────────────────────────────────────────────────────────────────
model = Model(Gurobi.Optimizer)
set_silent(model)

@variable(model, Pg_E[ENERGY_SOURCES, 1:HOURS_PER_YEAR] >= 0)  # dispatch from existing capacity (MW)
@variable(model, Pc_C[ENERGY_SOURCES, 1:HOURS_PER_YEAR] >= 0)  # dispatch from new capacity (MW)
@variable(model, Xc_Cmax[ENERGY_SOURCES]                >= 0)  # new capacity to build (MW)

# Capacity factor limits on existing and new generation
@constraint(model, cap_existing[i in ENERGY_SOURCES, t=1:HOURS_PER_YEAR],
    Pg_E[i,t] <= existing_cap[i] * CF_df[t, Symbol(i)])

@constraint(model, cap_new[i in ENERGY_SOURCES, t=1:HOURS_PER_YEAR],
    Pc_C[i,t] <= Xc_Cmax[i] * CF_df[t, Symbol(i)])

# Demand balance at every hour
@constraint(model, demand_balance[t=1:HOURS_PER_YEAR],
    sum(Pg_E[i,t] + Pc_C[i,t] for i in ENERGY_SOURCES) == demand_df[t, :Load_MW])

# Aggregate annual CO₂ emissions cap
@constraint(model, emissions_limit,
    sum(carbon_intensity[i] * (Pg_E[i,t] + Pc_C[i,t])
        for i in ENERGY_SOURCES, t in 1:HOURS_PER_YEAR) <= emissions_cap_lbs)

# Ramp-rate constraints (hours 2 through HOURS_PER_YEAR)
@constraint(model, ramp_up[i in ENERGY_SOURCES, t=2:HOURS_PER_YEAR],
    (Pg_E[i,t] + Pc_C[i,t]) - (Pg_E[i,t-1] + Pc_C[i,t-1]) <=
     (existing_cap[i] + Xc_Cmax[i]) * ramp_rate[i])

@constraint(model, ramp_down[i in ENERGY_SOURCES, t=2:HOURS_PER_YEAR],
    (Pg_E[i,t] + Pc_C[i,t]) - (Pg_E[i,t-1] + Pc_C[i,t-1]) >=
    -(existing_cap[i] + Xc_Cmax[i]) * ramp_rate[i])

# Objective: minimize capital cost + 20-year operating cost
# The 20-year factor accounts for load growth 2024–2050 modeled as a single snapshot;
# linear interpolation over the planning horizon yields ~20 equivalent full-demand years.
@objective(model, Min,
    sum(inv_cost[i] * Xc_Cmax[i] for i in ENERGY_SOURCES) +
    OPEX_YEARS * sum(marginal_cost[i] * (Pg_E[i,t] + Pc_C[i,t])
                     for i in ENERGY_SOURCES, t in 1:HOURS_PER_YEAR))

# ── Solve and report ───────────────────────────────────────────────────────────
optimize!(model)

if termination_status(model) == MOI.OPTIMAL
    println("Optimal total system cost: \$", round(objective_value(model) / 1e9, digits=2), "B")
    println("\nOptimal new capacity additions (MW):")
    for i in ENERGY_SOURCES
        cap = round(value(Xc_Cmax[i]), digits=1)
        cap > 0 && println("  $(rpad(i, 20)) $(cap) MW")
    end
else
    println("Solver did not find an optimal solution. Status: ", termination_status(model))
end
