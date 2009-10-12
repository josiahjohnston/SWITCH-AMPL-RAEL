# updated to include hydro 11/7/07
# major update  11/28/07
#   to specify study periods exogenously and allow samples that cover fractional
#   numbers of hours
# updated 12/13/07 
#   to assume whole days are sampled, and apply each month's hydro limits to each full
#   day. this is necessary to incorporate any sort of stored-resource dispatch, because
#   if the dispatch model works with randomly sampled hours, each day will have a
#   flatter set of hourly conditions than is realistic (i.e., the day will include
#   some high-wind and some low-wind hours, so that the total storage needed for the
#   day is close to zero. In reality, there will be some days that are windy all day
#   and some that have low-wind all day.) Unfortunately, until the model can be greatly
#   expanded, it won't be able to do multi-day storage and dispatch decisions. The
#   previous system used seasonal dispatch rules for hydro, but that could allow
#   "storage" of power during a sample that comes from a low-hydro year and then using
#   more stored power during a sample that comes from a high-hydro year. This system 
#   uses (used) hourly dispatch for all hydro facilities, but that was slow.
# updated 12/24/07
#   to dispatch simple hydro using season-hour rules (as before 12/13/07)
#   and to include pumped hydro, with each facility dispatched hourly 
#   (as was done with simple hydro in the 12/13/07 version)
#   season-hour rules are quicker to optimize (2200 s instead of 4400 s) 
#   and allow more renewables (66.2% instead of 65.2%), 
#   but are hard to use for pumped hydro because of the round-trip efficiency losses
#   (solution time is about 900 s with season-hour rules and no pumped hydro)
# added transmission line losses 12/28/07, to be more realistic and to make the model
#   prefer to dispatch local gas plants instead of ones in other zones 
#   (adds about 10% to solution time)
# 1/16/08: added existing power plants and transmission lines 
#   (solution time for $85, with individual hydro dispatch: 8400 s; 150-300 s to move to $80 solution)
# 2/7/08: added variables and constraints to ensure 15% extra capacity every hour 
#   (solution time for $85 with indiv. hydro: 19191 s; then 440s to move from $85 solution to $80)
#   LP Presolve eliminated 455594 rows and 161015 columns.
#   Reduced LP has 261551 rows, 508642 columns, and 6973630 nonzeros.
#   Barrier method:
# ***NOTE: Found 76 dense columns.
# Number of nonzeros in lower triangle of A*A' = 163698997
# Using Nested Dissection ordering
# Total time for automatic ordering = 3204.36 sec.
# Summary statistics for Cholesky factor:
#   Rows in Factor            = 261627
#   Integer space required    = 2399027
#   Total non-zeros in factor = 744509101
#   Total FP ops to factor    = 4348384748541
# (16 hours to solve)
# 2/8/08: switched reserve calculation to use total capacity of new and existing dispatchable 
#   (non-hydro) plants, and not to calculate hourly dispatch for them. (no effect on problem size or solution time)
# 3/14/08: 
#   changed ep_fixed_cost calculation to discount annual costs within each period to the start of the period
#   changed objective function to (correctly) multiply ep_capital_cost and ep_fixed_cost by the size of each plant
#   switched to 4x4-year periods, beginning in 2010, instead of 4x3-year periods beginning in 2015
#   added peak load days (with 1-day's weight) during each month
#   (solution time is now 94000 s with indiv. hydro, hourly dispatch of reserves, $80 carbon tax; 3300 s to move from $80 to $90)
# 4/28/08: lots of little changes
#  converted transmission dispatch constraints to be bidirectional, and use the known wecc path limits where applicable
#  switched transmission constraint from forward + backward <= limit to forward <= limit, backward <= limit
#  added a (crude) calculation for the "cost" of existing hydro plants
#  changed date indexing in source data so each simulated date is uniquely indexed, 
#   even if the same historical date is used in multiple investment periods
#   (still can't refer to the same historical date twice in the same investment period, but there's no reason to do that anyway)
#  added small hydro (<50MW) plants to the source data, with min=avg=max requirement (i.e., in baseload mode)
#  changed wind data to convert estimated production for 2020 turbines into 2010 values,
#    and improved the creation of augmented, low-speed wind sites
#  removed redundant vintage range specification from EP_BASELOAD_PERIODS definition
#    because it was already specified in EP_PERIODS
#  added data and calculations for the cost of connecting new projects to the grid
#    these are either given generically, as connect_cost_per_mw_generic,
#    or the connect_length_km (for an added line) and connect_cost_per_mw (for grid upgrades)
#    are specified for each new project
# 06/29/09 Josiah and Jimmy Regionalized plant costs
# 07/03/09 Jimmy (attempted) to make costs all in $/MW instead of the previous mix of $/MW and $/kW.
# 	 and also added Biomass

###############################################
#
# Time-tracking parameters
#

set YEARS ordered; # all possible years
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

# note: periods must be evenly spaced and count by years, 
# but they can have decimals (e.g., 2006.5 for July 1, 2006)
# and be any distance apart.
# VINTAGE_YEARS are a synonym for PERIODS, but refer more explicitly
# the date when a power plant starts running.
set PERIODS ordered = setof {h in TIMEPOINTS} (period[h]);
set VINTAGE_YEARS ordered = PERIODS;

# specific dates are used to collect hours that are part of the same
# day, for the purpose of hydro dispatch, etc.
set DATES ordered = setof {h in TIMEPOINTS} (date[h]);

set HOURS_OF_DAY ordered = setof {h in TIMEPOINTS} (hour_of_day[h]);
set MONTHS_OF_YEAR ordered = setof {h in TIMEPOINTS} (month_of_year[h]);
set SEASONS_OF_YEAR ordered = setof {h in TIMEPOINTS} (season_of_year[h]);

# the date (year and fraction) when the optimization starts
param start_year = first(PERIODS);

# interval between study periods
param years_per_period = (last(PERIODS)-first(PERIODS))/(card(PERIODS)-1);

# the first year that is beyond the simulation
# (i.e., this would be the first year of the next simulation, if there were one)
param end_year = last(PERIODS)+years_per_period;

###############################################
#
# System loads and zones
#

# list of all load zones in the state
# it is ordered, so they are listed from north to south
set LOAD_AREAS ordered;

# system load (MW)
param system_load {LOAD_AREAS, TIMEPOINTS} >= 0;

# Regional cost multipliers
param economic_multiplier {LOAD_AREAS} >= 0;



###############################################
# Solar run parameters

# Minimum amount of electricity that solar must produce
param min_solar_production >= 0, <= 1;

# Minimum amount of electricity that solar must produce
param enable_min_solar_production;

# Solar-based technologies
set SOLAR_TECHNOLOGIES;


###############################################
#
# Technology specifications for generators
# (most of these come from generator_info.tab)

set TECHNOLOGIES;

# list of all possible fuels
set FUELS; 

# Reference to hydro's "fuel": Water
param fuel_hydro symbolic in FUELS;

# fuel used by this type of plant
param fuel {TECHNOLOGIES} symbolic in FUELS;

# earliest time when each technology can be built
param min_build_year {TECHNOLOGIES} >= 0;

# heat rate (in Btu/kWh)
param heat_rate {TECHNOLOGIES} >= 0;

# construction lead time (years)
param construction_time_years {TECHNOLOGIES} >= 0;

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

# can this type of project only be installed in limited amounts?
param min_build_capacity {TECHNOLOGIES} >= 0;



###############################################
#
# Generator costs by technology & region
# (most of these come from regional_generator_costs.tab or windsun.dat)

# list of all available technologies (from the generator cost table)
set REGIONAL_TECHNOLOGIES dimen 2;

# year for which the price of each technology has been specified
param price_year {REGIONAL_TECHNOLOGIES} >= 0;

# overnight cost for the plant ($/MW)
param overnight_cost {REGIONAL_TECHNOLOGIES} >= 0;

# cost of grid upgrades to deliver power from the new plant to the "center" of the load zone
# (specified generically for all projects of a given technology, also specified per-project below.
# if specified in both places, the two will be summed; usually one of them will be zero.)
param connect_cost_per_mw_generic {REGIONAL_TECHNOLOGIES} >= 0;

# fixed O&M ($/MW-year)
param fixed_o_m {REGIONAL_TECHNOLOGIES} >= 0;

# variable O&M ($/MWh)
param variable_o_m {REGIONAL_TECHNOLOGIES} >= 0;
# unused parameter for changing o&m
param variable_o_m_change {REGIONAL_TECHNOLOGIES};

# annual rate of change of overnight cost, beginning at price_year
param overnight_cost_change {REGIONAL_TECHNOLOGIES};

