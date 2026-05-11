#coding sample for RFF

using PowerModels, JuMP, Gurobi, DataFrames, CSV, XLSX, LinearAlgebra, Memento, Logging, HiGHS
Memento.config!("error")
Logging.disable_logging(Logging.Warn)

model = Model(Gurobi.Optimizer)
set_optimizer_attribute(model, MOI.Silent(), true)

#feasibility relaxation
#set_optimizer_attribute(model, "FeasibilityTol", 1e-6)

energy_sources = ["Coal", "Nuclear", "NGCC", "NGCT","NGCC with CCS", "Hydro", "Onshore Wind", "Solar"]

#load in the Ontario capacity factor data
file_path = "Data/OntarioCFdata.xlsx"
CF_df = XLSX.openxlsx(file_path) do workbook
    sheet = workbook["Sheet1"]
    data = XLSX.readtable(file_path, "Sheet1")
    DataFrame(data)
end

#load in the Ontario hourly demand data

demand_path = "Data/OntarioLoadData.xlsx"
demand_df = XLSX.openxlsx(demand_path) do workbook
    demand_sheet = workbook["LoadDatafromRAfile"]
    demand_data = XLSX.readtable(demand_path, "LoadDatafromRAfile")
    DataFrame(demand_data)
end
#println(first(demand_df,10))
# println(first(df,5))
#println(first(df.ON_solar,10))

#marginal costs ($/MWh) were calculated using cost_summary data from my RA work (variable O&M + Heat Rate * Fuel Cost)
marginal_cost = Dict(
    "Coal" => 28.548,
    "Nuclear" => 10.2524,
    "NGCC" => 23.2424,
    "NGCT" => 37.4648,
    "NGCC with CCS" => 27.4428,
    "Hydro" => 0,
    "Onshore Wind" => 0,
    "Solar" => 0
)

#pounds of CO2 emissions per MWh
carbon_emissions = Dict(
    "Coal" => 2300, # taken from EIA data: https://www.eia.gov/tools/faqs/faq.php?id=74&t=11
    "Nuclear" => 0,
    "NGCC" => 970, #same EIA data
    "NGCT" => 1300, 
    "NGCC with CCS" => 48.5, #used the same EIA data, but took off 95% for CCS; 95% value taken from: https://www.bgs.ac.uk/discovering-geology/climate-change/carbon-capture-and-storage/#:~:text=Conventional%20CCS%20on%20a%20fossil,by%20over%2095%20per%20cent.
    "Hydro" => 0,
    "Onshore Wind" => 0,
    "Solar" => 0
)

#capex cost in $/MW from RA work
inv_cost = Dict(
    "Coal" => 4790826,
    "Nuclear" => 8750300,
    "NGCC" => 1426275,
    "NGCT" => 766338,
    "NGCC with CCS" => 2966581,
    "Hydro" => 9999999999999999, #just hydro_res value; this value is 3233520, but I've set it arbitarily high here to avoid its buildout
    "Onshore Wind" => 902500,
    "Solar" => 741340
)

#find these existing capacity values in RA work files
existing_cap = Dict(
    "Coal" => 0,
    "Nuclear" => 13144,
    "NGCC" => 5470,
    "NGCT" => 5000,
    "NGCC with CCS" => 0,
    "Hydro" => 8748, #hydro_res + hydro_ror
    "Onshore Wind" => 4883,
    "Solar" => 648
)

#Ramp up and ramp down [percentage of rated capacity per hour; where 1 = 100%] (they are the same in this dataset)
ramp_up_down_pct = Dict(
    "Coal" => 0.57,
    "Nuclear" => 0.25,
    "NGCC" => 1,
    "NGCT" => 3.78,
    "NGCC with CCS" => 0.64,
    "Hydro" => 0.5,
    "Onshore Wind" => 1,
    "Solar" => 1
)

#baseline year: 2022
# https://www.cer-rec.gc.ca/en/data-analysis/energy-markets/provincial-territorial-energy-profiles/provincial-territorial-energy-profiles-ontario.html
Baseline_Level = 3.8 * 2204622621.8488 #3.8 MT emissions times conversion factor from MT to pounds

@variable(model, Pg_E[energy_sources, t=1:8760])
@variable(model, Pc_C[energy_sources, t=1:8760])
@variable(model, Xc_Cmax[energy_sources])

#non-negativity constraints
@constraint(model, [i in energy_sources], Xc_Cmax[i] >= 0)
@constraint(model, [i in energy_sources, t=1:8760], Pg_E[i,t] >= 0)
@constraint(model, [i in energy_sources, t=1:8760], Pc_C[i,t] >= 0)

#use capacity factor hourly data from RA files to set the max power generation amounts for each hour
@constraint(model, [i in energy_sources, t=1:8760], Pg_E[i,t] <= existing_cap[i] * CF_df[!,Symbol(i)][t])
@constraint(model, [i in energy_sources, t=1:8760], Pc_C[i,t] <= Xc_Cmax[i] * CF_df[!,Symbol(i)][t])

#emissions constraint
@constraint(model, [i in energy_sources], sum(carbon_emissions[i] * (Pg_E[i,t] + Pc_C[i,t]) for t in 1:8760) <= 0.1*Baseline_Level)

#meeting future hourly demand:
#https://www.newswire.ca/news-releases/electricity-demand-in-ontario-to-grow-by-75-per-cent-by-2050-849843177.html#:~:text=TORONTO%2C%20Oct.,the%20end%20of%20this%20decade.
@constraint(model, [t=1:8760], sum(Pg_E[i,t] for i in energy_sources) + sum(Pc_C[i,t] for i in energy_sources) == demand_df[!, :Load_MW][t])

#ramp up and ramp down constraints
@constraint(model, [i in energy_sources, t=2:8760], (Pg_E[i,t] + Pc_C[i,t]) - (Pg_E[i,t-1] + Pc_C[i,t-1]) <= (existing_cap[i] + Xc_Cmax[i])*ramp_up_down_pct[i])
@constraint(model, [i in energy_sources, t=2:8760], (Pg_E[i,t] + Pc_C[i,t]) - (Pg_E[i,t-1] + Pc_C[i,t-1]) >= -(existing_cap[i] + Xc_Cmax[i])*ramp_up_down_pct[i])

#the 20 factor is to account for the fact that the demand won't immediately be the 2050 demand even though this is a one-shot build, 
#so 26 years' worth of generation (to meet load) cost is approximate to just 20 years of the last year's demand assuming load increases linearly from now until 2050
#calculated justification is in this project folder
@objective(model, Min, sum(inv_cost[i]*Xc_Cmax[i] for i in energy_sources) + 20*sum(sum(marginal_cost[i]*(Pg_E[i,t] + Pc_C[i,t]) for t in 1:8760) for i in energy_sources))

optimize!(model)
if termination_status(model) == MOI.OPTIMAL
    println("Objective value: ", objective_value(model))
else
    println("The model did not solve to optimality. Status: ", termination_status(model))
end

