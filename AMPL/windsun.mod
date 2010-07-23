# This is the fundamental code of Switch which compiles a mixed integer linear program to be solved by CPLEX.
# Most constants are found in windsun.dat, while run-time variables are in the various .tab files.
# A combination of windsun.run and switch.run wrap around windsun.mod.

###############################################
#
# Time-tracking parameters
#

set TIMEPOINTS ordered;

# Each timepoint is assigned to a study period exogenously,
# so that we don't have to do any arithmetic to figure out
# which timepoint is in each period. This allows for arbitrary
# numbering of the hours, so they need not be spaced integral
# number of hours apart through the whole year. This is important
# if we want to sample, e.g., 12*24 hours per year or per 3 years.
# Another way to do it would be to exogenously specify
# how many samples there are per study period, and then bundle
# them up within the model. That would allow us to change the length
# of the study period from inside the model.
# But it wouldn't gain us very much, since the sampling must be
# done carefully for each study period anyway.

# chronological information on each timepoint (e.g. study hour, sample)
# this is used to identify which hours fall in each study period
# and how many real hours are represented by each sample (which may be fractional).
# Hour_of_day and month_of_year are just used for reporting (if that)
param period {TIMEPOINTS};
param date {TIMEPOINTS};
param hours_in_sample {TIMEPOINTS};
param hour_of_day {TIMEPOINTS};
param month_of_year {TIMEPOINTS};
param season_of_year {h in TIMEPOINTS} = floor((month_of_year[h]-1)/3)+1;

# note: periods must be evenly spaced and count by years
set PERIODS ordered = setof {h in TIMEPOINTS} (period[h]);

# specific dates are used to collect hours that are part of the same
# day, for the purpose of hydro dispatch, etc.
set DATES ordered = setof {h in TIMEPOINTS} (date[h]);

set HOURS_OF_DAY ordered = setof {h in TIMEPOINTS} (hour_of_day[h]);
set MONTHS_OF_YEAR ordered = setof {h in TIMEPOINTS} (month_of_year[h]);
set SEASONS_OF_YEAR ordered = setof {h in TIMEPOINTS} (season_of_year[h]);

# the date (year and fraction) when the optimization starts
param start_year = first(PERIODS);

# interval between study periods
param num_years_per_period = (last(PERIODS)-first(PERIODS))/(card(PERIODS)-1);

# the first year past the end of the current simulation
# used for discounting series of annual payments back to a lump sum at the start of the payment window
param end_year = last(PERIODS) + num_years_per_period;


###############################################
#
# System loads and zones
#

# Load Areas are the smallest unit of load in the model. 
set LOAD_AREAS;

# load area id, useful for rapidly referencing the database
param load_area_id {LOAD_AREAS} >= 0;

# system load (MW)
param system_load {LOAD_AREAS, TIMEPOINTS} >= 0;

# Regional cost multipliers
param economic_multiplier {LOAD_AREAS} >= 0;

# system load aggregated in various ways
param total_loads_by_period {p in PERIODS} = 
	sum {a in LOAD_AREAS, h in TIMEPOINTS: period[h]=p} system_load[a, h];
param total_loads_by_period_weighted {p in PERIODS} = 
	sum {a in LOAD_AREAS, h in TIMEPOINTS: period[h]=p} system_load[a, h] * hours_in_sample[h];

###################
#
# Financial data
#

# the year to which all costs should be discounted
param base_year >= 0;

# annual rate (real) to use to discount future costs to current year
param discount_rate;

# required rates of return (real) for generator and transmission investments
# may differ between generator types, and between generators and transmission lines
param finance_rate >= 0;
param transmission_finance_rate >= 0;

# cost of carbon emissions ($/ton), e.g., from a carbon tax
# can also be set negative to drive renewables out of the system
param carbon_cost default 0;

# set and parameters used to make carbon cost curves
set CARBON_COSTS;

# planning reserve margin - fractional extra load the system must be able able to serve
# when there are no forced outages
param planning_reserve_margin;

###############################################
# Solar run parameters

# Minimum amount of electricity that solar must produce
param min_solar_production >= 0, <= 1;

# Minimum amount of electricity that solar must produce
param enable_min_solar_production >= 0, <= 1 default 0;

set SOLAR_CSP_TECHNOLOGIES;
set SOLAR_DIST_PV_TECHNOLOGIES;

###############################################
#
# Technology and Fuel specifications for generators
# (most of these come from generator_info.tab)

set TECHNOLOGIES;

# database ids for technologies
param technology_id {TECHNOLOGIES} >= 0;

# earliest time when each technology can be built
param min_build_year {TECHNOLOGIES} >= 0;

# all possible years in the study, including the first year construction can begin
set YEARS ordered = (min{ t in TECHNOLOGIES } min_build_year[t]) .. end_year by 1;

# list of all possible fuels
set FUELS; 

# Reference to hydro's "fuel": Water
param fuel_hydro symbolic in FUELS;

# fuel used by this type of plant
param fuel {TECHNOLOGIES} symbolic in FUELS;

# annual fuel price forecast in $/MBtu
param fuel_price {LOAD_AREAS, FUELS, YEARS} default 0, >= 0;

# carbon content (tons) per MBtu of each fuel
param carbon_content {FUELS} default 0, >= 0;

# For now, all hours in each study period use the same fuel cost which averages annual prices over the course of each study period.
# This could be updated to use fuel costs that vary by month, or for an hourly model, it could interpolate between annual forecasts 
param fuel_cost_hourly {a in LOAD_AREAS, f in FUELS, h in TIMEPOINTS} := 
	( sum{ y in YEARS: y >= period[h] and y < period[h] + num_years_per_period } fuel_price[a, f, y] )
	/ num_years_per_period;

# heat rate (in MBtu/MWh)
param heat_rate {TECHNOLOGIES} >= 0;

# construction lead time (years)
param construction_time_years {TECHNOLOGIES} >= 0;

# the next six parameters decribe the fraction of costs that must be paid from the
# start of construction to the completion of the project
param year_1_cost_fraction {TECHNOLOGIES} >= 0, <= 1;
param year_2_cost_fraction {TECHNOLOGIES} >= 0, <= 1;
param year_3_cost_fraction {TECHNOLOGIES} >= 0, <= 1;
param year_4_cost_fraction {TECHNOLOGIES} >= 0, <= 1;
param year_5_cost_fraction {TECHNOLOGIES} >= 0, <= 1;
param year_6_cost_fraction {TECHNOLOGIES} >= 0, <= 1;

# life of the plant (age when it must be retired)
param max_age_years {TECHNOLOGIES} >= 0;

# fraction of the time when a plant will be unexpectedly unavailable
param forced_outage_rate {TECHNOLOGIES} >= 0, <= 1;

# fraction of the time when a plant must be taken off-line for maintenance
param scheduled_outage_rate {TECHNOLOGIES} >= 0, <= 1;

# does the generator have a fixed hourly capacity factor?
param intermittent {TECHNOLOGIES} binary;

# can this type of project only be installed in limited amounts?
param resource_limited {TECHNOLOGIES} binary;

# is this type of plant run in baseload mode?
param new_baseload {TECHNOLOGIES} binary;

# is this plant dispatchable?
param dispatchable {t in TECHNOLOGIES} binary = 
(if intermittent[t] = 0 and new_baseload[t] = 0 
 then 1
 else 0
)
;

# does this type of project have a minimum feasable installation size?
# only in place for Nuclear at the moment
# other technologies such as Coal, CSP and CCGT that hit their minimum feasable/economical size at ~100-300MW
# are left out of this constraint because the decrease in runtime is more important than added resolution on minimum install capacity,
# especially considering that if a project is economical, normally Switch will build a few hundred MW per load area
param min_build_capacity {TECHNOLOGIES} >= 0;

# the minimum capacity in MW that a project can be dispatched due to operation constraints
# (i.e. CCGTs don't operate at 5% capacity)
param min_dispatch_fraction {TECHNOLOGIES} >= 0;

# the minimum amount of hours a generator must be operating (at >= min_dispatch_fraction)
# if that generator is to be turned on at all
param min_runtime {TECHNOLOGIES} >= 0;

# the minimum amount of hours a generator must be left off before ramping up again
param min_downtime {TECHNOLOGIES} >= 0;

# the maximum ramp rate (unused at the moment)
param max_ramp_rate_mw_per_hour {TECHNOLOGIES} >= 0;

# the amount of fuel burned in MBtu that is needed to start a generator from cold
param startup_fuel_mbtu {TECHNOLOGIES} >= 0;

# Whether or not technologies located at the same place will compete for space
param technologies_compete_for_space {TECHNOLOGIES} >= 0, <= 1 default 0;

# Solar-based technologies
set SOLAR_TECHNOLOGIES = {t in TECHNOLOGIES: fuel[t]=='Solar'};

# Names of technologies that have capacity factors or maximum capacities 
# tied to specific locations. 
param tech_wind symbolic in TECHNOLOGIES;
param tech_offshore_wind symbolic in TECHNOLOGIES;
param tech_biomass_igcc symbolic in TECHNOLOGIES;
param tech_bio_gas symbolic in TECHNOLOGIES;

# names of other technologies, just to have them around 
# (but this is getting silly)
param tech_ccgt symbolic in TECHNOLOGIES;
param tech_gas_combustion_turbine symbolic in TECHNOLOGIES;

#####################

# new storage techs ######

# is this technology an electricity storage technology?
param storage {TECHNOLOGIES} binary;

# Parameters
# Currently only one technology, so will keep this in windsun.dat file, but should probably create a separate table for
# storage-specific parameters eventually
param round_trip_efficiency_caes >= 0 ;
param storage_efficiency_caes >= 0, <= 1;
#    Dispatch(stored) = Dispatch(NG) * caes_ng_to_storage_ratio
param caes_ng_to_storage_ratio = storage_efficiency_caes / (round_trip_efficiency_caes - storage_efficiency_caes);
 