# annual rate of change of fixed O&M, beginning at min_build_year
param fixed_o_m_change {REGIONAL_TECHNOLOGIES};


##################################################################
#
# RPS goals for each load area 
# (these come from generator_rps.tab and rps_requirement.tab)

set LOAD_AREAS_AND_FUEL_CATEGORY dimen 2;
set RPS_FUEL_CATEGORY = setof {(load_area, rps_fuel_category) in LOAD_AREAS_AND_FUEL_CATEGORY} (rps_fuel_category);
set LOAD_AREAS_WITH_RPS dimen 1;

param enable_rps;

# rps goals for each load area
param rps_compliance_percentage {LOAD_AREAS_WITH_RPS};

# whether fuels in a load area qualify for rps 
param fuel_qualifies_for_rps {LOAD_AREAS_AND_FUEL_CATEGORY};

# determines if fuel falls in solar/wind/geo or gas/coal/nuclear/hydro
param rps_fuel_category {FUELS} symbolic in RPS_FUEL_CATEGORY;

# determines which LOAD_AREAS have rps_requirements 
param load_area_rps_policy {LOAD_AREAS_WITH_RPS};

# What year each zone needs to meet its RPS goal
param rps_compliance_year {LOAD_AREAS_WITH_RPS};
param period_rps_takes_effect {z in LOAD_AREAS_WITH_RPS} = 
	years_per_period * round( ( rps_compliance_year[z] - start_year) / years_per_period ) + start_year;

###############################################
# Project data

# default values for projects that don't have sites or configurations
param site_unspecified symbolic;
param configuration_unspecified symbolic;

# Names of technologies that have capacity factors or maximum capacities 
# tied to specific locations. 
param tech_distributed_pv symbolic in TECHNOLOGIES;
param tech_csp_trough symbolic in TECHNOLOGIES;
param tech_wind symbolic in TECHNOLOGIES;
param tech_offshore_wind symbolic in TECHNOLOGIES;
param tech_biomass symbolic in TECHNOLOGIES;

# names of other technologies, just to have them around 
# (but this is getting silly)
param tech_ccgt symbolic in TECHNOLOGIES;
param tech_combustion_turbine symbolic in TECHNOLOGIES;

# maximum capacity factors (%) for each project, each hour. 
# generally based on renewable resources available
set PROJ_INTERMITTENT_HOURS dimen 5;  # LOAD_AREAS, TECHNOLOGIES, SITES, CONFIGURATIONS, TIMEPOINTS
set PROJ_INTERMITTENT = setof {(z, t, s, o, h) in PROJ_INTERMITTENT_HOURS} (z, t, s, o);

param cap_factor {PROJ_INTERMITTENT_HOURS} >= 0;

# make sure all hours are represented
check {(z, t, s, o) in PROJ_INTERMITTENT, h in TIMEPOINTS}: cap_factor[z, t, s, o, h] >= 0;
# cap factors for solar can be greater than 1 becasue sometimes the sun shines more than 1000W/m^2
# which is how PV cap factors are defined.
# The below checks make sure that for other plants the cap factors
# are <= 1 but for solar they are <= 1.4
# (roughly the irradiation coming in from space, though the cap factor shouldn't ever approach this number)
check {(z, t, s, o) in PROJ_INTERMITTENT, h in TIMEPOINTS: not( t in SOLAR_TECHNOLOGIES )}: cap_factor[z, t, s, o, h] <= 1;
check {(z, t, s, o) in PROJ_INTERMITTENT, h in TIMEPOINTS: t in SOLAR_TECHNOLOGIES }: cap_factor[z, t, s, o, h] <= 1.4;
check {(z, t, s, o) in PROJ_INTERMITTENT}: intermittent[t];

# maximum capacity (MW) that can be installed in each project
set PROJ_RESOURCE_LIMITED_SITES dimen 3;  # LOAD_AREAS, TECHNOLOGIES, SITES
set PROJ_RESOURCE_LIMITED = 
	PROJ_INTERMITTENT
	union 
	setof {(z, t, s) in PROJ_RESOURCE_LIMITED_SITES: not intermittent[t]} (z, t, s, configuration_unspecified);
check {(z, t, s, o) in PROJ_RESOURCE_LIMITED}: resource_limited[t];
param max_capacity {PROJ_RESOURCE_LIMITED_SITES} >= 0;

# all other types of project (dispatchable and installable anywhere)
set PROJ_ANYWHERE =
	setof {(z,t) in REGIONAL_TECHNOLOGIES: not intermittent[t] and not resource_limited[t]} (z, t, site_unspecified, configuration_unspecified);


# hydro is resource limited but not intermittent
# solar troughs are intermittent but not resource limited - not true anymore!!!!
# so we union all the possibilities
set PROJECTS = 
  PROJ_ANYWHERE 
  union PROJ_INTERMITTENT
  union PROJ_RESOURCE_LIMITED;

# the set of all dispatchable projects (i.e., non-intermittent)
set PROJ_DISPATCH = {(z, t, s, o) in PROJECTS: not new_baseload[t] and not intermittent[t]};

# sets derived from site-specific tables, help keep projects distinct
set SITES = setof {(z, t, s, o) in PROJECTS} (s);
set CONFIGURATIONS = setof {(z, t, s, o) in PROJECTS} (o);

# cost of grid upgrades to support a new project, in dollars per peak MW.
# these are needed in order to deliver power from the interconnect point to
# the load center (or make it deliverable to other zones)
param connect_cost_per_mw {(z, t, s) in PROJ_RESOURCE_LIMITED_SITES} >= 0 default 0;

##############################################
# Existing hydro plants (assumed impossible to build more, but these last forever)

# forced outage rate for hydroelectric dams
# this is used to de-rate the planned power production
param forced_outage_rate_hydro >= 0;

# round-trip efficiency for storing power via a pumped hydro system
param pumped_hydro_efficiency >= 0;

# annual cost for existing hydro plants (see notes in windsun.dat)
# it would be better to calculate this from the capital cost, fixed and variable O&M,
# but that introduces messy new parameters and doesn't add anything to the analysis
param hydro_annual_payment_per_mw >= 0;

# indexing sets for hydro data (read in along with data tables)
# (this should probably be monthly data, but this has equivalent effect,
# and doesn't require adding a month dataset and month <-> date links)
set PROJ_HYDRO_DATES dimen 3; # load_area, site, date

# minimum, maximum and average flow (in average MW) at each dam, each day
# (note: we assume that the average dispatch for each day must come out at this average level,
# and flow will always be between minimum and maximum levels)
# maximum is based on plant size
# average is based on historical power production for each month
# for simple hydro, minimum flow is a fixed fraction of average flow (for now)
# for pumped hydro, minimum flow is a negative value, showing the maximum pumping rate
param avg_hydro_flow {PROJ_HYDRO_DATES};
param max_hydro_flow {PROJ_HYDRO_DATES};
param min_hydro_flow {PROJ_HYDRO_DATES};
check {(z, s, d) in PROJ_HYDRO_DATES}: 
  min_hydro_flow[z, s, d] <= avg_hydro_flow[z, s, d] <= max_hydro_flow[z, s, d];
check {(z, s, d) in PROJ_HYDRO_DATES}: 
  max_hydro_flow[z, s, d] >= 0;

# list of all hydroelectric projects (pumped or simple)
set PROJ_HYDRO = setof {(z, s, d) in PROJ_HYDRO_DATES} (z, s);

# pumped hydro projects (have negative minimum flows at some point)
# or any projects that should get individual-hour dispatch
# set PROJ_PUMPED_HYDRO = setof {(z, s, d) in PROJ_HYDRO_DATES} (z, s);
# the next two limits are equivalent (they give individual dispatch of all large hydro, and aggregated dispatch of small, baseload hydro)
# set PROJ_PUMPED_HYDRO = setof {(z, s, d) in PROJ_HYDRO_DATES: min_hydro_flow[z, s, d] < 0 or z="Northwest" or max_hydro_flow[z, s, d] >= 50} (z, s);
# set PROJ_PUMPED_HYDRO = setof {(z, s, d) in PROJ_HYDRO_DATES: min_hydro_flow[z, s, d] < 0.9999 * avg_hydro_flow[z, s, d]} (z, s);
set PROJ_PUMPED_HYDRO = setof {(z, s, d) in PROJ_HYDRO_DATES: min_hydro_flow[z, s, d] < 0 or z="Northwest" or max_hydro_flow[z, s, d] >= 100} (z, s);
# set PROJ_PUMPED_HYDRO = setof {(z, s, d) in PROJ_HYDRO_DATES: min_hydro_flow[z, s, d] < 0 or z="Northwest"} (z, s);

