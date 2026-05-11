using DataFrames, CSV, XLSX

# ── Physical constants ─────────────────────────────────────────────────────────
const HOURS_PER_YEAR = 8760
const MT_TO_LBS      = 2_204_622_621.8488   # lbs per megatonne CO₂
const VOLL           = 20_000.0             # value of lost load ($/MWh)

# ── Model configuration ────────────────────────────────────────────────────────
config_raw = CSV.read("Data/model_config.csv", DataFrame)
config = Dict(row.parameter => row.value for row in eachrow(config_raw))

baseline_emissions_mt = config["baseline_emissions_mt"]
emissions_target_pct  = config["emissions_target_pct"]
opex_years            = Int(config["opex_years"])

emissions_cap_lbs = emissions_target_pct * baseline_emissions_mt * MT_TO_LBS

# ── Generator parameters ───────────────────────────────────────────────────────
gen_df = CSV.read("Data/generator_params.csv", DataFrame)

energy_sources   = gen_df[!, :technology]
marginal_cost    = Dict(row.technology => row.marginal_cost    for row in eachrow(gen_df))
carbon_intensity = Dict(row.technology => row.carbon_intensity for row in eachrow(gen_df))
inv_cost         = Dict(row.technology => row.inv_cost_per_mw  for row in eachrow(gen_df))
existing_cap     = Dict(row.technology => row.existing_cap_mw  for row in eachrow(gen_df))
ramp_rate        = Dict(row.technology => row.ramp_rate        for row in eachrow(gen_df))

# ── Battery parameters ─────────────────────────────────────────────────────────
bat_df = CSV.read("Data/battery_params.csv", DataFrame)

bat_capex_mw      = bat_df[1, :capex_per_mw]
bat_eff_charge    = bat_df[1, :eff_charge]
bat_eff_discharge = bat_df[1, :eff_discharge]
bat_duration      = Int(bat_df[1, :duration_hrs])
bat_max_mw        = bat_df[1, :max_cap_mw]
ramp_rate["Battery"] = bat_df[1, :ramp_rate]

# ── Time series data ───────────────────────────────────────────────────────────
CF_df     = DataFrame(XLSX.readtable("Data/OntarioCFdata.xlsx", "Sheet1"))
demand_df = DataFrame(XLSX.readtable("Data/OntarioLoadData.xlsx", "LoadDatafromRAfile"))

println("  Loaded $(length(energy_sources)) generators, $(HOURS_PER_YEAR) hours of time-series data.")