# Maximum store rate for CAES
param max_store_rate_caes >= 0;
  
  
##################################################################
#
# Project data

set PROJECTS dimen 3; # Project ID, load area, technology

param project_location {PROJECTS} >= 0;
param capacity_limit {PROJECTS} >= 0;
param capacity_limit_conversion {PROJECTS} >= 0;

# cost of grid upgrades to support a new project, in dollars per peak MW.
# these are needed in order to deliver power from the interconnect point to
# the load center (or make it deliverable to other zones)
param connect_cost_per_mw {PROJECTS} >= 0 default 0;

# year for which the price of each technology has been specified
param price_and_dollar_year {PROJECTS} >= 0;

# overnight cost for the plant ($/MW)
param overnight_cost {PROJECTS} >= 0;

# fixed O&M ($/MW-year)
param fixed_o_m {PROJECTS} >= 0;

# variable O&M ($/MWh)
param variable_o_m {PROJECTS} >= 0;

# annual rate of change of overnight cost, beginning at price_and_dollar_year
param overnight_cost_change {PROJECTS};

# the nonfuel costs incurred by starting a plant from cold to producing powers
param nonfuel_startup_cost {PROJECTS};

set PROJ_RESOURCE_LIMITED = {(pid, a, t) in PROJECTS: resource_limited[t]};

# maximum capacity factors (%) for each project, each hour. 
# generally based on renewable resources available
set PROJ_INTERMITTENT_HOURS dimen 4;  # LOAD_AREAS, TECHNOLOGIES, PROJECT_ID, TIMEPOINTS
set PROJ_INTERMITTENT = setof {(pid, a, t, h) in PROJ_INTERMITTENT_HOURS} (pid, a, t);

check: card({(pid, a, t) in PROJ_RESOURCE_LIMITED: intermittent[t]} diff PROJ_INTERMITTENT) = 0;
param cap_factor {PROJ_INTERMITTENT_HOURS};

set PROJ_ANYWHERE = {(pid, a, t) in PROJECTS: not intermittent[t] and not resource_limited[t]};

# the set of all dispatchable projects (i.e., non-intermittent)
set PROJ_DISPATCH = {(pid, a, t) in PROJECTS: not new_baseload[t] and not intermittent[t]};

# the set of all new storage projects
set PROJ_STORAGE = {(pid, a, t) in PROJECTS: storage[t]};

# project-vintage combinations that can be installed
set PROJECT_VINTAGES = { (pid, a, t) in PROJECTS, p in PERIODS: p >= min_build_year[t] + construction_time_years[t]};
# technology that can be installed, along with their year of construction and year of coming online. 
set TECHNOLOGY_VINTAGES = setof { (pid, a, t, p) in PROJECT_VINTAGES} (t, p);

# default values for projects that don't have sites
param location_unspecified symbolic;

# maximum capacity that can be installed in each project. These are units of MW for most technologies. The exceptions are Central PV and CSP, which have units of km^2 and a conversion factor of MW / km^2
set LOCATIONS_WITH_COMPETING_TECHNOLOGIES;
param capacity_limit_by_location {loc in LOCATIONS_WITH_COMPETING_TECHNOLOGIES} = min {(pid, a, t) in PROJ_RESOURCE_LIMITED: project_location[pid, a, t] == loc } capacity_limit[pid, a, t];

# make sure all hours are represented, and that cap factors make sense.
# Solar thermal can be parasitic, which means negative cap factors are allowed (just not TOO negative)
check {(pid, a, t) in PROJ_INTERMITTENT, h in TIMEPOINTS: t in SOLAR_CSP_TECHNOLOGIES}: cap_factor[pid, a, t, h] >= -0.1;
# No other technology can be parasitic, so only positive cap factors allowed
check {(pid, a, t) in PROJ_INTERMITTENT, h in TIMEPOINTS: not( t in SOLAR_CSP_TECHNOLOGIES) }: cap_factor[pid, a, t, h] >= 0;
# cap factors for solar can be greater than 1 becasue sometimes the sun shines more than 1000W/m^2
# which is how PV cap factors are defined.
# The below checks make sure that for other plants the cap factors
# are <= 1 but for solar they are <= 1.4
# (roughly the irradiation coming in from space, though the cap factor shouldn't ever approach this number)
check {(pid, a, t) in PROJ_INTERMITTENT, h in TIMEPOINTS: not( t in SOLAR_TECHNOLOGIES )}: cap_factor[pid, a, t, h] <= 1;
check {(pid, a, t) in PROJ_INTERMITTENT, h in TIMEPOINTS: t in SOLAR_TECHNOLOGIES }: cap_factor[pid, a, t, h] <= 1.4;
check {(pid, a, t) in PROJ_INTERMITTENT}: intermittent[t];


##################################################################
#
# RPS goals for each load area 

set LOAD_AREAS_AND_FUEL_CATEGORY dimen 2;
set RPS_FUEL_CATEGORY = setof {(load_area, rps_fuel_category) in LOAD_AREAS_AND_FUEL_CATEGORY} (rps_fuel_category);

param enable_rps >= 0, <= 1 default 0;

# whether fuels in a load area qualify for rps 
param fuel_qualifies_for_rps {LOAD_AREAS_AND_FUEL_CATEGORY};

# determines if fuel falls in solar/wind/geo or gas/coal/nuclear/hydro
param rps_fuel_category {FUELS} symbolic in RPS_FUEL_CATEGORY;

# new RPS stuff... replace stuff above
param rps_compliance_fraction {LOAD_AREAS, YEARS} >= 0 default 0;

# average the RPS compliance percentages over a period to get the RPS target for that period
# the end year is the year after the last period, so this sum doesn't include it.
param rps_compliance_fraction_in_period {a in LOAD_AREAS, p in PERIODS} = 
	( sum {yr in YEARS: yr >= p and yr < p + num_years_per_period}
	rps_compliance_fraction[a, yr] ) / num_years_per_period;

##############################################
# Existing hydro plants (assumed impossible to build more, but these last forever)

# forced outage rate for hydroelectric dams
# this is used to de-rate the planned power production
# NOT in use right now for some hydro constraints
# but is used to derate pumped hydro storage decisions
param forced_outage_rate_hydro >= 0;

# round-trip efficiency for storing power via a pumped hydro system
param pumped_hydro_efficiency > 0;

# annual costs for existing hydro plants (see notes in windsun.run)
# "carrying cost" for hydro and pumped hydro facilities ($/MWp/year)
# The source for these cost number is Black and Veach / NREL ReEDS
# To do: Move these numbers & calculations into the database, then read them in with other cost values in existing_plants.tab
param hydro_capital = 2242369 * discount_rate / (1-(1+discount_rate)^(-100)); # $2242369/MW * crf (capital recovery factor for a 100-year project at 7% interest)
param hydro_fixed_o_m = 13632; # 13632/MW (fixed O&M per MW)
param hydro_var_o_m = 2.43; 
param hydro_var_o_m_annual = hydro_var_o_m * 8766 * 0.38; # var_o_m [$/MWh] * 8766h * 0.38 h/y (approx. capacity factor for hydro projects is about 38% according to our hydro monthly limit data)
param hydro_annual_payment_per_mw =
	hydro_capital + hydro_fixed_o_m + hydro_var_o_m_annual;

# indexing sets for hydro data (read in along with data tables)
# (this should probably be monthly data, but this has equivalent effect,
# and doesn't require adding a month dataset and month <-> date links)
set PROJ_HYDRO_DATES dimen 3; # load_area, hydro_project_id, date

# database id for hydro projects
param hydro_project_id {PROJ_HYDRO_DATES} >= 0;
param hydro_technology {PROJ_HYDRO_DATES} symbolic;
param hydro_technology_id {PROJ_HYDRO_DATES} >= 0;

# average output (in MW) for dams aggregated to the load area level for each day
# (note: we assume that the average dispatch for each day must come out at this average level,
# and flow will always be between minimum and maximum levels)
# average is based on historical power production for each month
# for simple hydro, minimum output is a fixed fraction of average output
# for pumped hydro, minimum output is a negative value, showing the maximum pumping rate
param hydro_capacity_mw {PROJ_HYDRO_DATES} >= 0;
param avg_hydro_output {PROJ_HYDRO_DATES};

set PROJ_HYDRO = setof {(a, pid, d) in PROJ_HYDRO_DATES} (a, pid);
set PROJ_PUMPED_HYDRO = setof {(a, pid, d) in PROJ_HYDRO_DATES: hydro_technology[a, pid, d] = 'Hydro_Pumped'} (a, pid);
set PROJ_NONPUMPED_HYDRO = setof {(a, pid, d) in PROJ_HYDRO_DATES: hydro_technology[a, pid, d] = 'Hydro_NonPumped'} (a, pid);

# Make sure hydro outputs aren't outside the bounds of the turbine capacities (should have already been fixed in mysql)
check {(a, pid, d) in PROJ_HYDRO_DATES}: 
  -hydro_capacity_mw[a, pid, d] <= avg_hydro_output[a, pid, d] <= hydro_capacity_mw[a, pid, d];
check {(a, pid, d) in PROJ_HYDRO_DATES: hydro_technology[a, pid, d] = 'Hydro_NonPumped'}: 
  0 <= avg_hydro_output[a, pid, d] <= hydro_capacity_mw[a, pid, d];

# make sure each hydro plant has an entry for each date.
check {(a, pid) in PROJ_HYDRO}:
	card(DATES symdiff setof {(a, pid, d) in PROJ_HYDRO_DATES} (d)) = 0;

# minimum dispatch that non-pumped hydro generators must do in each hour
# TODO this should be derived from USGS stream flow data
# right now, it's set at 25% of the average stream flow for each month
# there isn't a similar paramter for pumped hydro because it is assumed that the lower resevoir is large enough
# such that hourly stream flow can be maintained independent of the pumped hydro dispatch
# especially because the daily flow through the turbine will be constrained to be within historical monthly averages below
param min_nonpumped_hydro_dispatch_fraction = 0.25;