# model can fit in 32-bit cplex with installtrans fixed, or with individual dispatch only for hydro sites >= 100 MW. 
# it cannot fit if installtrans is free and sites between 50 and 100 MW are dispatched individually.

# simple hydro projects (everything else)
set PROJ_SIMPLE_HYDRO = PROJ_HYDRO diff PROJ_PUMPED_HYDRO;

# make sure the data tables have full, matching sets of data
 check card(DATES symdiff setof {(z, s, d) in PROJ_HYDRO_DATES} (d)) = 0;
 check card(PROJ_HYDRO_DATES) = card(PROJ_HYDRO) * card(DATES);

#################
# simple hydro projects are dispatched on a linearized, aggregated basis in each zone
# the code below sets up parameters for this.

# maximum share of each day's "discretionary" hydro flow 
# (everything between the minimum_hydro_flow and the average_hydro_flow) 
# that can be dispatched in a single hour
# Higher values will produce narrower, taller hydro dispatch schedules,
# but also more "baseload" hydro.
param max_hydro_dispatch_per_hour;

# minimum and maximum flow rates for each simple hydro facility,
# dispatched on a linearized, aggregated basis.
param min_hydro_dispatch {(z, s) in PROJ_SIMPLE_HYDRO, d in DATES} =
  max(
    # if the avg_hydro_flow is close to the max_hydro_flow for this site, then we need to increase the 
    # minimum flow rate, reducing the amount of  "discretionary" hydro, so that when max_hydro_dispatch_per_hour
    # is dispatched, it won't overshoot the max_hydro_flow for this site.
    (max_hydro_dispatch_per_hour * 24 * avg_hydro_flow[z, s, d] - max_hydro_flow[z, s, d]) 
      / (max_hydro_dispatch_per_hour * 24 - 1),

    # in other cases, we just respect the lower flow limit for the site.
    min_hydro_flow[z, s, d]
  );
# make sure we'll never overshoot maximum allowed production
check {(z, s) in PROJ_SIMPLE_HYDRO, d in DATES}: 
  min_hydro_dispatch[z, s, d] 
  + max_hydro_dispatch_per_hour * (avg_hydro_flow[z, s, d] - min_hydro_dispatch[z, s, d]) * 24
    <= max_hydro_flow[z, s, d] * 1.001;

# pre-aggregate the available simple hydro supply for use in the satisfy_load constraint
param min_hydro_dispatch_all_sites {z in LOAD_AREAS, d in DATES} 
  = sum {(z, s) in PROJ_SIMPLE_HYDRO} min_hydro_dispatch[z, s, d];
param avg_hydro_dispatch_all_sites {z in LOAD_AREAS, d in DATES} 
  = sum {(z, s) in PROJ_SIMPLE_HYDRO} avg_hydro_flow[z, s, d];


###############################################
# Existing generators

# name of each plant
set EXISTING_PLANTS dimen 2;  # load zone, plant code

check {z in setof {(z, e) in EXISTING_PLANTS} (z)}: z in LOAD_AREAS;

# the size of the plant in MW
param ep_size_mw {EXISTING_PLANTS} >= 0;

# type of technology used by the plant
# This variable needs to have the check symbolic in TECHNOLOGIES, but we don't know all of the generators technologies for all of the existing plants. 
set TECHNOLOGIES_AND_UNKNOWN = TECHNOLOGIES union { "unknown" };
param ep_technology {EXISTING_PLANTS} symbolic in TECHNOLOGIES_AND_UNKNOWN;

# type of fuel used by the plant
param ep_fuel {EXISTING_PLANTS} symbolic in FUELS;

# heat rate (in Btu/kWh)
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
# note: this is also used for plants that only run part time
# e.g., a baseload-type plant with 97% reliability but 80% capacity factor
param ep_scheduled_outage_rate {EXISTING_PLANTS} >= 0, <= 1;

# does the generator run at its full capacity all year?
param ep_baseload {EXISTING_PLANTS} binary;

# is the generator part of a cogen facility (used for reporting)?
param ep_cogen {EXISTING_PLANTS} binary;

# is the generator intermittent (i.e. is its power production non-dispatchable)?
param ep_intermittent {EXISTING_PLANTS} binary;

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
param local_td_annual_payment_per_mw >= 0;


###################
#
# Financial data and calculations
#

# the year to which all costs should be discounted
param base_year >= 0;

# annual rate (real) to use to discount future costs to current year
param discount_rate;

# required rates of return (real) for generator and transmission investments
# may differ between generator types, and between generators and transmission lines
param finance_rate {TECHNOLOGIES} >= 0;
param transmission_finance_rate >= 0;

# cost of carbon emissions ($/ton), e.g., from a carbon tax
# can also be set negative to drive renewables out of the system
param carbon_cost;

# set and parameters used to make carbon cost curves
set CARBON_COSTS;

# annual fuel price forecast
# old: param fuel_price {YEARS, FUELS} default 0, >= 0;
param fuel_price {LOAD_AREAS, FUELS, YEARS} default 0, >= 0;

# carbon content (tons) per million Btu of each fuel
param carbon_content {FUELS} default 0, >= 0;

# Calculate discounted fixed and variable costs for each technology and vintage

# For now, all hours in each study period use the fuel cost 
# from the year when each study period started.
# This is because we don't want artificially strong run-ups in fuel prices
# between the beginning and end of each study period as a result of the long intervals
# needed to make it solvable.
# This could be updated to use fuel costs that vary by month,
# or for an hourly model, it could interpolate between annual forecasts 
# (see versions of this model from before 11/27/07 for code to do that).
param fuel_cost_hourly {z in LOAD_AREAS, f in FUELS, h in TIMEPOINTS} := fuel_price[z, f, floor(period[h])];

# planning reserve margin - fractional extra load the system must be able able to serve
# when there are no forced outages
param planning_reserve_margin;

##########
# calculate discounted costs for new plants

# apply projected annual real cost changes to each technology,
# to get the capital, fixed and variable costs if it is installed 
# at each possible vintage date

# first, the capital cost of the plant and any 
# interconnecting lines and grid upgrades
# (all costs are in $/MW)
param capital_cost_proj {(z, t, s, o) in PROJECTS, v in VINTAGE_YEARS} = 
  ( overnight_cost[z,t] * (1+overnight_cost_change[z,t])^(v - construction_time_years[t] - price_year[z,t])
    + connect_cost_per_mw_generic[z,t] 
    + connect_cost_per_mw[z, t, s]
  )
; 

# The O&M change is locked in when the shovel hits the ground (implicitly assumes that the installed tech is the most significant influence on this change)
param fixed_o_m_cost_proj {(z,t) in REGIONAL_TECHNOLOGIES, v in VINTAGE_YEARS} = 
  fixed_o_m[z,t] * (1+fixed_o_m_change[z,t])^(v - construction_time_years[t] - price_year[z,t]);
# earlier versions also assumed that variable costs declined for future vintages,
# but this version does not, because the changes were minor, hard to support,
# and required separate dispatch decisions for every vintage of every technology,
# which needlessly expands the model.

# annual revenue that will be needed to cover the capital cost
param capital_cost_annual_payment {(z, t, s, o) in PROJECTS, v in VINTAGE_YEARS} = 
  finance_rate[t] * (1 + 1/((1+finance_rate[t])^(max_age_years[t] + construction_time_years[t])-1)) * capital_cost_proj[z, t, s, o, v];

# date when a plant of each type and vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made) 
# until the end of that period. This avoids having artificial gaps
# between retirements and starting new plants.
param project_end_year {t in TECHNOLOGIES, v in VINTAGE_YEARS} =
  min(end_year, v+ceil(max_age_years[t]/years_per_period)*years_per_period);

# finally, take the stream of capital & fixed costs over the duration of the project,
# and discount to a lump-sum value at the start of the project,
# then discount from there to the base_year.
param fixed_cost {(z, t, s, o) in PROJECTS, v in VINTAGE_YEARS} = 
  # Capital payments that are paid from when construction starts till the plant is retired (or the study period ends)
  capital_cost_annual_payment[z,t,s,o,v]
    # A factor to convert Uniform annual capital payments to "Present value" in the construction year - a lump sum at the beginning of the payments. This considers the time from when construction began to the end year
    * (1-(1/(1+discount_rate)^(project_end_year[t,v] - v + construction_time_years[t])))/discount_rate
    # Future value (in the construction year) to Present value (in the base year)
    * 1/(1+discount_rate)^(v-construction_time_years[t]-base_year)
+
  # Fixed annual costs that are paid while the plant is operating (up to the end of the study period)
  fixed_o_m_cost_proj[z,t,v]
    # U to P, from the time the plant comes online to the end year
    * (1-(1/(1+discount_rate)^(project_end_year[t,v]-v)))/discount_rate
    # F to P, from the time the plant comes online to the base year
    * 1/(1+discount_rate)^(v-base_year);

