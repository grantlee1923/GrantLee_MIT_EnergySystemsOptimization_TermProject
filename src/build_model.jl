using JuMP, Gurobi, HiGHS

model = Model(Gurobi.Optimizer)
set_silent(model)

# ── Variables ──────────────────────────────────────────────────────────────────
@variable(model, Pg_E[energy_sources, 1:HOURS_PER_YEAR] >= 0)  # dispatch from existing capacity (MW)
@variable(model, Pc_C[energy_sources, 1:HOURS_PER_YEAR] >= 0)  # dispatch from new capacity (MW)
@variable(model, Xc_Cmax[energy_sources]                >= 0)  # new generation capacity to build (MW)

@variable(model, Xbat_MW                  >= 0)  # new battery power capacity (MW)
@variable(model, P_dis[1:HOURS_PER_YEAR]  >= 0)  # battery discharge power (MW)
@variable(model, P_chg[1:HOURS_PER_YEAR]  >= 0)  # battery charge power (MW)
@variable(model, E_stor[1:HOURS_PER_YEAR] >= 0)  # battery state of charge (MWh)
@variable(model, u_bat[1:HOURS_PER_YEAR], Bin)   # 1 = discharge mode, 0 = charge/idle mode
@variable(model, NSE[1:HOURS_PER_YEAR]    >= 0)  # non-served energy (MW)

# ── Generation constraints ─────────────────────────────────────────────────────
@constraint(model, cap_existing[i in energy_sources, t=1:HOURS_PER_YEAR],
    Pg_E[i,t] <= existing_cap[i] * CF_df[t, Symbol(i)])

@constraint(model, cap_new[i in energy_sources, t=1:HOURS_PER_YEAR],
    Pc_C[i,t] <= Xc_Cmax[i] * CF_df[t, Symbol(i)])

@constraint(model, emissions_limit,
    sum(carbon_intensity[i] * (Pg_E[i,t] + Pc_C[i,t])
        for i in energy_sources, t in 1:HOURS_PER_YEAR) <= emissions_cap_lbs)

@constraint(model, ramp_up[i in energy_sources, t=2:HOURS_PER_YEAR],
    (Pg_E[i,t] + Pc_C[i,t]) - (Pg_E[i,t-1] + Pc_C[i,t-1]) <=
     (existing_cap[i] + Xc_Cmax[i]) * ramp_rate[i])

@constraint(model, ramp_down[i in energy_sources, t=2:HOURS_PER_YEAR],
    (Pg_E[i,t] + Pc_C[i,t]) - (Pg_E[i,t-1] + Pc_C[i,t-1]) >=
    -(existing_cap[i] + Xc_Cmax[i]) * ramp_rate[i])

# ── Battery storage constraints ────────────────────────────────────────────────
@constraint(model, bat_dis_lim[t=1:HOURS_PER_YEAR],   P_dis[t] <= Xbat_MW)
@constraint(model, bat_chg_lim[t=1:HOURS_PER_YEAR],   P_chg[t] <= Xbat_MW)

# Mutual exclusivity: battery cannot charge and discharge in the same hour.
# bat_max_mw is the big-M; combined with bat_dis_lim / bat_chg_lim this tightens to Xbat_MW.
@constraint(model, bat_dis_mode[t=1:HOURS_PER_YEAR],  P_dis[t] <= bat_max_mw * u_bat[t])
@constraint(model, bat_chg_mode[t=1:HOURS_PER_YEAR],  P_chg[t] <= bat_max_mw * (1 - u_bat[t]))

@constraint(model, bat_soc_lim[t=1:HOURS_PER_YEAR],
    E_stor[t] <= bat_duration * Xbat_MW)

# Cyclic SOC energy balance: end-of-year SOC wraps to start-of-year
@constraint(model, bat_soc_balance[t=1:HOURS_PER_YEAR],
    E_stor[t] == (t > 1 ? E_stor[t-1] : E_stor[HOURS_PER_YEAR]) +
                 bat_eff_charge * P_chg[t] - (1 / bat_eff_discharge) * P_dis[t])

@constraint(model, bat_max_cap, Xbat_MW <= bat_max_mw)

@constraint(model, bat_ramp_up[t=2:HOURS_PER_YEAR],
    (P_dis[t] - P_chg[t]) - (P_dis[t-1] - P_chg[t-1]) <=  ramp_rate["Battery"] * Xbat_MW)

@constraint(model, bat_ramp_down[t=2:HOURS_PER_YEAR],
    (P_dis[t] - P_chg[t]) - (P_dis[t-1] - P_chg[t-1]) >= -ramp_rate["Battery"] * Xbat_MW)

# ── Demand balance ─────────────────────────────────────────────────────────────
@constraint(model, demand_balance[t=1:HOURS_PER_YEAR],
    sum(Pg_E[i,t] + Pc_C[i,t] for i in energy_sources) +
    P_dis[t] - P_chg[t] + NSE[t] == demand_df[t, :Load_MW])

# ── Objective ──────────────────────────────────────────────────────────────────
# Minimize capital cost + 20-year operating cost.
# The 20-year factor accounts for load growth 2024–2050 modeled as a single snapshot;
# linear interpolation over the planning horizon yields ~20 equivalent full-demand years.
@objective(model, Min,
    sum(inv_cost[i] * Xc_Cmax[i] for i in energy_sources) +
    bat_capex_mw * Xbat_MW +
    opex_years * sum(marginal_cost[i] * (Pg_E[i,t] + Pc_C[i,t])
                     for i in energy_sources, t in 1:HOURS_PER_YEAR) +
    opex_years * VOLL * sum(NSE[t] for t in 1:HOURS_PER_YEAR))

# ── Solve ──────────────────────────────────────────────────────────────────────
optimize!(model)

if termination_status(model) == MOI.OPTIMAL
    println("  Optimal total system cost: \$", round(objective_value(model) / 1e9, digits=2), "B")
else
    println("  Solver status: ", termination_status(model))
    error("Model did not solve to optimality — outputs not written.")
end