###############################################
# Existing generators

# name of each plant
set EXISTING_PLANTS dimen 2;  # load zone, plant code

check {a in setof {(a, e) in EXISTING_PLANTS} (a)}: a in LOAD_AREAS;

# the database id of the plant
param ep_project_id {EXISTING_PLANTS} >= 0;

# the size of the plant in MW
param ep_size_mw {EXISTING_PLANTS} >= 0;

# type of technology used by the plant
param ep_technology {EXISTING_PLANTS} symbolic;

# type of fuel used by the plant
param ep_fuel {EXISTING_PLANTS} symbolic in FUELS;

# heat rate (in MBtu/MWh)
param ep_heat_rate {EXISTING_PLANTS} >= 0;

# year when the plant was built (used to calculate annual capital cost and retirement date)
param ep_vintage {EXISTING_PLANTS} >= 0;

# life of the plant (age when it must be retired)
param ep_max_age_years {EXISTING_PLANTS} >= 0;

# overnight cost of the plant ($/MW)
param ep_overnight_cost {EXISTING_PLANTS} >= 0;

# fixed O&M ($/MW-year)
param ep_fixed_o_m {EXISTING_PLANTS} >= 0;

# variable O&M ($/MWh)
param ep_variable_o_m {EXISTING_PLANTS} >= 0;

# fraction of the time when a plant will be unexpectedly unavailable
param ep_forced_outage_rate {EXISTING_PLANTS} >= 0, <= 1;

# fraction of the time when a plant must be taken off-line for maintenance
param ep_scheduled_outage_rate {EXISTING_PLANTS} >= 0, <= 1;

# does the generator run at its full capacity all year?
param ep_baseload {EXISTING_PLANTS} binary;

# is the generator part of a cogen facility?
param ep_cogen {EXISTING_PLANTS} binary;

# is the generator intermittent (i.e. is its power production non-dispatchable)?
param ep_intermittent {EXISTING_PLANTS} binary;

# is the generator dispatchable?
param ep_dispatchable {(a,e) in EXISTING_PLANTS} binary = 
(if ep_intermittent[a,e] = 0 and ep_baseload[a,e] = 0 
 then 1
 else 0
)
;

###############################################
# Existing intermittent generators (existing wind, csp and pv)

# hours in which each existing intermittent renewable adds power to the grid
set EP_INTERMITTENT_HOURS dimen 3;  # load zone, plant code, hour

# capacity factor for existing intermittent renewables
# generally between 0 and 1, but for some solar plants the capacity factor may be more than 1
# due to capacity factor definition, so the limit here is 1.4
param eip_cap_factor {EP_INTERMITTENT_HOURS} >= 0 <=1.4;

###############################################
# Transmission lines

# cost to build a transmission line, per mw of capacity, per km of distance
# (assumed linear and can be added in small increments!)
param transmission_cost_per_mw_km >= 0;

# the cost to maintin the existing transmission infrustructure over all of WECC
param transmission_sunk_annual_payment {LOAD_AREAS} >= 0;

# retirement age for transmission lines
param transmission_max_age_years >= 0;

# forced outage rate for transmission lines, used for probabilistic dispatch(!)
param transmission_forced_outage_rate >= 0;

# possible transmission lines are listed in advance;
# these include all possible combinations of LOAD_AREAS, with no double-counting
# The model could be simplified by only allowing lines to be built between neighboring zones.
set TRANSMISSION_LINES in {LOAD_AREAS, LOAD_AREAS};

# length of each transmission line
param transmission_length_km {TRANSMISSION_LINES};

# delivery efficiency on each transmission line
param transmission_efficiency {TRANSMISSION_LINES};

# the rating of existing lines in MW (can be different for the two directions, but each direction is
# represented by an individual entry in the table)
param existing_transfer_capacity_mw {TRANSMISSION_LINES} >= 0 default 0;

# unique ID for each transmission line, used for reporting results
param transmission_line_id {TRANSMISSION_LINES};

# parameters for local transmission and distribution from the large-scale network to distributed loads
param local_td_max_age_years >= 0;
param local_td_new_annual_payment_per_mw {LOAD_AREAS} >= 0;

# the max_coincident_load_for_local_td is used to determine the amount of new local t&d needed in a load area
# this param represents the max coincident load in 2010 for each load area
param max_coincident_load_for_local_td {LOAD_AREAS} >= 0; 

# it is assumed that local T&D is currently installed up to the capacity margin
# (hence the max_coincident_load_for_local_td * ( 1 + planning_reserve_margin ) ).
# TODO: find better data on how much Local T&D is already installed above peak load
param existing_local_td {a in LOAD_AREAS} = max_coincident_load_for_local_td[a] * ( 1 + planning_reserve_margin );

# the cost to maintin the existing local T&D infrustructure for each load area
param local_td_sunk_annual_payment {LOAD_AREAS} >= 0;

#####################
# calculate discounted costs for new plants

# apply projected annual real cost changes to each technology,
# to get the capital, fixed and variable costs if it is installed 
# at each possible vintage date

# first, the capital cost of the plant and any 
# interconnecting lines and grid upgrades
# (all costs are in $/MW)

# calculate fraction of capital cost incurred in each year of the construction period based on declination schedule

set YEAR_OF_CONSTRUCTION ordered;

# date when a plant of each type and vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made) 
# until the end of that period. This avoids having artificial gaps
# between retirements and starting new plants.
param project_end_year {t in TECHNOLOGIES, p in PERIODS} =
  min(end_year, p + ceil(max_age_years[t]/num_years_per_period)*num_years_per_period);

param cost_fraction {t in TECHNOLOGIES, yr in YEAR_OF_CONSTRUCTION};

param project_vintage_overnight_costs {(pid, a, t, online_yr) in PROJECT_VINTAGES} = 
	# Overnight cost, adjusted for projected cost changes.
	overnight_cost[pid, a, t] * (1+overnight_cost_change[pid, a, t])^(online_yr - construction_time_years[t] - price_and_dollar_year[pid, a, t]);

# The equations below make a working assumption that the "finance rate" and "discount rate" are the same value. 
# If those numbers take on different values, the equation will need to be inspected for correctness. 
# Bring the series of lump-sum costs made during construction up to the year before the plant starts operation. 
param cost_of_plant_one_year_before_operational {(pid, a, t, online_yr) in PROJECT_VINTAGES} =
  # Connect costs are incurred in said year, so they don't accrue interest
  connect_cost_per_mw[pid, a, t] + 
  # Construction costs are incurred annually during the construction phase. 
  sum{ yr_of_constr in YEAR_OF_CONSTRUCTION } (
  	cost_fraction[t, yr_of_constr] * project_vintage_overnight_costs[pid, a, t, online_yr] *
  	(1 + discount_rate) ^ ( construction_time_years[t] - yr_of_constr - 1 )  	# This exponent will range from (construction_time - 1) to 0, meaning the cost of the last year's construction doesn't accrue interest.
  	)
 
;
# Spread the costs of the plant evenly over the plant's operation. 
# This doesn't represent the cash flow. Rather, it spreads the costs of bringing the plant online evenly over the operational period so the linear program optimization won't experience "boundary conditions" and avoid making long-term investments close to the last year of the simulation. 
param overnight_cost_levelized_over_operation {(pid, a, t, online_yr) in PROJECT_VINTAGES} = 
  cost_of_plant_one_year_before_operational[pid, a, t, online_yr] *
  discount_rate / ( 1 - (1 + discount_rate) ^ ( -1 * max_age_years[t] ) )
  ;

param capital_cost {(pid, a, t, online_yr) in PROJECT_VINTAGES} = 
  overnight_cost_levelized_over_operation [pid, a, t, online_yr]
  # CRF to convert uniform annual payments to a lump sum in the year before operation starts
  * (1 - (1+discount_rate)^(-1 * (project_end_year[t,online_yr] - online_yr)))/discount_rate
  # future value (in the year before operation starts) to present value (in the base year)
  * 1/(1+discount_rate)^(online_yr - 1 - base_year)
;

# Take the stream of fixed O & M payments over the duration of the each periods,
# and discount to a lump-sum value at the start of the period,
# then discount from there to the base_year.
param fixed_o_m_by_period {(pid, a, t, p) in PROJECT_VINTAGES} = 
  # Fixed annual costs that are paid while the plant is operating (up to the end of the study period)
  fixed_o_m[pid, a, t]
    # U to P: Convert annual payments during the course of the period to the value at the beginning of the period
    * (1-(1+discount_rate)^(-1*num_years_per_period))/discount_rate
    # F to P, from the time the plant comes online to the base year
    * 1/(1+discount_rate)^(p-base_year);

# all variable costs ($/MWh) for generating a MWh of electricity in some
# future hour, using a particular technology and vintage, 
# discounted to reference year
# these include O&M, fuel, carbon tax
# We also multiply by the number of real hours represented by each sample,
# because a case study could use only a limited subset of hours.
# (this used to vary by vintage to allow for changing variable costs, but not anymore)
# note: in a full hourly model, this should discount each hour based on its exact date,
# but for now, since the hours are non-chronological samples within each study period,
# they are all discounted by the same factor
param variable_cost {(pid, a, t) in PROJECTS, h in TIMEPOINTS} =
  hours_in_sample[h] * (
    variable_o_m[pid, a, t] + heat_rate[t] * fuel_cost_hourly[a, fuel[t], h]
  ) * 1/(1+discount_rate)^(period[h]-base_year);

param carbon_cost_per_mwh {t in TECHNOLOGIES, h in TIMEPOINTS} = 
  hours_in_sample[h] * (
    heat_rate[t] * carbon_content[fuel[t]] * carbon_cost
  ) * 1/(1+discount_rate)^(period[h]-base_year);

########
# now get discounted costs for existing projects on similar terms

# year when the plant will be retired
# this is rounded up to the end of the study period when the retirement would occur,
# so power is generated and capital & O&M payments are made until the end of that period.
param ep_end_year {(a, e) in EXISTING_PLANTS} =
  min(end_year, start_year+ceil((ep_vintage[a, e]+ep_max_age_years[a, e]-start_year)/num_years_per_period)*num_years_per_period);