# all variable costs ($/MWh) for generating a MWh of electricity in some
# future hour, using a particular technology and vintage, 
# discounted to reference year
# these include O&M, fuel, carbon tax
# note: we divide heat_rate by 1000 to go from Btu/kWh to MBtu/MWh
# We also multiply by the number of real hours represented by each sample,
# because a case study could use only a limited subset of hours.
# (this used to vary by vintage to allow for changing variable costs, but not anymore)
# note: in a full hourly model, this should discount each hour based on its exact date,
# but for now, since the hours are non-chronological samples within each study period,
# they are all discounted by the same factor
param variable_cost {(z,t) in REGIONAL_TECHNOLOGIES, h in TIMEPOINTS} =
  hours_in_sample[h] * (
    variable_o_m[z,t] + heat_rate[t]/1000 * fuel_cost_hourly[z, fuel[t], h]
  ) * 1/(1+discount_rate)^(period[h]-base_year);

param carbon_cost_per_mwh {t in TECHNOLOGIES, h in TIMEPOINTS} = 
  hours_in_sample[h] * (
    heat_rate[t]/1000 * carbon_content[fuel[t]] * carbon_cost
  ) * 1/(1+discount_rate)^(period[h]-base_year);

########
# now get discounted costs for existing projects on similar terms

# year when the plant will be retired
# this is rounded up to the end of the study period when the retirement would occur,
# so power is generated and capital & O&M payments are made until the end of that period.
param ep_end_year {(z, e) in EXISTING_PLANTS} =
  min(end_year, start_year+ceil((ep_vintage[z, e]+ep_max_age_years[z, e]-start_year)/years_per_period)*years_per_period);

# annual revenue that is needed to cover the capital cost (per MW)
# TODO: find a better way to specify the finance rate applied to existing projects
# for now, we just assume it's the same as a new CCGT plant
# TODO: Move the regional cost adjustment into the database. 
param ep_capital_cost_annual_payment {(z, e) in EXISTING_PLANTS} = 
  finance_rate[tech_ccgt] * (1 + 1/((1+finance_rate[tech_ccgt])^ep_max_age_years[z, e]-1)) * ep_overnight_cost[z, e] * economic_multiplier[z];

# discount capital costs to a lump-sum value at the start of the study.
param ep_capital_cost {(z, e) in EXISTING_PLANTS} =
  ep_capital_cost_annual_payment[z, e]
  * (1-(1/(1+discount_rate)^(ep_end_year[z, e]-start_year)))/discount_rate
  * 1/(1+discount_rate)^(start_year-base_year);
# cost per MW to operate a plant in any future period, discounted to start of study
param ep_fixed_cost {(z, e) in EXISTING_PLANTS, p in PERIODS} =
  ep_fixed_o_m[z, e] * economic_multiplier[z] * (1-(1/(1+discount_rate)^(years_per_period)))/discount_rate
  * 1/(1+discount_rate)^(p-base_year);

# all variable costs ($/MWh) for generating a MWh of electricity in some
# future hour, from each existing project, discounted to the reference year
# note: we divide heat_rate by 1000 to go from Btu/kWh to MBtu/MWh
param ep_variable_cost {(z, e) in EXISTING_PLANTS, h in TIMEPOINTS} =
  hours_in_sample[h] * (
    ep_variable_o_m[z, e] * economic_multiplier[z]
    + ep_heat_rate[z, e]/1000 * fuel_cost_hourly[z, ep_fuel[z, e], h]
  ) * 1/(1+discount_rate)^(period[h]-base_year);

param ep_carbon_cost_per_mwh {(z, e) in EXISTING_PLANTS, h in TIMEPOINTS} = 
  hours_in_sample[h] * (
    ep_heat_rate[z, e]/1000 * carbon_content[ep_fuel[z, e]] * carbon_cost
  ) * 1/(1+discount_rate)^(period[h]-base_year);

########
# now get discounted costs per MW for transmission lines on similar terms

# cost per MW for transmission lines
# TODO: use a transmission_annual_cost_change factor to make this vary between vintages
# TODO: Move the regional cost adjustment into the database. 
param transmission_annual_payment {(z1, z2) in TRANSMISSION_LINES, v in VINTAGE_YEARS} = 
  transmission_finance_rate * (1 + 1/((1+transmission_finance_rate)^transmission_max_age_years-1)) 
  * transmission_cost_per_mw_km * (economic_multiplier[z1] + economic_multiplier[z2]) / 2 * transmission_length_km[z1, z2];

# date when a transmission line built of each vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made).
param transmission_end_year {v in VINTAGE_YEARS} =
  min(end_year, v+ceil(transmission_max_age_years/years_per_period)*years_per_period);

# discounted cost per MW
param transmission_cost_per_mw {(z1, z2) in TRANSMISSION_LINES, v in VINTAGE_YEARS} =
  transmission_annual_payment[z1, z2, v]
  * (1-(1/(1+discount_rate)^(transmission_end_year[v] - v)))/discount_rate
  * 1/(1+discount_rate)^(v-base_year);

# date when a when local T&D infrastructure of each vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made).
param local_td_end_year {v in VINTAGE_YEARS} =
  min(end_year, v+ceil(local_td_max_age_years/years_per_period)*years_per_period);

# discounted cost per MW for local T&D
# note: instead of bringing in an annual payment directly (above), we could calculate it as
# = local_td_finance_rate * (1 + 1/((1+local_td_finance_rate)^local_td_max_age_years-1)) 
#  * local_td_real_cost_per_mw;
# TODO: Move the regional cost adjustment into the database. 
param local_td_cost_per_mw {v in VINTAGE_YEARS, z in LOAD_AREAS} = 
  local_td_annual_payment_per_mw * economic_multiplier[z]
  * (1-(1/(1+discount_rate)^(local_td_end_year[v]-v)))/discount_rate
  * 1/(1+discount_rate)^(v-base_year);

######
# total cost of existing hydro plants (including capital and O&M)
# note: it would be better to handle these costs more endogenously.
# for now, we assume the nameplate capacity of each plant is equal to its peak allowed output.

# the total cost per MW for existing hydro plants
# (the discounted stream of annual payments over the whole study)
param hydro_cost_per_mw { z in LOAD_AREAS } = 
  hydro_annual_payment_per_mw * economic_multiplier[z]
  * (1-(1/(1+discount_rate)^(end_year-start_year)))/discount_rate
  * 1/(1+discount_rate)^(start_year-base_year);
# make a guess at the nameplate capacity of all existing hydro
param hydro_total_capacity = 
  sum {(z, s) in PROJ_HYDRO} (max {(z, s, d) in PROJ_HYDRO_DATES} max_hydro_flow[z, s, d]);

######
# "discounted" system load, for use in calculating levelized cost of power.
param system_load_discounted = 
  sum {z in LOAD_AREAS, h in TIMEPOINTS} 
    (hours_in_sample[h] * system_load[z,h] 
     / (1+discount_rate)^(period[h]-base_year));

##################
# reduced sets for decision variables and constraints

# project-vintage combinations that can be installed
set PROJECT_VINTAGES = setof {(z, t, s, o) in PROJECTS, v in VINTAGE_YEARS: v >= min_build_year[t] + construction_time_years[t]} (z, t, s, o, v);

# project-vintage combinations that have a minimum size constraint.
set PROJ_MIN_BUILD_VINTAGES = setof {(z, t, s, o, v) in PROJECT_VINTAGES: min_build_capacity[t] > 0} (z, t, s, o, v);

# technology-site-vintage-hour combinations for dispatchable projects
# (i.e., all the project-vintage combinations that are still active in a given hour of the study)
set PROJ_DISPATCH_VINTAGE_HOURS := 
  {(z, t, s, o) in PROJ_DISPATCH, v in VINTAGE_YEARS, h in TIMEPOINTS: not new_baseload[t] and v >= min_build_year[t] + construction_time_years[t] and v <= period[h] < project_end_year[t, v]};

# technology-site-vintage-hour combinations for intermittent (non-dispatchable) projects
set PROJ_INTERMITTENT_VINTAGE_HOURS := 
  {(z, t, s, o) in PROJ_INTERMITTENT, v in VINTAGE_YEARS, h in TIMEPOINTS: v >= min_build_year[t] + construction_time_years[t] and v <= period[h] < project_end_year[t, v]};

# plant-period combinations when new baseload plants can run
set NEW_BASELOAD_PERIODS :=
  {(z, t, s, o, v) in PROJECT_VINTAGES: new_baseload[t]};

