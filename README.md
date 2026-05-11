# Ontario Energy System Optimization — MIT Term Project

A mixed-integer linear programming (MILP) model that determines the optimal electricity generation portfolio for Ontario through 2050 under an aggressive decarbonization target.

## Overview

This project solves a capacity expansion and unit commitment problem for Ontario's electricity grid. The model selects how much new generation capacity to build and how to dispatch all sources across every hour of the year, minimizing total system cost while satisfying demand and capping carbon emissions at 10% of 2022 baseline levels (~0.38 MT CO₂e/year).

## Problem Formulation

**Objective:** Minimize total cost = Capital Expenditure + 20 years of Operating Costs

**Decision Variables:**
- `Pg_E[i,t]` — Power from existing capacity of source `i` at hour `t` (MW)
- `Pc_C[i,t]` — Power from new capacity of source `i` at hour `t` (MW)
- `Xc_Cmax[i]` — New capacity to build for source `i` (MW)

**Key Constraints:**
- Supply-demand balance enforced at every hour (8,760 time steps)
- Generation bounded by capacity × capacity factor
- Annual CO₂ emissions ≤ 10% of 2022 baseline
- Hourly ramp-rate limits for each technology

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

## Repository Structure

```
├── EnergySystemOpt_ProjectCode.jl   # Main optimization model
└── Data/
    ├── OntarioCFdata.xlsx            # Hourly capacity factors for all technologies (8,760 hrs)
    └── OntarioLoadData.xlsx          # Hourly electricity demand for Ontario (8,760 hrs)
```

## Requirements

- [Julia](https://julialang.org/) 1.6+
- [JuMP](https://jump.dev/) — mathematical optimization modeling
- [Gurobi](https://www.gurobi.com/) (primary solver) or [HiGHS](https://highs.dev/) (open-source fallback)
- [XLSX.jl](https://github.com/felipenoris/XLSX.jl) — for reading Excel data files

Install Julia packages:
```julia
using Pkg
Pkg.add(["JuMP", "HiGHS", "XLSX", "DataFrames"])
```

## Running the Model

```julia
julia EnergySystemOpt_ProjectCode.jl
```

The script will print the optimal objective value (total system cost), solver status, and the optimal new capacity and dispatch for each technology.

## Key Modeling Assumptions

- **Planning horizon:** 2024–2050 (~20 years of operations)
- **Emissions target:** ≤ 10% of Ontario's 2022 grid emissions (3.8 MT CO₂e)
- **Hydro:** Existing capacity only; new hydro buildout excluded via prohibitive capital cost
- **No storage:** Battery or pumped-hydro storage is not modeled
- **CCS efficiency:** 95% emissions reduction applied to NGCC+CCS units
- **Full-year hourly resolution:** All 8,760 hours modeled to capture renewable variability and demand peaks

## Course

MIT Energy Systems Optimization — Term Project