# plant-period combinations when existing plants can run
# these are the times when a decision must be made about whether a plant will be kept available for the year
# or mothballed to save on fixed O&M (or fuel, for baseload plants)
# note: something like this could be added later for early retirement of new plants too
# cogen plants can be operated past their normal lifetime by paying O & M costs during each period, plus paying into a capital replacement fund
set EP_PERIODS :=
  {(a, e) in EXISTING_PLANTS, p in PERIODS: 
  		( not ep_cogen[a, e] and p < ep_end_year[a, e] ) or
  		( ep_cogen[a, e] )	
  };
param ep_could_be_operating_past_expected_lifetime { (a, e, p) in EP_PERIODS } =
  (if ep_cogen[a, e] and p >= ep_end_year[a, e]
   then 1
   else 0
  );

param ep_capital_cost_annual_payment {(a, e) in EXISTING_PLANTS} = 
  sum{ yr in YEAR_OF_CONSTRUCTION: yr < construction_time_years[ep_technology[a, e]] } (
    ep_overnight_cost[a, e] * economic_multiplier[a]
    * cost_fraction[ep_technology[a, e], yr] 
	* finance_rate / (1 - (1+finance_rate)^(-1* (ep_max_age_years[a, e]+construction_time_years[ep_technology[a, e]]-yr)))
  );


# Calculate capital costs for all cogen plants that are operated beyond their expected retirement. 
# This can be thought of as making payments into a capital replacement fund
param ep_capital_cost_payment_per_period_to_extend_operation
	{(a, e, p) in EP_PERIODS: ep_could_be_operating_past_expected_lifetime[a, e, p]} =
		ep_capital_cost_annual_payment[a, e]
    # A factor to convert all of the uniform annual payments that occur in a study period to the start of a study period
		* (1-(1+discount_rate)^(-1*num_years_per_period))/discount_rate
    # Future value (at the start of the study) to Present value (in the base year)
		* 1/(1+discount_rate)^(p-base_year);

# discount capital costs to a lump-sum value at the start of the study.
# Multiply fixed costs by years per period so they will match the way multi-year periods are implicitly treated in variable costs.
param ep_capital_cost {(a, e) in EXISTING_PLANTS: start_year < ep_end_year[a, e]} =
    ep_capital_cost_annual_payment[a, e]
    # A factor to convert Uniform annual capital payments from the start of the study until the plant is retired
    # to a lump sum value at the start of the study
    * (1-(1+discount_rate)^(-1 * (ep_end_year[a, e]-start_year)))/discount_rate
    # Future value (at the start of the study) to Present value (in the base year)
    * 1/(1+discount_rate)^(start_year-base_year);


# cost per MW to operate a plant in any future period, discounted to start of study (ep_fixed_o_m is a series of annual payments)
# and then discounted back to the base year
param ep_fixed_o_m_cost {(a, e, p) in EP_PERIODS} =
  ep_fixed_o_m[a, e] * economic_multiplier[a] 
    # A factor to convert all of the uniform annual payments that occur in a study period to the start of a study period
    * (1-(1+discount_rate)^(-1 * num_years_per_period))/discount_rate
    # Future value (at the start of the study) to Present value (in the base year)
    * 1/(1+discount_rate)^(p-base_year);

# all variable costs ($/MWh) for generating a MWh of electricity in some
# future hour, from each existing project, discounted to the reference year
# In variable costs, hours_in_sample is a weight intended to reflect how many hours are represented by a timepoint.
# hours_in_sample is calculated using period length in MySQL: period_length * (days represented) * (subsampling factors),
# so if you work through the math, variable costs are multiplied by period_length.
param ep_variable_cost {(a, e) in EXISTING_PLANTS, h in TIMEPOINTS} =
  hours_in_sample[h] * (
    ep_variable_o_m[a, e] * economic_multiplier[a]
    + ep_heat_rate[a, e] * fuel_cost_hourly[a, ep_fuel[a, e], h]
  ) * 1/(1+discount_rate)^(period[h]-base_year);

param ep_carbon_cost_per_mwh {(a, e) in EXISTING_PLANTS, h in TIMEPOINTS} = 
  hours_in_sample[h] * (
    ep_heat_rate[a, e] * carbon_content[ep_fuel[a, e]] * carbon_cost
  ) * 1/(1+discount_rate)^(period[h]-base_year);

########
# now get discounted costs per MW for transmission lines and local T&D on similar terms

# cost per MW for transmission lines
# TODO: Move the regional cost adjustment into the database. 
param transmission_annual_payment {(a1, a2) in TRANSMISSION_LINES, p in PERIODS} = 
  transmission_finance_rate / (1 - (1+transmission_finance_rate)^(-1*transmission_max_age_years)) 
  * transmission_cost_per_mw_km * ( (economic_multiplier[a1] + economic_multiplier[a2]) / 2 )
  * transmission_length_km[a1, a2];

# date when a transmission line built of each vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made).
param transmission_end_year {p in PERIODS} =
  min(end_year, p + ceil(transmission_max_age_years/num_years_per_period)*num_years_per_period);

# discounted transmission cost per MW
param transmission_cost_per_mw {(a1, a2) in TRANSMISSION_LINES, p in PERIODS} =
  transmission_annual_payment[a1, a2, p]
  * (1-(1+discount_rate)^(-1*(transmission_end_year[p] - p)))/discount_rate
  * 1/(1+discount_rate)^(p-base_year);

# costs to pay off and maintain the existing transmission grid are brought in as yearly cost that must be incurred
# so they are summed here to make a total lump sum cost in present value at the base_year
param transmission_sunk_cost =
  sum {a in LOAD_AREAS} 
    transmission_sunk_annual_payment[a] 
    * (1 - (1+discount_rate)^(-1*(end_year-start_year)))/discount_rate
    * 1/(1+discount_rate)^(start_year-base_year);

# date when a when local T&D infrastructure of each vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made).
param local_td_end_year {p in PERIODS} =
  min(end_year, p + ceil(local_td_max_age_years/num_years_per_period)*num_years_per_period);

# discounted cost per MW for local T&D
# the costs are already regionalized, so no need to do it again here
param local_td_cost_per_mw {a in LOAD_AREAS, p in PERIODS} = 
  local_td_new_annual_payment_per_mw[a]
  * (1 - (1+discount_rate)^(-1*(local_td_end_year[p]-p)))/discount_rate
  * 1/(1+discount_rate)^(p-base_year);

# costs to pay off and maintain local T&D are brought in as yearly cost that must be incurred
# so they are summed here to make a total lump sum cost in present value at the base_year
param local_td_sunk_cost =
  sum {a in LOAD_AREAS} 
    local_td_sunk_annual_payment[a] 
    * (1 - (1+discount_rate)^(-1*(end_year-start_year)))/discount_rate
    * 1/(1+discount_rate)^(start_year-base_year);


######
# total cost of existing hydro plants (including capital and O&M)
# note: it would be better to handle these costs more endogenously.
# for now, we assume the nameplate capacity of each plant is equal to its peak allowed output.

# the total cost per MW for existing hydro plants
# (the discounted stream of annual payments over the whole study)
param hydro_cost_per_mw { a in LOAD_AREAS } = 
  hydro_annual_payment_per_mw * economic_multiplier[a]
  * (1 - (1+discount_rate)^(-1*(end_year-start_year)))/discount_rate
  * 1/(1+discount_rate)^(start_year-base_year);
# find the nameplate capacity of all existing hydro - they're all the same value - the max just picks one - could do avg or min instead
param hydro_total_capacity {(a, pid) in PROJ_HYDRO} = 
  max {(a, pid, d) in PROJ_HYDRO_DATES} hydro_capacity_mw[a, pid, d];

##################
# reduced sets for decision variables and constraints

# project-vintage combinations that have a minimum size constraint.
set PROJ_MIN_BUILD_VINTAGES = {(pid, a, t, p) in PROJECT_VINTAGES: min_build_capacity[t] > 0};

# technology-site-vintage-hour combinations for dispatchable projects
# (i.e., all the project-vintage combinations that are still active in a given hour of the study)
set PROJ_DISPATCH_VINTAGE_HOURS := 
  {(pid, a, t) in PROJ_DISPATCH, p in PERIODS, h in TIMEPOINTS: not new_baseload[t] and p >= min_build_year[t] + construction_time_years[t] and p <= period[h] < project_end_year[t, p]};

# technology-site-vintage-hour combinations for storage projects
# (i.e., all the project-vintage combinations that are still active in a given hour of the study)
set PROJ_STORAGE_VINTAGE_HOURS := 
  {(pid, a, t) in PROJ_STORAGE, p in PERIODS, h in TIMEPOINTS: p >= min_build_year[t] + construction_time_years[t] and p <= period[h] < project_end_year[t, p]};

# technology-project-vintage-hour combinations for intermittent (non-dispatchable) projects
set PROJ_INTERMITTENT_VINTAGE_HOURS := 
  {(pid, a, t) in PROJ_INTERMITTENT, p in PERIODS, h in TIMEPOINTS: p >= min_build_year[t] + construction_time_years[t] and p <= period[h] < project_end_year[t, p]};

# plant-period combinations when new baseload plants can be installed
set NEW_BASELOAD_VINTAGES = {(pid, a, t, p) in PROJECT_VINTAGES: new_baseload[t] and p >= min_build_year[t] + construction_time_years[t] };

# plant-period combinations when new baseload plants can run. That is, all new baseload plants that are active in a given hour of the study
set NEW_BASELOAD_VINTAGE_HOURS =
  setof {(pid, a, t, p) in NEW_BASELOAD_VINTAGES, h in TIMEPOINTS: p <= period[h] < project_end_year[t, p]} (pid, a, t, p, h);