# plant-period combinations when existing plants can run
# these are the times when a decision must be made about whether a plant will be kept available for the year
# or mothballed to save on fixed O&M (or fuel, for baseload plants)
# note: something like this could be added later for early retirement of new plants too
set EP_PERIODS :=
  {(z, e) in EXISTING_PLANTS, p in PERIODS: ep_vintage[z, e] <= p < ep_end_year[z, e]};

# plant-hour combinations when existing non-baseload, non-intermittent plants can be dispatched
set EP_DISPATCH_HOURS :=
  {(z, e) in EXISTING_PLANTS, h in TIMEPOINTS: not ep_baseload[z, e] and not ep_intermittent[z,e] and ep_vintage[z, e] <= period[h] < ep_end_year[z, e]};

# plant-hour combinations when existing intermittent plants can produce power or be mothballed (e.g. They have not been retired yet)
set EP_INTERMITTENT_OPERATIONAL_HOURS :=
  {(z, e, h) in EP_INTERMITTENT_HOURS: 
  	# Retire plants after their max age. e.g. Filter out periods that occur before the plant "is built" and periods that occur after the plant is retired. 
  	ep_vintage[z, e] <= period[h] < ep_end_year[z, e]};

# plant-period combinations when existing baseload plants can run
# should this be as above limiting periods to times at which the plant hasn't retired yet?
set EP_BASELOAD_PERIODS :=
  {(z, e, p) in EP_PERIODS: ep_baseload[z, e]};

# trans_line-vintage-hour combinations for which dispatch decisions must be made
set TRANS_VINTAGE_HOURS := 
  {(z1, z2) in TRANSMISSION_LINES, v in VINTAGE_YEARS, h in TIMEPOINTS: v <= period[h] < transmission_end_year[v]};

# local_td-vintage-hour combinations which must be reconciled
set LOCAL_TD_HOURS := 
  {z in LOAD_AREAS, v in VINTAGE_YEARS, h in TIMEPOINTS: v <= period[h] < local_td_end_year[v]};


#### VARIABLES ####

# number of MW to install in each project at each date (vintage)
var InstallGen {PROJECT_VINTAGES} >= 0;

# binary constraint that restricts small plants of certain types of generators (ex: Nuclear) from being built
# this quantity is one when there is there is not a constraint on how small plants can be
# and is zero when there is a constraint
var BuildGenOrNot {PROJ_MIN_BUILD_VINTAGES} binary;

# number of MW to generate from each project, in each hour
var DispatchGen {PROJ_DISPATCH, TIMEPOINTS} >= 0;

# number of MW generated by intermittent renewables
# this is not a decision variable, but is useful for reporting
# (well, it would be useful for reporting, but it takes 63 MB of ram for 
# 240 hours x 2 vintages and grows proportionally to that product)
#var IntermittentOutput {(z, t, s, o, v, h) in PROJ_INTERMITTENT_VINTAGE_HOURS} 
#   = (1-forced_outage_rate[t]) * cap_factor[z, t, s, o, h] * InstallGen[z, t, s, o, v];

# share of existing plants to operate during each study period.
# this should be a binary variable, but it's interesting to see 
# how the continuous form works out
#var OperateEPDuringPeriod {EP_PERIODS} >= 0, <= 1;
var OperateEPDuringPeriod {EP_PERIODS} binary;

# number of MW to generate from each existing dispatchable plant, in each hour
var DispatchEP {EP_DISPATCH_HOURS} >= 0;

# number of MW to install in each transmission corridor at each vintage
var InstallTrans {TRANSMISSION_LINES, VINTAGE_YEARS} >= 0;

