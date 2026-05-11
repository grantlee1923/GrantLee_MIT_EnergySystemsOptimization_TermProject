# Ontario Energy System Optimization — MIT Term Project

A mixed-integer linear program (MILP) that determines the optimal electricity generation portfolio for Ontario through 2050 under an aggressive decarbonization target.

## Overview

This project solves a capacity expansion and unit commitment problem for Ontario's electricity grid. The model selects how much new generation capacity to build and how to dispatch all sources across every hour of the year, minimizing total system cost while satisfying demand and capping carbon emissions at 10% of 2022 baseline levels (~0.38 MT CO₂e/year).

## Problem Formulation

**Objective:** Minimize total cost = Capital Expenditure + 20 years of Operating Costs

**Decision Variables:**

*Generation:*
- `Pg_E[i,t]` — Power from existing capacity of source `i` at hour `t` (MW)
- `Pc_C[i,t]` — Power from new capacity of source `i` at hour `t` (MW)
- `Xc_Cmax[i]` — New generation capacity to build for source `i` (MW)

*Battery storage:*
- `Xbat_MW` — New battery power capacity to build (MW)
- `P_dis[t]` — Battery discharge power at hour `t` (MW)
- `P_chg[t]` — Battery charge power at hour `t` (MW)
- `E_stor[t]` — Battery state of charge at end of hour `t` (MWh)
- `u_bat[t]` — Binary mode flag to enforce non-simultaneous charging and discharging

*Reliability:*
- `NSE[t]` — Non-served energy at hour `t` (MW); load that cannot be met by generation or storage, penalized at VOLL = $20,000/MWh in the objective

**Key Constraints:**
- Supply-demand balance enforced at every hour: generation + net battery discharge + NSE = load
- Generation bounded by capacity × capacity factor
- Annual CO₂ emissions ≤ 10% of 2022 baseline
- Hourly ramp-rate limits for each thermal technology
- Battery discharge and charge each bounded by power capacity
- Battery cannot charge and discharge in the same hour (enforced via binary variable `u_bat[t]`)
- Battery state of charge bounded by energy capacity (duration x power capacity)
- Cyclic SOC energy balance: end-of-year state of charge equals start-of-year

## Technologies Modeled

| Technology | Type |
|---|---|
| Coal | Fossil |
| Nuclear | Low-carbon |
| NGCC | Fossil |
| NGCT (peaker) | Fossil |
| NGCC + CCS | Low-carbon |
| Hydro | Renewable (existing only) |
| Onshore Wind | Renewable |
| Solar PV | Renewable |
| **Battery Storage (4-hr)** | **Storage** |

## Repository Structure

```
├── run.jl                        # Entry point — runs all three stages in order
├── src/
│   ├── load_inputs.jl            # Reads all CSVs and Excel files, defines parameters
│   ├── build_model.jl            # Builds and solves the JuMP optimization model
│   └── write_outputs.jl          # Writes results to Data/outputs/
└── Data/
    ├── generator_params.csv       # Per-technology costs, capacity, ramp rates, emissions
    ├── battery_params.csv         # Battery storage parameters
    ├── model_config.csv           # Scalar settings: emissions target, planning horizon
    ├── OntarioCFdata.xlsx         # Hourly capacity factors for all technologies (8,760 hrs)
    ├── OntarioLoadData.xlsx       # Hourly electricity demand for Ontario (8,760 hrs)
    └── outputs/                   # Generated on first run
        ├── capacity_expansion.csv # Optimal new capacity per technology (MW / MWh)
        └── dispatch.csv           # Hourly generation, battery dispatch, SOC, and NSE
```

## Requirements

- [Julia](https://julialang.org/) 1.6+
- [JuMP](https://jump.dev/) — mathematical optimization modeling
- [Gurobi](https://www.gurobi.com/) (primary solver) or [HiGHS](https://highs.dev/) (open-source fallback)
- [XLSX.jl](https://github.com/felipenoris/XLSX.jl) — for reading Excel data files

Install Julia packages:
```julia
using Pkg
Pkg.add(["JuMP", "HiGHS", "XLSX", "DataFrames", "CSV"])
```

## Running the Model

```julia
julia run.jl
```

This will load all inputs, solve the model, and write results to `Data/outputs/`. Progress is printed at each stage. To modify assumptions, edit the CSV files in `Data/` — no changes to the Julia scripts are needed for most scenarios.

## Key Modeling Assumptions

- **Planning horizon:** 2024–2050 (~20 years of operations using full 2050 load for all years)
- **Emissions target:** ≤ 10% of Ontario's 2022 grid emissions (3.8 MT CO₂e)
- **Hydro:** Existing capacity only; new hydro buildout excluded via prohibitive capital cost
- **Battery storage:** 4-hour lithium-ion battery with symmetric charge/discharge power capacity, cyclic state-of-charge balance, and 0.92 one-way efficiency on each side
- **CCS efficiency:** 95% emissions reduction applied to NGCC+CCS units
- **Value of lost load (VOLL):** $20,000/MWh — non-served energy is allowed in the power balance but penalized at this rate in the objective, ensuring load shedding only occurs when it is cheaper than the marginal cost of serving that energy
- **Full-year hourly resolution:** All 8,760 hours modeled to capture renewable variability and demand peaks

## Course

MIT Energy Systems Optimization — Term Project