# plant-hour combinations when existing plants can be available. 
set EP_AVAILABLE_HOURS := setof{ (a, e, p) in EP_PERIODS, h in TIMEPOINTS: period[h] = p} (a,e,h);

# plant-hour combinations when existing non-baseload, non-intermittent plants can be dispatched
set EP_DISPATCH_HOURS :=
  {(a, e) in EXISTING_PLANTS, h in TIMEPOINTS: not ep_baseload[a, e] and not ep_intermittent[a,e]
  	and period[h] < ep_end_year[a, e]};

# plant-hour combinations when existing intermittent plants can produce power or be mothballed (e.g. They have not been retired yet)
set EP_INTERMITTENT_OPERATIONAL_HOURS :=
  {(a, e, h) in EP_INTERMITTENT_HOURS: 
  	# Retire plants after their max age. e.g. Filter out periods that occur after the plant is retired. 
  	period[h] < ep_end_year[a, e]};

# plant-period combinations when existing baseload plants can run
# note: periods in which non-cogen baseload plants have exceeded their max age
# and are therefore retired are selected out above in EP_PERIODS
set EP_BASELOAD_PERIODS :=
  {(a, e, p) in EP_PERIODS: ep_baseload[a, e]};

# trans_line-vintage-hour combinations for which dispatch decisions must be made
set TRANS_VINTAGE_HOURS := 
  {(a1, a2) in TRANSMISSION_LINES, p in PERIODS, h in TIMEPOINTS: p <= period[h] < transmission_end_year[p]};

# local_td-vintage-hour combinations which must be reconciled
set LOCAL_TD_HOURS := 
  {a in LOAD_AREAS, p in PERIODS, h in TIMEPOINTS: p <= period[h] < local_td_end_year[p]};


#### VARIABLES ####

# number of MW to install in each project at each date (vintage)
var InstallGen {PROJECT_VINTAGES} >= 0;

# binary constraint that restricts small plants of certain types of generators (ex: Nuclear) from being built
# this quantity is one when there is there is not a constraint on how small plants can be
# and is zero when there is a constraint
var BuildGenOrNot {PROJ_MIN_BUILD_VINTAGES} >= 0, <= 1, integer;

# number of MW to generate from each generation project, in each hour
var DispatchGen {PROJ_DISPATCH, TIMEPOINTS} >= 0;