# number of MW to transmit through each transmission corridor in each hour
var DispatchTransFromXToY {TRANSMISSION_LINES, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;
var DispatchTransFromXToY_Reserve {TRANSMISSION_LINES, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;

# amount of local transmission and distribution capacity
# (to carry peak power from transmission network to distributed loads)
var InstallLocalTD {LOAD_AREAS, VINTAGE_YEARS} >= 0;

# amount of pumped hydro to store and dispatch during each hour
# note: the amount "stored" is the number of MW that can be generated using
# the water that is stored, 
# so it takes 1/pumped_hydro_efficiency MWh to store 1 MWh
var StorePumpedHydro {PROJ_PUMPED_HYDRO, TIMEPOINTS} >= 0;
var DispatchPumpedHydro {PROJ_PUMPED_HYDRO, TIMEPOINTS} >= 0;
var StorePumpedHydro_Reserve {PROJ_PUMPED_HYDRO, TIMEPOINTS} >= 0;
var DispatchPumpedHydro_Reserve {PROJ_PUMPED_HYDRO, TIMEPOINTS} >= 0;

# simple hydro is dispatched on an aggregated basis, using a schedule that shows the
# amount of discretionary hydro to dispatch during each study period, in each zone,
# season (Jan-Mar, Apr-Jun, etc.) and hour
var HydroDispatchShare {PERIODS, LOAD_AREAS, SEASONS_OF_YEAR, HOURS_OF_DAY} >= 0;
var HydroDispatchShare_Reserve {PERIODS, LOAD_AREAS, SEASONS_OF_YEAR, HOURS_OF_DAY} >= 0;

#### OBJECTIVES ####

# total cost of power, including carbon tax
# z = Load Zone, AKA Load Area
# t = technology
# s = site
# o = orientation (PV tilt, usually not used)
# v = VINTAGE_YEARS, are a synonym for PERIODS, but refer more explicitly the date when a power plant starts running.
# h = study hour - unique timepoint considered
# e = Plant ID for existing plants. In US, this is the FERC plant_code. e.g. 55306-CC
# p = investment period
minimize Power_Cost:

	#############################
	#    NEW PLANTS
  # Calculate fixed costs for all new plants
    sum {(z, t, s, o, v) in PROJECT_VINTAGES} 
      InstallGen[z, t, s, o, v] * fixed_cost[z, t, s, o, v]
  # Calculate variable costs for new plants that are dispatchable. 
  + sum {(z, t, s, o) in PROJ_DISPATCH, h in TIMEPOINTS} 
      DispatchGen[z, t, s, o, h] * (variable_cost[z, t, h] + carbon_cost_per_mwh[t, h])
  # Calculate variable costs for new baseload plants
  + sum {(z, t, s, o, v) in NEW_BASELOAD_PERIODS, h in TIMEPOINTS: period[h]=v}
      (1-forced_outage_rate[t]) * (1-scheduled_outage_rate[t]) * InstallGen[z, t, s, o, v] 
      * (variable_cost[z, t, h] + carbon_cost_per_mwh[t, h])

	#############################
	#    EXISTING PLANTS
  # Calculate capital costs for all existing plants. This number is not affected by any of the decision variables because it is a sunk cost.
  + sum {(z, e) in EXISTING_PLANTS}
      ep_size_mw[z, e] * ep_capital_cost[z, e]
  # Calculate fixed costs for all existing plants
  + sum {(z, e, p) in EP_PERIODS} 
      OperateEPDuringPeriod[z, e, p] * ep_size_mw[z, e] * ep_fixed_cost[z, e, p]
  # Calculate variable costs for existing BASELOAD plants
  # NOTE: The number of decision variables could be reduced significantly if you indexed ep_variable_cost & ep_carbon_cost_per_mwh by p instead of h, then express the sum like this: + sum {(z, e, p) in EP_BASELOAD_PERIODS} OperateEPDuringPeriod[z, e, p] * (1-ep_forced_outage_rate[z, e]) * (1-ep_scheduled_outage_rate[z, e]) * ep_size_mw[z, e] * (ep_variable_cost[z, e, p] + ep_carbon_cost_per_mwh[z, e, p]) * total_hours_in_period[p]
  + sum {(z, e, p) in EP_BASELOAD_PERIODS, h in TIMEPOINTS: period[h]=p}
      OperateEPDuringPeriod[z, e, p] * (1-ep_forced_outage_rate[z, e]) * (1-ep_scheduled_outage_rate[z, e]) * ep_size_mw[z, e] 
      * (ep_variable_cost[z, e, h] + ep_carbon_cost_per_mwh[z, e, h])
  # Calculate variable costs for existing NON-BASELOAD plants
  + sum {(z, e, h) in EP_DISPATCH_HOURS}
      DispatchEP[z, e, h]
      * (ep_variable_cost[z, e, h] + ep_carbon_cost_per_mwh[z, e, h])
  # Calculate variable costs for existing INTERMITTENT plants
  + sum {(z, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS}
      OperateEPDuringPeriod[z, e, period[h]] * ep_size_mw[z, e] * eip_cap_factor[z, e, h] * 
      (1-ep_forced_outage_rate[z, e]) * ep_variable_cost[z, e, h]

  # Hydro
  + sum {(z, s) in PROJ_HYDRO} 
      hydro_cost_per_mw[z] * (max {(z, s, d) in PROJ_HYDRO_DATES} max_hydro_flow[z, s, d])

	########################################
	#    TRANSMISSION & DISTRIBUTION
  + sum {(z1, z2) in TRANSMISSION_LINES, v in VINTAGE_YEARS} 
      InstallTrans[z1, z2, v] * transmission_cost_per_mw[z1, z2, v]
  + sum {(z1, z2) in TRANSMISSION_LINES} 
      transmission_cost_per_mw[z1, z2, first(PERIODS)] * (existing_transfer_capacity_mw[z1, z2])/2
  + sum {z in LOAD_AREAS, v in VINTAGE_YEARS}
      InstallLocalTD[z, v] * local_td_cost_per_mw[v, z]
;

# this alternative objective is used to reduce transmission flows to
# zero in one direction of each pair, and to minimize needless flows
# around loops, or shipping of unneeded power to neighboring zones, 
# so it is more clear where surplus power is being generated
minimize Transmission_Usage:
  sum {(z1, z2) in TRANSMISSION_LINES, h in TIMEPOINTS, fuel_cat in RPS_FUEL_CATEGORY} 
    (DispatchTransFromXToY[z1, z2, h, fuel_cat]);


#### CONSTRAINTS ####

# system needs to meet the load in each load zone in each hour
# note: power is deemed to flow from z1 to z2 if positive, reverse if negative
subject to Satisfy_Load {z in LOAD_AREAS, h in TIMEPOINTS}:

	#############################
	#    NEW PLANTS
  # new dispatchable projects
  (sum {(z, t, s, o) in PROJ_DISPATCH} DispatchGen[z, t, s, o, h])
  # output from new intermittent projects
  + (sum {(z, t, s, o, v, h) in PROJ_INTERMITTENT_VINTAGE_HOURS} 
      (1-forced_outage_rate[t]) * cap_factor[z, t, s, o, h] * InstallGen[z, t, s, o, v])
  # new baseload plants
  + sum {(z, t, s, o, v) in NEW_BASELOAD_PERIODS} 
      ((1-forced_outage_rate[t]) * (1-scheduled_outage_rate[t]) * InstallGen[z, t, s, o, v] )

	#############################
	#    EXISTING PLANTS
  # existing baseload plants
  + sum {(z, e, p) in EP_BASELOAD_PERIODS: p=period[h]} 
      (OperateEPDuringPeriod[z, e, p] * (1-ep_forced_outage_rate[z, e]) * (1-ep_scheduled_outage_rate[z, e]) * ep_size_mw[z, e])
  # existing dispatchable plants
  + sum {(z, e, h) in EP_DISPATCH_HOURS} DispatchEP[z, e, h]
  # existing intermittent plants
  + sum {(z, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS} 
      OperateEPDuringPeriod[z, e, period[h]] * ep_size_mw[z, e] * eip_cap_factor[z, e, h] * (1-ep_forced_outage_rate[z, e])

  # pumped hydro, de-rated to reflect occasional unavailability of the hydro plants
  + (1 - forced_outage_rate_hydro) * (sum {(z, s) in PROJ_PUMPED_HYDRO} DispatchPumpedHydro[z, s, h])
  - (1 - forced_outage_rate_hydro) * (1/pumped_hydro_efficiency) * 
      (sum {(z, s) in PROJ_PUMPED_HYDRO} StorePumpedHydro[z, s, h])
  # simple hydro, dispatched using the season-hour schedules chosen above
  # also de-rated to reflect occasional unavailability
  + (1 - forced_outage_rate_hydro) * 
    (min_hydro_dispatch_all_sites[z, date[h]] 
       + HydroDispatchShare[period[h], z, season_of_year[h], hour_of_day[h]]
         * (avg_hydro_dispatch_all_sites[z, date[h]] - min_hydro_dispatch_all_sites[z, date[h]]) * 24)


	########################################
	#    TRANSMISSION
  # transmission into and out of the zone. 
  
  # Transmitted power coming into the zone will have losses because of the transmission line it has come in over;
  # as a result, the incoming DispatchTransFromXToY[z2, z, h, ft] is multiplied by the transmission efficiency of the line over which it was transmitted.
  # On the other hand, transmitted power leaving the zone will not yet have experienced transmission losses; as a result the outgoing 
  # DispatchTransFromXToY[z, z1, h, ft] is not multiplied by the transmission efficiency.

  # Imports (have experienced transmission losses)
  + (sum {(z2, z) in TRANSMISSION_LINES, f in FUELS} (transmission_efficiency[z2, z] * DispatchTransFromXToY[z2, z, h, rps_fuel_category[f]]))
  
  # Exports (have not experienced transmission losses)
  - (sum {(z, z1) in TRANSMISSION_LINES, f in FUELS} (DispatchTransFromXToY[z, z1, h, rps_fuel_category[f]]))

  >= system_load[z, h];

################################################################################
# same on a reserve basis
# note: these are not prorated by forced outage rate, because that is incorporated in the reserve margin
subject to Satisfy_Load_Reserve {z in LOAD_AREAS, h in TIMEPOINTS}:

	#############################
	#    NEW PLANTS
  # new dispatchable capacity (no need to decide how to dispatch it; we just need to know it's available)
  (sum {(z, t, s, o, v, h) in PROJ_DISPATCH_VINTAGE_HOURS} InstallGen[z, t, s, o, v])

  # Is it appropriate to put intermittent plants into the load reserve? Do any utility regulators currently allow this?
  # output from new intermittent projects
  + (sum {(z, t, s, o, v, h) in PROJ_INTERMITTENT_VINTAGE_HOURS} 
      cap_factor[z, t, s, o, h] * InstallGen[z, t, s, o, v])

  # new baseload plants
  + sum {(z, t, s, o, v) in NEW_BASELOAD_PERIODS} 
      ((1-scheduled_outage_rate[t]) * InstallGen[z, t, s, o, v] )

	#############################
	#    EXISTING PLANTS
  # existing baseload plants
  + sum {(z, e, p) in EP_BASELOAD_PERIODS: p=period[h]} 
      (OperateEPDuringPeriod[z, e, p] * (1-ep_scheduled_outage_rate[z, e]) * ep_size_mw[z, e])
  # existing dispatchable capacity
  + sum {(z, e, h) in EP_DISPATCH_HOURS} OperateEPDuringPeriod[z, e, period[h]] * ep_size_mw[z, e]
  # existing intermittent plants
  + sum {(z, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS} 
      OperateEPDuringPeriod[z, e, period[h]] * ep_size_mw[z, e] * eip_cap_factor[z, e, h]

  # pumped hydro
  + (sum {(z, s) in PROJ_PUMPED_HYDRO} DispatchPumpedHydro_Reserve[z, s, h])
  - (1/pumped_hydro_efficiency) * 
      (sum {(z, s) in PROJ_PUMPED_HYDRO} StorePumpedHydro_Reserve[z, s, h])
  # simple hydro, dispatched using the season-hour schedules chosen above
  + (min_hydro_dispatch_all_sites[z, date[h]] 
       + HydroDispatchShare_Reserve[period[h], z, season_of_year[h], hour_of_day[h]]
         * (avg_hydro_dispatch_all_sites[z, date[h]] - min_hydro_dispatch_all_sites[z, date[h]]) * 24)

	########################################
	#    TRANSMISSION
  # Imports (have experienced transmission losses)
  + (sum {(z2, z) in TRANSMISSION_LINES, f in FUELS} (transmission_efficiency[z2, z] * DispatchTransFromXToY_Reserve[z2, z, h, rps_fuel_category[f]]))
  # Exports (have not experienced transmission losses)
  - (sum {(z, z1) in TRANSMISSION_LINES, f in FUELS} (DispatchTransFromXToY_Reserve[z, z1, h, rps_fuel_category[f]]))

  >= system_load[z, h] * (1 + planning_reserve_margin);


################################################################################
# pumped hydro dispatch for all hours of the day must be within the limits of the plant
# net flow of power (i.e., water) must also match the historical average
# TODO: find better historical averages that reflect net balance of generated and stored power,
#  because the values currently used are equal to sum(Dispatch - 1/efficiency * Storage)
subject to Maximum_DispatchPumpedHydro {(z, s) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS}:
  DispatchPumpedHydro[z, s, h] <= max_hydro_flow[z, s, date[h]];
subject to Maximum_StorePumpedHydro {(z, s) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS: min_hydro_flow[z, s, date[h]] < 0}:
  StorePumpedHydro[z, s, h] <= -min_hydro_flow[z, s, date[h]];
subject to Average_PumpedHydroFlow {(z, s) in PROJ_PUMPED_HYDRO, d in DATES}:
  sum {h in TIMEPOINTS: date[h]=d} (DispatchPumpedHydro[z, s, h] - StorePumpedHydro[z, s, h]) <= 
  sum {h in TIMEPOINTS: date[h]=d} avg_hydro_flow[z, s, d];
# extra rules to apply when non-pumped sites are also dispatched hourly
subject to Minimum_DispatchNonPumpedHydro {(z, s) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS: min_hydro_flow[z, s, date[h]] >= 0}:
  DispatchPumpedHydro[z, s, h] >= min_hydro_flow[z, s, date[h]];
subject to Maximum_StoreNonPumpedHydro {(z, s) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS: min_hydro_flow[z, s, date[h]] >= 0}:
  StorePumpedHydro[z, s, h] = 0;

# discretionary hydro dispatch for all hours of the day must sum to 1
# note: dispatch is deemed to happen no matter what (to respect flow constraints), 
# but energy supply is later de-rated by hydro forced outage rate
subject to Maximum_DispatchHydroShare
  {p in PERIODS, z in LOAD_AREAS, s in SEASONS_OF_YEAR}: sum {h in HOURS_OF_DAY} HydroDispatchShare[p, z, s, h] <= 1;

# only part of the discretionary hydro can be dispatched in each hour of the day
subject to MaximumHourly_DispatchHydroShare
  {p in PERIODS, z in LOAD_AREAS, s in SEASONS_OF_YEAR, h in HOURS_OF_DAY}:
    0 <= HydroDispatchShare[p, z, s, h] <= max_hydro_dispatch_per_hour;

# same for reserve margin operation
subject to Maximum_DispatchPumpedHydro_Reserve {(z, s) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS}:
  DispatchPumpedHydro_Reserve[z, s, h] <= max_hydro_flow[z, s, date[h]];
subject to Maximum_StorePumpedHydro_Reserve {(z, s) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS: min_hydro_flow[z, s, date[h]] < 0}:
  StorePumpedHydro_Reserve[z, s, h] <= -min_hydro_flow[z, s, date[h]];
subject to Average_PumpedHydroFlow_Reserve {(z, s) in PROJ_PUMPED_HYDRO, d in DATES}:
  sum {h in TIMEPOINTS: date[h]=d} (DispatchPumpedHydro_Reserve[z, s, h] - StorePumpedHydro_Reserve[z, s, h]) <= 
  sum {h in TIMEPOINTS: date[h]=d} avg_hydro_flow[z, s, d];
subject to Minimum_DispatchNonPumpedHydro_Reserve {(z, s) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS: min_hydro_flow[z, s, date[h]] >= 0}:
  DispatchPumpedHydro_Reserve[z, s, h] >= min_hydro_flow[z, s, date[h]];
subject to Maximum_StoreNonPumpedHydro_Reserve {(z, s) in PROJ_PUMPED_HYDRO, h in TIMEPOINTS: min_hydro_flow[z, s, date[h]] >= 0}:
  StorePumpedHydro_Reserve[z, s, h] = 0;
subject to Maximum_DispatchHydroShare_Reserve
  {p in PERIODS, z in LOAD_AREAS, s in SEASONS_OF_YEAR}: sum {h in HOURS_OF_DAY} HydroDispatchShare_Reserve[p, z, s, h] <= 1;
subject to MaximumHourly_DispatchHydroShare_Reserve
  {p in PERIODS, z in LOAD_AREAS, s in SEASONS_OF_YEAR, h in HOURS_OF_DAY}:
    0 <= HydroDispatchShare_Reserve[p, z, s, h] <= max_hydro_dispatch_per_hour;


# system can only dispatch as much of each project as is EXPECTED to be available
# i.e., we only dispatch up to 1-forced_outage_rate, so the system will work on an expected-value basis
# (this is the base portfolio, more backup generators will be added later to get a lower year-round risk level)
subject to Maximum_DispatchGen 
  {(z, t, s, o) in PROJ_DISPATCH, h in TIMEPOINTS}:
  DispatchGen[z, t, s, o, h] <= (1-forced_outage_rate[t]) * 
    sum {(z, t, s, o, v, h) in PROJ_DISPATCH_VINTAGE_HOURS} InstallGen[z, t, s, o, v];

# there are limits on total installations in certain projects
# TODO: adjust this to allow re-installing at the same site after retiring an earlier plant
# (not an issue if the simulation is too short to retire plants)
# or even allow forced retiring of earlier plants if new technologies are better
subject to Maximum_Resource {(z, t, s, o) in PROJ_RESOURCE_LIMITED}:
  sum {v in VINTAGE_YEARS: v >= min_build_year[t] + construction_time_years[t]} InstallGen[z, t, s, o, v] <= max_capacity[z, t, s];

# Some generators have a minimum build size. This enforces that constraint
# If a generator is installed, then BuildGenOrNot is 1, and InstallGen has to be >= min_build_capacity
# If a generator is NOT installed, then BuildGenOrNot is 0, and InstallGen has to be >= 0
subject to Minimum_GenSize 
  {(z, t, s, o, v) in PROJ_MIN_BUILD_VINTAGES}:
  InstallGen[z, t, s, o, v] >= min_build_capacity[t] * BuildGenOrNot[z, t, s, o, v];

# This binds BuildGenOrNot to InstallGen. The number below (1e6) is somewhat arbitrary. 
# I picked a number that would be far above the largest generator that would possibly be built
# If a generator is installed, then BuildGenOrNot is 1, and InstallGen has to be <= 0
# If a generator is NOT installed, then BuildGenOrNot is 0, and InstallGen can be between 0 & 1e6 - basically no upper limit
subject to BuildGenOrNot_Constraint 
  {(z, t, s, o, v) in PROJ_MIN_BUILD_VINTAGES}:
  InstallGen[z, t, s, o, v] <= 1000000 * BuildGenOrNot[z, t, s, o, v];

# existing dispatchable plants can only be used if they are operational this year
subject to EP_Operational
  {(z, e, h) in EP_DISPATCH_HOURS}: DispatchEP[z, e, h] <= 
      OperateEPDuringPeriod[z, e, period[h]] * (1-ep_forced_outage_rate[z, e]) * ep_size_mw[z, e];

# system can only use as much transmission as is expected to be available
# note: transmission up and down the line both enter positively,
# but the form of the model allows them to both be reduced or increased by a constant,
# so they will both be held low enough to stay within the installed capacity
# (if there were a variable cost of operating, one of them would always go to zero)
# a quick follow-up model run minimizing transmission usage will push one of these to zero.
# TODO: retire pre-existing transmission lines after transmission_max_age_years 
#   (this requires figuring out when they were first built!)
subject to Maximum_DispatchTransFromXToY
  {(z1, z2) in TRANSMISSION_LINES, h in TIMEPOINTS}:
  ( sum { f in FUELS } DispatchTransFromXToY[z1, z2, h, rps_fuel_category[f]] )
    <= (1-transmission_forced_outage_rate) * 
          (existing_transfer_capacity_mw[z1, z2] + sum {(z1, z2, v, h) in TRANS_VINTAGE_HOURS} InstallTrans[z1, z2, v]);

subject to Maximum_DispatchTransFromXToY_Reserve
  {(z1, z2) in TRANSMISSION_LINES, h in TIMEPOINTS}:
  ( sum { f in FUELS } DispatchTransFromXToY_Reserve[z1, z2, h, rps_fuel_category[f]] )
    <= (existing_transfer_capacity_mw[z1, z2] + sum {(z1, z2, v, h) in TRANS_VINTAGE_HOURS} InstallTrans[z1, z2, v]);


# make sure there's enough intra-zone transmission and distribution capacity
# to handle the net distributed loads
subject to Maximum_LocalTD 
  {z in LOAD_AREAS, h in TIMEPOINTS}:
  system_load[z,h]
    - (sum {(z, t, s, o, v, h) in PROJ_INTERMITTENT_VINTAGE_HOURS: t=tech_distributed_pv}
        (1-forced_outage_rate[t]) * cap_factor[z, t, s, o, h] * InstallGen[z, t, s, o, v])
    - (sum {(z, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS: ep_technology[z,e]=tech_distributed_pv}
    	OperateEPDuringPeriod[z, e, period[h]] * 
        (1-ep_forced_outage_rate[z,e]) * eip_cap_factor[z, e, h] * ep_size_mw[z, e] )
  <= sum {(z, v, h) in LOCAL_TD_HOURS} InstallLocalTD[z, v];


# make the system generate a certain amount of power from a certain resource
subject to Min_Gen_Fraction_From_Solar { if enable_min_solar_production}:
    # New plants
	(sum {(z, t, s, o, v, h) in PROJ_INTERMITTENT_VINTAGE_HOURS: t in SOLAR_TECHNOLOGIES             and v = last( VINTAGE_YEARS )} 
        (1-forced_outage_rate[t]) * cap_factor[z, t, s, o, h] * InstallGen[z, t, s, o, v]) 
    # Existing plants
    - (sum {(z, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS: ep_technology[z,e] in SOLAR_TECHNOLOGIES and period[h] = last( VINTAGE_YEARS )}
    	OperateEPDuringPeriod[z, e, period[h]] * 
        (1-ep_forced_outage_rate[z,e]) * eip_cap_factor[z, e, h]   * ep_size_mw[z, e] )
      >=
    min_solar_production * (sum {z in LOAD_AREAS, h in TIMEPOINTS} (system_load[z,h]) );

#################################################
# RPS constraint
subject to Satisfy_RPS {z in LOAD_AREAS_WITH_RPS, p in PERIODS: 
	p >= period_rps_takes_effect[z] and enable_rps}:

 (
	#############################
	#   Power from NEW PLANTS
  # new dispatchable projects
   (sum {(z, t, s, o) in PROJ_DISPATCH, h in TIMEPOINTS: 
        period[h] = p and fuel_qualifies_for_rps[z, rps_fuel_category[fuel[t]]]} 
     DispatchGen[z, t, s, o, h] * hours_in_sample[h]
   )
  # output from new intermittent projects
  + (sum {(z, t, s, o, v, h) in PROJ_INTERMITTENT_VINTAGE_HOURS: 
          v = p and fuel_qualifies_for_rps[z, rps_fuel_category[fuel[t]]]} 
      (1-forced_outage_rate[t]) * cap_factor[z, t, s, o, h] * InstallGen[z, t, s, o, v] * hours_in_sample[h]
    )
  # new baseload plants
  + (sum {(z, t, s, o, v) in NEW_BASELOAD_PERIODS, h in TIMEPOINTS: 
          v = p and period[h] = p and fuel_qualifies_for_rps[z, rps_fuel_category[fuel[t]]]} 
      (1-forced_outage_rate[t]) * (1-scheduled_outage_rate[t]) * InstallGen[z, t, s, o, v] * hours_in_sample[h]
    )

	#############################
	#    Power from EXISTING PLANTS
  # existing baseload plants
  + (sum {(z, e, p) in EP_BASELOAD_PERIODS, h in TIMEPOINTS: 
          period[h]=p and fuel_qualifies_for_rps[z, rps_fuel_category[ep_fuel[z,e]]]} 
      OperateEPDuringPeriod[z, e, p] * (1-ep_forced_outage_rate[z, e]) * (1-ep_scheduled_outage_rate[z, e]) * ep_size_mw[z, e] * hours_in_sample[h]
    )
  # existing dispatchable plants
  + (sum {(z, e, h) in EP_DISPATCH_HOURS: 
          period[h]=p and fuel_qualifies_for_rps[z, rps_fuel_category[ep_fuel[z,e]]]} 
      DispatchEP[z, e, h] * hours_in_sample[h]
    )
  # existing intermittent plants
  + (sum {(z, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS: 
          period[h]=p and fuel_qualifies_for_rps[z, rps_fuel_category[ep_fuel[z,e]]]} 
      OperateEPDuringPeriod[z, e, p] * ep_size_mw[z, e] * eip_cap_factor[z, e, h] * (1-ep_forced_outage_rate[z, e]) * hours_in_sample[h]
    )

	########################################
	#    TRANSMISSION
  # transmission into and out of the zone.

#  Imports
  + (sum {(z2, z) in TRANSMISSION_LINES, f in FUELS, h in TIMEPOINTS: 
          period[h]=p and fuel_qualifies_for_rps[z, rps_fuel_category[f]]}
      (transmission_efficiency[z2, z] * DispatchTransFromXToY[z2, z, h, rps_fuel_category[f]]) * hours_in_sample[h]
    )
  
#  Exports
  - (sum {(z, z1) in TRANSMISSION_LINES, f in FUELS, h in TIMEPOINTS: 
          period[h]=p and fuel_qualifies_for_rps[z, rps_fuel_category[f]]}
      DispatchTransFromXToY[z, z1, h, rps_fuel_category[f]] * hours_in_sample[h]
    )
 ) 
  / (sum { h in TIMEPOINTS: 
           period[h] = p  and load_area_rps_policy[z] = 1} 
      system_load[z, h] * hours_in_sample[h]
    )
  >= rps_compliance_percentage[z];

#############################
# REC accounting: Reclassifying electrons is verboten!
subject to Conservation_of_Colored_Electrons {z in LOAD_AREAS, h in TIMEPOINTS, ft in RPS_FUEL_CATEGORY: enable_rps}:

	#############################
	#    Power Production
  # new dispatchable projects
    (sum {(z, t, s, o) in PROJ_DISPATCH: rps_fuel_category[fuel[t]] = ft} 
      DispatchGen[z, t, s, o, h]
    )
  # new intermittent projects
  + (sum {(z, t, s, o, v, h) in PROJ_INTERMITTENT_VINTAGE_HOURS: rps_fuel_category[fuel[t]] = ft} 
      (1-forced_outage_rate[t]) * cap_factor[z, t, s, o, h] * InstallGen[z, t, s, o, v]
    )
  # new baseload plants
  + (sum {(z, t, s, o, v) in NEW_BASELOAD_PERIODS: rps_fuel_category[fuel[t]] = ft} 
      (1-forced_outage_rate[t]) * (1-scheduled_outage_rate[t]) * InstallGen[z, t, s, o, v] 
    )
  # existing baseload plants
  + (sum {(z, e, p) in EP_BASELOAD_PERIODS: p=period[h] and rps_fuel_category[ep_fuel[z,e]] = ft} 
      OperateEPDuringPeriod[z, e, p] * (1-ep_forced_outage_rate[z, e]) * (1-ep_scheduled_outage_rate[z, e]) * ep_size_mw[z, e]
    )
  # existing dispatchable plants
  + (sum {(z, e, h) in EP_DISPATCH_HOURS: rps_fuel_category[ep_fuel[z,e]] = ft} 
      DispatchEP[z, e, h]
    )
  # existing intermittent plants
  + (sum {(z, e, h) in EP_INTERMITTENT_OPERATIONAL_HOURS: rps_fuel_category[ep_fuel[z,e]] = ft} 
      OperateEPDuringPeriod[z, e, period[h]] * ep_size_mw[z, e] * eip_cap_factor[z, e, h] * (1-ep_forced_outage_rate[z, e])
    )

  #############################
  # Imports (have experienced transmission losses)
  + (sum {(z2, z) in TRANSMISSION_LINES} 
      transmission_efficiency[z2, z] * DispatchTransFromXToY[z2, z, h, ft]
    )
  
     #############################
     # Exports (have not experienced transmission losses)
  >= (sum {(z, z1) in TRANSMISSION_LINES} (DispatchTransFromXToY[z, z1, h, ft]));


#######
# REC accounting: Reclassifying electrons is verboten!
# Hydro power production is done differently than all the other technologies
# Consequently, we need to express it in a separate constraint instead of bundling it into the one above. 
subject to Conservation_of_Blue_Electrons {z in LOAD_AREAS, h in TIMEPOINTS: enable_rps}:

  ####
  # Hydro Production
  # pumped hydro, de-rated to reflect occasional unavailability of the hydro plants
  + (1 - forced_outage_rate_hydro) * (sum {(z, s) in PROJ_PUMPED_HYDRO} DispatchPumpedHydro[z, s, h])
  - (1 - forced_outage_rate_hydro) * (1/pumped_hydro_efficiency) * 
      (sum {(z, s) in PROJ_PUMPED_HYDRO} StorePumpedHydro[z, s, h])
  # simple hydro, dispatched using the season-hour schedules chosen above
  # also de-rated to reflect occasional unavailability
  + (1 - forced_outage_rate_hydro) * 
    (min_hydro_dispatch_all_sites[z, date[h]] 
       + HydroDispatchShare[period[h], z, season_of_year[h], hour_of_day[h]]
         * (avg_hydro_dispatch_all_sites[z, date[h]] - min_hydro_dispatch_all_sites[z, date[h]]) * 24)

  # Imports (have experienced transmission losses)
  + (sum {(z2, z) in TRANSMISSION_LINES} (transmission_efficiency[z2, z] * DispatchTransFromXToY[z2, z, h, rps_fuel_category[fuel_hydro]]))
  
     # Exports (have not experienced transmission losses)
  >= (sum {(z, z1) in TRANSMISSION_LINES} (DispatchTransFromXToY[z, z1, h, rps_fuel_category[fuel_hydro] ]));



