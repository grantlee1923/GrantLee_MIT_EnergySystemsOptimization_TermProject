using DataFrames, CSV

mkpath("Data/outputs")

# ── Capacity expansion results ─────────────────────────────────────────────────
cap_df = DataFrame(
    technology       = vcat(energy_sources, ["Battery ($(bat_duration)-hr)"]),
    new_capacity_mw  = vcat(
        [round(value(Xc_Cmax[i]), digits=1) for i in energy_sources],
        [round(value(Xbat_MW), digits=1)]
    ),
    new_capacity_mwh = vcat(
        fill(missing, length(energy_sources)),
        [round(value(Xbat_MW) * bat_duration, digits=1)]
    )
)

CSV.write("Data/outputs/capacity_expansion.csv", cap_df)
println("  Wrote Data/outputs/capacity_expansion.csv")

# ── Hourly dispatch ────────────────────────────────────────────────────────────
# Column names replace spaces with underscores for CSV compatibility
col_name(s) = replace(s, " " => "_")

dispatch_df = DataFrame(hour = 1:HOURS_PER_YEAR)

for i in energy_sources
    dispatch_df[!, Symbol(col_name(i) * "_MW")] =
        [round(value(Pg_E[i,t]) + value(Pc_C[i,t]), digits=2) for t in 1:HOURS_PER_YEAR]
end

dispatch_df[!, :Battery_discharge_MW] = [round(value(P_dis[t]),   digits=2) for t in 1:HOURS_PER_YEAR]
dispatch_df[!, :Battery_charge_MW]    = [round(value(P_chg[t]),   digits=2) for t in 1:HOURS_PER_YEAR]
dispatch_df[!, :Battery_SOC_MWh]      = [round(value(E_stor[t]),  digits=2) for t in 1:HOURS_PER_YEAR]
dispatch_df[!, :NSE_MW]               = [round(value(NSE[t]),     digits=2) for t in 1:HOURS_PER_YEAR]
dispatch_df[!, :Load_MW]              = demand_df[!, :Load_MW]

CSV.write("Data/outputs/dispatch.csv", dispatch_df)
println("  Wrote Data/outputs/dispatch.csv ($(HOURS_PER_YEAR) rows × $(ncol(dispatch_df)) columns)")