# the load in MW drawn from grid from storing electrons in new storage plants
var StoreEnergy {PROJ_STORAGE, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;
# number of MW to generate from each storage project, in each hour. 
var ReleaseEnergy {PROJ_STORAGE, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;


# storage reserve variables. 
# ReleaseEnergyReserve is different from ReleaseEnergy in that all power from a CAES plant is attributed to ReleaseEnergyReserve rather than being spread over two decision variables. 
var StoreEnergyReserve {PROJ_STORAGE, TIMEPOINTS} >= 0;
var ReleaseEnergyReserve {PROJ_STORAGE, TIMEPOINTS} >= 0;

# Number of MW of power consumed in each load area in each hour. This is needed for RPS in cases where some excess power is spilled.
var ConsumePower {LOAD_AREAS, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;

# share of existing plants to operate during each study period.
# this should be a binary variable, but it's interesting to see 
# how the continuous form works out
var OperateEPDuringPeriod {EP_PERIODS} >= 0, <= 1, integer;

# number of MW to generate from each existing dispatchable plant, in each hour
var DispatchEP {EP_DISPATCH_HOURS} >= 0;

# number of MW to install in each transmission corridor at each vintage
var InstallTrans {TRANSMISSION_LINES, PERIODS} >= 0;

# number of MW to transmit through each transmission corridor in each hour
var DispatchTransFromXToY {TRANSMISSION_LINES, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;
var DispatchTransFromXToY_Reserve {TRANSMISSION_LINES, TIMEPOINTS} >= 0;

# amount of local transmission and distribution capacity
# (to carry peak power from transmission network to distributed loads)
var InstallLocalTD {LOAD_AREAS, PERIODS} >= 0;

# amount of hydro to store and dispatch during each hour
# note: Store_Pumped_Hydro represents the load on the grid so the amount of energy available for release
# is Store_Pumped_Hydro * pumped_hydro_efficiency
var Dispatch_NonPumped_Hydro {PROJ_NONPUMPED_HYDRO, TIMEPOINTS} >= 0;
var Dispatch_Pumped_Hydro_Watershed_Electrons {PROJ_PUMPED_HYDRO, TIMEPOINTS} >= 0;
var Dispatch_Pumped_Hydro_Storage {PROJ_PUMPED_HYDRO, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;
var Store_Pumped_Hydro {PROJ_PUMPED_HYDRO, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;
# hydro reserve variables
var Dispatch_NonPumped_Hydro_Reserve {PROJ_NONPUMPED_HYDRO, TIMEPOINTS} >= 0;
var Dispatch_Pumped_Hydro_Watershed_Electrons_Reserve {PROJ_PUMPED_HYDRO, TIMEPOINTS} >= 0;
var Dispatch_Pumped_Hydro_Storage_Reserve {PROJ_PUMPED_HYDRO, TIMEPOINTS} >= 0;
var Store_Pumped_Hydro_Reserve {PROJ_PUMPED_HYDRO, TIMEPOINTS} >= 0;

#####################################################
# The rest of the variables are derived from linear combinations of decision variables. 
# They are substituted out before the optimization occurs, so do not increase the complixity of the model.

# This tracks the cumulative installed capacity at each project that is available at any given timepoint of the study.
var Installed_To_Date { (pid, a, t) in PROJECTS, h in TIMEPOINTS } = 
	sum {(pid, a, t, install_yr) in PROJECT_VINTAGES: 
	     install_yr <= period[h] < project_end_year[t, install_yr] } 
	 InstallGen[pid, a, t, install_yr];
var Installed_To_Date_by_Period { (pid, a, t) in PROJECTS, p in PERIODS } = 
	sum {(pid, a, t, install_yr) in PROJECT_VINTAGES: 
	     install_yr <= p < project_end_year[t, install_yr] } 
	 InstallGen[pid, a, t, install_yr];

# How much power is expected from each new project in each timepoint.
var Power_Produced { (pid, a, t) in PROJECTS, h in TIMEPOINTS};
subject to Power_From_Dispatchable_Plants { (pid, a, t) in PROJECTS, h in TIMEPOINTS: dispatchable[t]}: 
	Power_Produced[pid, a, t, h] = DispatchGen[pid, a, t, h];
subject to Power_From_Intermittent_Plants { (pid, a, t) in PROJECTS, h in TIMEPOINTS: intermittent[t] }: 
	Power_Produced[pid, a, t, h] = Installed_To_Date[pid, a, t, h] * cap_factor[pid, a, t, h] * ( 1 - forced_outage_rate[t] );
subject to Power_From_Baseload_Plants { (pid, a, t) in PROJECTS, h in TIMEPOINTS: new_baseload[t] }: 
    Power_Produced[pid, a, t, h] =  Installed_To_Date[pid, a, t, h] * ( 1 - forced_outage_rate[t] ) * ( 1 - scheduled_outage_rate[t] );

# How much power is expected from each non-storage existing project in each timepoint.
var EP_Power_Produced { (a,e,h) in EP_AVAILABLE_HOURS };
subject to EP_Power_From_Dispatchable_Plants { (a,e,h) in EP_AVAILABLE_HOURS: ep_dispatchable[a,e] }: 
	EP_Power_Produced[a,e,h] = DispatchEP[a, e, h];
subject to EP_Power_From_Intermittent_Plants { (a,e,h) in EP_AVAILABLE_HOURS: ep_intermittent[a,e] }: 
	EP_Power_Produced[a,e,h] = OperateEPDuringPeriod[a, e, period[h]] * ep_size_mw[a, e] * eip_cap_factor[a, e, h] * ( 1 - ep_forced_outage_rate[a, e] );
subject to EP_Power_From_Baseload_Plants { (a,e,h) in EP_AVAILABLE_HOURS: ep_baseload[a,e] }: 
    EP_Power_Produced[a,e,h] = OperateEPDuringPeriod[a, e, period[h]] * ep_size_mw[a, e] * ( 1 - ep_forced_outage_rate[a, e] ) * ( 1 - ep_scheduled_outage_rate[a, e] );


# The gross power available in each load area in each hour, broken down by "renewable" and "non-renewable" sources.
var Gross_Power {a in LOAD_AREAS, h in TIMEPOINTS, fc in RPS_FUEL_CATEGORY} = 
	# Power from new plants
	sum {(pid, a, t) in PROJECTS: rps_fuel_category[fuel[t]] = fc} 
        Power_Produced[pid, a, t, h]
    # Power from existing plants
    + sum { (a,e,h) in EP_AVAILABLE_HOURS: rps_fuel_category[ep_fuel[a, e]] = fc }
        EP_Power_Produced[a,e,h]
  #############################
  # Hydro Production
    # non pumped 
	+ ( sum {(a, pid) in PROJ_NONPUMPED_HYDRO: rps_fuel_category[fuel_hydro] = fc}
		Dispatch_NonPumped_Hydro[a, pid, h] )
    # pumped dispatch of water that wasn't stored
	+ ( sum {(a, pid) in PROJ_PUMPED_HYDRO: rps_fuel_category[fuel_hydro] = fc}
		Dispatch_Pumped_Hydro_Watershed_Electrons[a, pid, h] );

# The net power available in each load area in each hour, broken down by "renewable" and "non-renewable" sources.
var Net_Power {a in LOAD_AREAS, h in TIMEPOINTS, fc in RPS_FUEL_CATEGORY}
  = Gross_Power[a, h, fc] 
  #############################
  # Storage (moves power temporally)
    # Compressed Air Energy Storage
  + sum {(pid, a, t) in PROJ_STORAGE} (
		ReleaseEnergy[pid, a, t, h, fc] - StoreEnergy[pid, a, t, h, fc] )
    # Pumped Hydro
  + sum {(a, pid) in PROJ_PUMPED_HYDRO} (
		Dispatch_Pumped_Hydro_Storage[a, pid, h, fc] - Store_Pumped_Hydro[a, pid, h, fc])
  #############################
  # Transmission (moves power spatially)
  # Imports (have experienced transmission losses)
  + ( sum {(a2, a) in TRANSMISSION_LINES} 
      DispatchTransFromXToY[a2, a, h, fc] * transmission_efficiency[a2, a])
  # Exports (have not experienced transmission losses)
  - ( sum {(a, a1) in TRANSMISSION_LINES}
	  DispatchTransFromXToY[a, a1, h, fc]);


#### OBJECTIVES ####

# minimize the total cost of power over all study periods and hours, including carbon tax
# pid = project specific id
# a = load area
# t = technology
# p = PERIODS, the start of an investment period as well as the date when a power plant starts running.
# h = study hour - unique timepoint considered
# e = Plant ID for existing plants. In US, this is the fuel, primemover and FERC plant_code. e.g. NG-CC-55306
# p = investment period

minimize Power_Cost:

	#############################
	#    NEW PLANTS
	# Capital costs
      sum {(pid, a, t, p) in PROJECT_VINTAGES} 
        InstallGen[pid, a, t, p] * capital_cost[pid, a, t, p]
	# Fixed Costs
	+ sum {(pid, a, t, p) in PROJECT_VINTAGES} 
	    Installed_To_Date_by_Period[pid, a, t, p] * fixed_o_m_by_period[pid, a, t, p]
	# Variable costs for non-storage projects
	+ sum {(pid, a, t) in PROJECTS, h in TIMEPOINTS} 
	    Power_Produced[pid, a, t, h] * (variable_cost[pid, a, t, h] + carbon_cost_per_mwh[t, h])
	# Variable costs for storage projects: currently attributed to the dispatch side of storage
	# for CAES, power output is apportioned between Power_Produced and ReleaseEnergy by storage_efficiency_caes through the constraint CAES_Combined_Dispatch
	+ sum {(pid, a, t) in PROJ_STORAGE, h in TIMEPOINTS, fc in RPS_FUEL_CATEGORY} 
	    ReleaseEnergy[pid, a, t, h, fc] * variable_cost[pid, a, t, h]
      
	#############################
	#    EXISTING PLANTS
	# Capital costs (sunk cost)
	+ sum {(a, e) in EXISTING_PLANTS: start_year < ep_end_year[a, e]}
	  ep_size_mw[a, e] * ep_capital_cost[a, e]
	# Calculate capital costs for all cogen plants that are operated beyond their expected retirement. 
	# This can be thought of as making payments into a capital replacement fund
	+ sum {(a, e, p) in EP_PERIODS: ep_could_be_operating_past_expected_lifetime[a, e, p]} 
      OperateEPDuringPeriod[a, e, p] * ep_size_mw[a, e] * ep_capital_cost_payment_per_period_to_extend_operation[a, e, p]
	# Calculate fixed costs for all existing plants
	+ sum {(a, e, p) in EP_PERIODS} 
      OperateEPDuringPeriod[a, e, p] * ep_size_mw[a, e] * ep_fixed_o_m_cost[a, e, p]
	# Calculate variable costs for all existing plants
	+ sum {(a,e,h) in EP_AVAILABLE_HOURS}
	  EP_Power_Produced[a, e, h] * (ep_variable_cost[a, e, h] + ep_carbon_cost_per_mwh[a, e, h])

	#############################
	# Hydro: cost per MW of operating the hydro fleet - no decision variables here because hydro is assumed to be run no matter what
	# TODO: divide hydro_cost_per_mw between nonpumped and pumped hydro projects
	+ sum {(a, pid) in PROJ_HYDRO} 
      hydro_cost_per_mw[a] * hydro_total_capacity[a, pid]

	########################################
	#    TRANSMISSION & DISTRIBUTION
	# Calculate the cost of installing new transmission lines between zones
	+ sum {(a1, a2) in TRANSMISSION_LINES, p in PERIODS} 
      InstallTrans[a1, a2, p] * transmission_cost_per_mw[a1, a2, p]
	# Sunk costs of operating the existing transmission grid
	+ transmission_sunk_cost
	# Calculate the cost of installing new local (intra-load area) transmission and distribution
	+ sum {a in LOAD_AREAS, p in PERIODS}
      InstallLocalTD[a, p] * local_td_cost_per_mw[a, p]
	# Sunk costs of operating the existing local (intra-load area) transmission and distribution
	+ local_td_sunk_cost
;

# this alternative objective is used to reduce transmission flows to
# zero in one direction of each pair, and to minimize needless flows
# around loops, or shipping of unneeded power to neighboring zones, 
# so it is more clear where surplus power is being generated
minimize Transmission_Usage:
  sum {(a1, a2) in TRANSMISSION_LINES, h in TIMEPOINTS, fc in RPS_FUEL_CATEGORY} 
    (DispatchTransFromXToY[a1, a2, h, fc]);


#### CONSTRAINTS ####

# Consumed power may not exceed net available power.
subject to Conservation_Of_Energy {a in LOAD_AREAS, h in TIMEPOINTS, fc in RPS_FUEL_CATEGORY}:
  ConsumePower[a,h,fc] <= Net_Power[a,h,fc];

# system needs to meet the load in each load area in each hour
# The output of plants is derated by outage rates to reflect occasional unavailability
# except for hydro... outage rates are already built into the data so they aren't included here
# (see the hydro constraints below)
# note: power is deemed to flow from a1 to a2 if positive, reverse if negative
subject to Satisfy_Load {a in LOAD_AREAS, h in TIMEPOINTS}:
	( sum{ fc in RPS_FUEL_CATEGORY} ConsumePower[a,h,fc] ) = system_load[a, h];


################################################################################
# same on a reserve basis
# note: these are not derated by forced outage rate, because that is incorporated in the reserve margin
subject to Satisfy_Load_Reserve {a in LOAD_AREAS, h in TIMEPOINTS}:

	#############################
	#    NEW PLANTS
  # new dispatchable capacity (no need to decide how to dispatch it; we just need to know it's available)
	( sum {(pid, a, t, p, h) in PROJ_DISPATCH_VINTAGE_HOURS: not storage[t]}
		InstallGen[pid, a, t, p] )
  # output from new intermittent projects. 
	+ ( sum {(pid, a, t, p, h) in PROJ_INTERMITTENT_VINTAGE_HOURS} 
		InstallGen[pid, a, t, p] * cap_factor[pid, a, t, h] )
  # new baseload plants
	+ ( sum {(pid, a, t, p, h) in NEW_BASELOAD_VINTAGE_HOURS} 
		InstallGen[pid, a, t, p] * ( 1 - scheduled_outage_rate[t] ) )
  # new storage projects
	+ sum {(pid, a, t) in PROJ_STORAGE} (
		ReleaseEnergyReserve[pid, a, t, h] - StoreEnergyReserve[pid, a, t, h] )
	#############################
	#    EXISTING PLANTS
  # existing dispatchable capacity
	+ ( sum {(a, e, h) in EP_DISPATCH_HOURS}
		OperateEPDuringPeriod[a, e, period[h]] * ep_size_mw[a, e] )
  # existing intermittent plants
	+ ( sum {(a, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS} 
		OperateEPDuringPeriod[a, e, period[h]] * ep_size_mw[a, e] * eip_cap_factor[a, e, h] )
  # existing baseload plants
	+ ( sum {(a, e, p) in EP_BASELOAD_PERIODS: p=period[h]} 
		OperateEPDuringPeriod[a, e, p] * ep_size_mw[a, e] * ( 1 - ep_scheduled_outage_rate[a, e] ) )

	#	HYDRO
  # non pumped hydro dispatch
	+ ( sum {(a, pid) in PROJ_NONPUMPED_HYDRO}
		Dispatch_NonPumped_Hydro_Reserve[a, pid, h] )
  # pumped hydro dispatch of water from upstream
	+ ( sum {(a, pid) in PROJ_PUMPED_HYDRO}
		Dispatch_Pumped_Hydro_Watershed_Electrons_Reserve[a, pid, h] )
  # pumped hydro storage and dispatch
	+ sum {(a, pid) in PROJ_PUMPED_HYDRO} (
		Dispatch_Pumped_Hydro_Storage_Reserve[a, pid, h] - Store_Pumped_Hydro_Reserve[a, pid, h] )

	########################################
	#    TRANSMISSION
  # Imports (have experienced transmission losses)
	+ ( sum {(a2, a) in TRANSMISSION_LINES}
		transmission_efficiency[a2, a] * DispatchTransFromXToY_Reserve[a2, a, h] )
  # Exports (have not experienced transmission losses)
	- ( sum {(a, a1) in TRANSMISSION_LINES}
		DispatchTransFromXToY_Reserve[a, a1, h] )

  >= system_load[a, h] * ( 1 + planning_reserve_margin );


#################################################
# RPS constraint
# windsun.run will drop this constraint if enable_rps is 0 (its default value)
subject to Satisfy_RPS {a in LOAD_AREAS, p in PERIODS: 
	rps_compliance_fraction_in_period[a, p] > 0 }:
    (sum { h in TIMEPOINTS, fc in RPS_FUEL_CATEGORY: 
           period[h] = p and fuel_qualifies_for_rps[a, fc] } 
      ConsumePower[a,h,fc] * hours_in_sample[h] )
  / ( sum {h in TIMEPOINTS: period[h]=p} system_load[a, h] * hours_in_sample[h] )
   >= rps_compliance_fraction_in_period[a, p];

################################################################################
# Operational Constraints

# system can only dispatch as much of each project as is EXPECTED to be available
# i.e., we only dispatch up to 1-forced_outage_rate, so the system will work on an expected-value basis
# (this is the base portfolio, more backup generators will be added later to get a lower year-round risk level)
subject to Maximum_DispatchGen 
  {(pid, a, t) in PROJ_DISPATCH, h in TIMEPOINTS: not storage[t]}:
  DispatchGen[pid, a, t, h] <= (1-forced_outage_rate[t]) * Installed_To_Date[pid, a, t, h];

# there are limits on total installations in certain projects
# TODO: adjust this to allow re-installing at the same site after retiring an earlier plant
# or even allow forced retiring of earlier plants if new technologies are better
subject to Maximum_Resource_Competing_Tech {l in LOCATIONS_WITH_COMPETING_TECHNOLOGIES}:
	sum {p in PERIODS, (pid, a, t) in PROJ_RESOURCE_LIMITED: 
			p >= min_build_year[t] + construction_time_years[t] and project_location[pid, a, t] = l} 
	InstallGen[pid, a, t, p] / capacity_limit_conversion[pid, a, t] 
		 <= capacity_limit_by_location[l];

subject to Maximum_Resource_Location_Unspecified { (pid, a, t) in PROJ_RESOURCE_LIMITED, p in PERIODS:
		not( project_location[pid, a, t] in LOCATIONS_WITH_COMPETING_TECHNOLOGIES ) }:
  Installed_To_Date_by_Period[pid, a, t, p] <= capacity_limit[pid, a, t] * capacity_limit_conversion[pid, a, t];

# Some generators (currently only Nuclear) have a minimum build size. This enforces that constraint
# If a generator is installed, then BuildGenOrNot is 1, and InstallGen has to be >= min_build_capacity
# If a generator is NOT installed, then BuildGenOrNot is 0, and InstallGen has to be >= 0
subject to Minimum_GenSize 
  {(pid, a, t, p) in PROJ_MIN_BUILD_VINTAGES}:
  InstallGen[pid, a, t, p] >= min_build_capacity[t] * BuildGenOrNot[pid, a, t, p];

# This binds BuildGenOrNot to InstallGen. The number below (1e6) is somewhat arbitrary. 
# I picked a number that would be far above the largest generator that would possibly be built
# If a generator is installed, then BuildGenOrNot is 1, and InstallGen has to be <= 0
# If a generator is NOT installed, then BuildGenOrNot is 0, and InstallGen can be between 0 & 1e6 - basically no upper limit
subject to BuildGenOrNot_Constraint 
  {(pid, a, t, p) in PROJ_MIN_BUILD_VINTAGES}:
  InstallGen[pid, a, t, p] <= 1000000 * BuildGenOrNot[pid, a, t, p];

# existing dispatchable plants can only be used if they are operational this period
subject to EP_Maximum_DispatchGen
  {(a, e, h) in EP_DISPATCH_HOURS}: DispatchEP[a, e, h] <= 
      OperateEPDuringPeriod[a, e, period[h]] * (1-ep_forced_outage_rate[a, e]) * ep_size_mw[a, e];

# system can only use as much transmission as is expected to be available
# note: transmission up and down the line both enter positively,
# but the form of the model allows them to both be reduced or increased by a constant,
# so they will both be held low enough to stay within the installed capacity
# (if there were a variable cost of operating, one of them would always go to zero)
# a quick follow-up model run minimizing transmission usage will push one of these to zero.
subject to Maximum_DispatchTransFromXToY
  {(a1, a2) in TRANSMISSION_LINES, h in TIMEPOINTS}:
  ( sum { fc in RPS_FUEL_CATEGORY } DispatchTransFromXToY[a1, a2, h, fc] )
    <= (1-transmission_forced_outage_rate) * 
          (existing_transfer_capacity_mw[a1, a2] + sum {(a1, a2, p, h) in TRANS_VINTAGE_HOURS} InstallTrans[a1, a2, p]);

# same on a reserve margin basis, but without the rps fuel category as rps doesn't apply to reserve margins
subject to Maximum_DispatchTransFromXToY_Reserve
  {(a1, a2) in TRANSMISSION_LINES, h in TIMEPOINTS}:
  DispatchTransFromXToY_Reserve[a1, a2, h]
    <= (existing_transfer_capacity_mw[a1, a2] + sum {(a1, a2, p, h) in TRANS_VINTAGE_HOURS} InstallTrans[a1, a2, p]);

# Simple fix to problem of asymetrical transmission build-out
subject to SymetricalTrans
  {(a1, a2) in TRANSMISSION_LINES, p in PERIODS}: InstallTrans[a1, a2, p] == InstallTrans[a2, a1, p];


# make sure there's enough intra-zone transmission and distribution capacity
# to handle the net distributed loads
# it is assumed that local T&D is needed up to the capacity planning margin
# because even at peak all loads aren't coincident
# and that local T&D is currently installed up to this margin (hence the max_coincident_load_for_local_td * (1 + planning_reserve_margin) ).
# TODO: find better data on how much Local T&D is needed above peak load
subject to Minimum_LocalTD 
  {a in LOAD_AREAS, h in TIMEPOINTS}:
  system_load[a, h] * ( 1 + planning_reserve_margin ) - existing_local_td[a]
    # New distributed PV
    - (sum {(pid, a, t) in PROJ_INTERMITTENT: t in SOLAR_DIST_PV_TECHNOLOGIES}
        (1-forced_outage_rate[t]) * cap_factor[pid, a, t, h] * Installed_To_Date[pid, a, t, h])
    # Existing distributed PV
    - (sum {(a, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS: ep_technology[a,e] in SOLAR_DIST_PV_TECHNOLOGIES }
    	OperateEPDuringPeriod[a, e, period[h]] * 
        (1-ep_forced_outage_rate[a, e]) * eip_cap_factor[a, e, h] * ep_size_mw[a, e] )
  <= sum {(a, p, h) in LOCAL_TD_HOURS} InstallLocalTD[a, p];

#################################
# Installable (non pumped hydro) Storage constraints - currently only Compressed Air Energy Storage (CAES)

# Energy output from CAES plants is apportioned into two separate decision variables: DispatchGen for the power attributable to NG combustion and ReleaseEnergy for the power attributable to stored energy. The ratio of NG:Stored is fixed at plant design and this constraint enforces that relationship. 
subject to CAES_Combined_Dispatch {(pid, a, t) in PROJ_STORAGE, h in TIMEPOINTS}:
  	(sum {fc in RPS_FUEL_CATEGORY} ReleaseEnergy[pid, a, t, h, fc] ) = 
  	  DispatchGen[pid, a, t, h] * caes_ng_to_storage_ratio;
 
# Maximum store rate for caes, derated for occasional forced outages
# StoreEnergy represents the load on the grid from storing electrons
subject to Maximum_Store_CAES {(pid, a, t) in PROJ_STORAGE, h in TIMEPOINTS}:
  	sum {fc in RPS_FUEL_CATEGORY} StoreEnergy[pid, a, t, h, fc]
  		<= Installed_To_Date[pid, a, t, h] * ( 1 - forced_outage_rate[t] ) * max_store_rate_caes;

# Maximum dispatch rate for caes, derated for occasional forced outages
subject to Maximum_Dispatch_CAES {(pid, a, t) in PROJ_STORAGE, h in TIMEPOINTS}:
  	(sum {fc in RPS_FUEL_CATEGORY} ReleaseEnergy[pid, a, t, h, fc] ) + Power_Produced[pid, a, t, h]
  		<= Installed_To_Date[pid, a, t, h] * ( 1 - forced_outage_rate[t] );

  # Energy balance
  # The parameter round_trip_efficiency below expresses the relationship between the amount of electricity from the grid used
  # to charge the storage device and the amount that is dispatched back to the grid.
  # For hybrid technologies like compressed-air energy storage (CAES), the round-trip efficiency will be higher than 1
  # because natural gas is added to run the turbine. For CAES, this parameter is therefore only a "partial energy balance,"
  # i.e. only one form of energy -- electricity -- is included in the balancing.
  # The energy balance for CAES should really be expressed as: sum(electricity in) + sum(natural gas in) = sum(electricity out) * k,
  # where k is the total round-trip efficiency for the CAES storage process.

  # ReleaseEnergy and StoreEnergy are derated for forced outages in Maximum_Dispatch_CAES and Maximum_Store_CAES respectivly
subject to Storage_Projects_Energy_Balance {(pid, a, t) in PROJ_STORAGE, d in DATES, fc in RPS_FUEL_CATEGORY}:
  	sum {h in TIMEPOINTS: date[h]=d} ReleaseEnergy[pid, a, t, h, fc]
  		= sum {h in TIMEPOINTS: date[h]=d} StoreEnergy[pid, a, t, h, fc] * storage_efficiency_caes;

# RESERVE - the same as above on a reserve margin basis
subject to Maximum_Store_CAES_Reserve {(pid, a, t) in PROJ_STORAGE, h in TIMEPOINTS}:
  	StoreEnergyReserve[pid, a, t, h]
  		<= Installed_To_Date[pid, a, t, h] * max_store_rate_caes;
subject to Maximum_Dispatch_CAES_Reserve {(pid, a, t) in PROJ_STORAGE, h in TIMEPOINTS}:
  	ReleaseEnergyReserve[pid, a, t, h]
  		<= Installed_To_Date[pid, a, t, h];
subject to Storage_Projects_Energy_Balance_Reserve {(pid, a, t) in PROJ_STORAGE, d in DATES}:
  	sum {h in TIMEPOINTS: date[h]=d} ReleaseEnergyReserve[pid, a, t, h]
  		= sum {h in TIMEPOINTS: date[h]=d} StoreEnergyReserve[pid, a, t, h] * round_trip_efficiency_caes;


#################################################
# Constraint: Min_Gen_Fraction_From_Solar
# The sum of system-wide power output by new and existing solar plants in the last investment period 
# (weighted by hours in each timepoint) must be greater than or equal to the policy target 
# (expressed as a fraction of system load)
#
# Note, by default windsun.run will drop this constraint. Set enable_min_solar_production to 1 to enable this constraint.
subject to Min_Gen_Fraction_From_Solar:
    # New solar plants power output in the last periods
	(sum {(pid, a, t) in PROJ_INTERMITTENT, h in TIMEPOINTS: 
	      t in SOLAR_TECHNOLOGIES and period[h] = last( PERIODS ) } 
        ( 1 - forced_outage_rate[t] ) * cap_factor[pid, a, t, h] * Installed_To_Date[pid, a, t, h] * hours_in_sample[h]) 
    # Existing solar plants power output in the last periods
    + (sum {(a, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS: 
        ep_technology[a,e] in SOLAR_TECHNOLOGIES and period[h] = last( PERIODS ) }
    	OperateEPDuringPeriod[a, e, period[h]] * 
        ( 1 - ep_forced_outage_rate[a,e] ) * eip_cap_factor[a, e, h]  * ep_size_mw[a, e] * hours_in_sample[h] )
    # The policy target expressed as a fraction of total load in the last period
    >=  min_solar_production * total_loads_by_period_weighted[ last( PERIODS ) ];


################################################################################
# HYDRO CONSTRAINTS

# note: hydro streamflow dispatch (Dispatch_NonPumped_Hydro and Dispatch_Pumped_Hydro_Watershed_Electrons)
# as done currently already includes scheduled and forced outages
# because the EIA data is on historical generation, not resource potential,
# therefore explicit outage rates are not included in hydro streamflow dispatch.
# TODO: use historical USGS stream flow and dam height data to estimate available hydro resource

#### NonPumped Hydro ####

# for every hour, the amount of water released can't be more than the turbine capacity
subject to Maximum_Dispatch_NonPumped_Hydro {(a, pid) in PROJ_NONPUMPED_HYDRO, h in TIMEPOINTS}:
  Dispatch_NonPumped_Hydro[a, pid, h] <= hydro_capacity_mw[a, pid, date[h]];

# for every hour, the amount of water released can't be less than that necessary to maintain stream flow
subject to Minimum_Dispatch_NonPumped_Hydro {(a, pid) in PROJ_NONPUMPED_HYDRO, h in TIMEPOINTS}:
  Dispatch_NonPumped_Hydro[a, pid, h] >= avg_hydro_output[a, pid, date[h]] * min_nonpumped_hydro_dispatch_fraction;

# for every day, the historical monthly average flow must be met
subject to Average_NonPumped_Hydro_Output {(a, pid) in PROJ_NONPUMPED_HYDRO, d in DATES}:
  sum {h in TIMEPOINTS: date[h]=d} Dispatch_NonPumped_Hydro[a, pid, h] = 
# The sum below is equivalent to the daily hydro flow, but only over the study hours considered in each day
  sum {h in TIMEPOINTS: date[h]=d} avg_hydro_output[a, pid, d];

# NonPumped Hydro Reserve
# as the amount of reserve available from hydro plants isn't infinite,
# the reserve must be dispatched on similar terms to the actual energy dispatch
subject to Maximum_Dispatch_NonPumped_Hydro_Reserve {(a, pid) in PROJ_NONPUMPED_HYDRO, h in TIMEPOINTS}:
  Dispatch_NonPumped_Hydro_Reserve[a, pid, h] <= hydro_capacity_mw[a, pid, date[h]];
subject to Minimum_Dispatch_NonPumped_Hydro_Reserve {(a, pid) in PROJ_NONPUMPED_HYDRO, h in TIMEPOINTS}:
  Dispatch_NonPumped_Hydro_Reserve[a, pid, h] >= avg_hydro_output[a, pid, date[h]] * min_nonpumped_hydro_dispatch_fraction;
subject to Average_NonPumped_Hydro_Output_Reserve {(a, pid) in PROJ_NONPUMPED_HYDRO, d in DATES}:
  sum {h in TIMEPOINTS: date[h]=d} Dispatch_NonPumped_Hydro_Reserve[a, pid, h] = 
  sum {h in TIMEPOINTS: date[h]=d} avg_hydro_output[a, pid, d];


#### Pumped Hydro ####

# The variable Store_Pumped_Hydro represents the MW of electricity required to pump water uphill (the load on the grid from pumping)
# To represent efficiency losses, the electrons stored by Store_Pumped_Hydro are then derated by the pumped_hydro_efficiency when dispatched
# so the stock of MW available to be dispatched from pumping hydro projects 
# is anything already in the upstream flow (Dispatch_Pumped_Hydro_Watershed_Electrons) plus Store_Pumped_Hydro * pumped_hydro_efficiency

# RPS for Pumped Hydro storage: electrons come in three RPS colors:
# any electron that is from upstream gets labeled blue - i.e. whatever color hydro is... currently this equates to brown
# also, any stored electron (less the pumped_hydro_efficiency) must retain its color - either brown or green 

# for every hour, the amount of water released can't be more than the turbine capacity
# the contribution from Dispatch_Pumped_Hydro_Storage is derated by the forced outage rate because storage decisions are completly internal to the model
# (hydro streamflow decisions have the outage rates built in, but the storage dispatch decisions have been split off from these)
# it's written somewhat strangely here because Dispatch_Pumped_Hydro_Watershed_Electrons is not derated:
# dividing by ( 1 - forced_outage_rate_hydro ) effectivly takes up more of the dam capacity in any given hour than a non-derated dispatch variable would
subject to Maximum_Dispatch_Pumped_Hydro {(a, pid) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS}:
 	Dispatch_Pumped_Hydro_Watershed_Electrons[a, pid, h]
	+ sum{ fc in RPS_FUEL_CATEGORY } Dispatch_Pumped_Hydro_Storage[a, pid, h, fc] / ( 1 - forced_outage_rate_hydro )
    <= hydro_capacity_mw[a, pid, date[h]];

# Can't pump more water uphill than the pump capacity (in MW)
# As mentioned above, Store_Pumped_Hydro represents the grid load of storage
# so the storage efficiency is taken into account in dispatch
# TODO: Research how MW pumping capacity translates into water flows - 
# it's unclear whether these pumps can only take their capacity_mw in load,
# or if they can take capacity_mw / pumped_hydro_efficiency in load thereby storing their capacity_mw uphill.
# We'll take the conservative assumption here that they can only store capacity_mw * pumped_hydro_efficiency
# Also, the maximum storage rate is derated by the forced hydro outage rate, as these decisions are internal to the model
subject to Maximum_Store_Pumped_Hydro {(a, pid) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS}:
  sum {fc in RPS_FUEL_CATEGORY} Store_Pumped_Hydro[a, pid, h, fc] <= hydro_capacity_mw[a, pid, date[h]] * ( 1 - forced_outage_rate_hydro ) ;

# for every day, the historical monthly average flow must be met to maintain downstream flow
# these electrons will be labeled blue by other constraints
# as there is a lower resevoir below the dam for each pumped hydro project,
# there is no accompanying minimum output from streamflow constraint (similar to Minimum_Dispatch_NonPumped_Hydro above)
# because water can be released from the lower reservoir at will into the stream
subject to Average_Pumped_Hydro_Watershed_Output {(a, pid) in PROJ_PUMPED_HYDRO, d in DATES}:
  sum {h in TIMEPOINTS: date[h]=d} Dispatch_Pumped_Hydro_Watershed_Electrons[a, pid, h] = 
# The sum below is equivalent to the daily hydro flow, but only over the study hours considered in each day
  sum {h in TIMEPOINTS: date[h]=d} avg_hydro_output[a, pid, d];

# Conservation of STORED electrons (electrons not from upstream) for pumped hydro
# Pumped hydro has to dispatch all electrons it stored each day for each fuel type such that 
# over the course of a day pumped hydro projects release the necessary amount of water downstream
subject to Conservation_Of_Stored_Pumped_Hydro_Electrons {(a, pid) in PROJ_PUMPED_HYDRO, d in DATES, fc in RPS_FUEL_CATEGORY}:
	sum {h in TIMEPOINTS: date[h]=d} Dispatch_Pumped_Hydro_Storage[a, pid, h, fc] = 
	sum {h in TIMEPOINTS: date[h]=d} Store_Pumped_Hydro[a, pid, h, fc] * pumped_hydro_efficiency;


# Pumped Hydro Reserve
# This is basically an independent operational plan for hydro that can ensure average flow rates while maintain a reserve margin. This contigency plan is overkill for short-lived events (hours) that require tapping into the reserve margin. This contigency plan is needed for long-lasting events (days or weeks) that require maintenance of average stream flow.

# as the reserve margin doesn't have an RPS flavor, these constraints don't include the fuel type

# as with other reserve margin constraints, the forced outage rates are removed here, because this is built into the reserve margin
subject to Maximum_Dispatch_Pumped_Hydro_Reserve {(a, pid) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS}:
	Dispatch_Pumped_Hydro_Watershed_Electrons_Reserve[a, pid, h] + Dispatch_Pumped_Hydro_Storage_Reserve[a, pid, h]
    <= hydro_capacity_mw[a, pid, date[h]];
subject to Average_Pumped_Hydro_Watershed_Output_Reserve {(a, pid) in PROJ_PUMPED_HYDRO, d in DATES}:
  sum {h in TIMEPOINTS: date[h]=d} Dispatch_Pumped_Hydro_Watershed_Electrons_Reserve[a, pid, h] = 
  sum {h in TIMEPOINTS: date[h]=d} avg_hydro_output[a, pid, d];
subject to Conservation_Of_Stored_Pumped_Hydro_Electrons_Reserve {(a, pid) in PROJ_PUMPED_HYDRO, d in DATES}:
	sum {h in TIMEPOINTS: date[h]=d} Dispatch_Pumped_Hydro_Storage_Reserve[a, pid, h] = 
	sum {h in TIMEPOINTS: date[h]=d} Store_Pumped_Hydro_Reserve[a, pid, h] * pumped_hydro_efficiency;
# Can't pump more water uphill than the pump capacity (in MW)
subject to Maximum_Store_Pumped_Hydro_Reserve {(a, pid) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS}:
  sum {fc in RPS_FUEL_CATEGORY} Store_Pumped_Hydro_Reserve[a, pid, h] <= hydro_capacity_mw[a, pid, date[h]];
