# This is the fundamental code of Switch which compiles a mixed integer linear program to be solved by CPLEX.
# Most constants are found in windsun.dat, while run-time variables are in the various .tab files.
# A combination of windsun.run and switch.run wrap around windsun.mod.

###############################################
# Time-tracking parameters

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

# specific dates are used to collect hours that are part of the same day, for the purpose of storage dispatch.
set DATES ordered = setof {h in TIMEPOINTS} (date[h]);
param period_of_date {d in DATES} = min { h in TIMEPOINTS: date[h] = d } period[h];
param hours_in_period {p in PERIODS} = sum { h in TIMEPOINTS: period[h] = p } hours_in_sample[h];

set HOURS_OF_DAY ordered = setof {h in TIMEPOINTS} (hour_of_day[h]);
set MONTHS_OF_YEAR ordered = setof {h in TIMEPOINTS} (month_of_year[h]);
set SEASONS_OF_YEAR ordered = setof {h in TIMEPOINTS} (season_of_year[h]);

# the present year, on which the preset day power cost optimization will depend
param present_year;

# the date (year and fraction) when the optimization starts
param start_year = first(PERIODS);

# interval between study periods
param num_years_per_period;

# the first year past the end of the current simulation
# used for discounting series of annual payments back to a lump sum at the start of the payment window
param end_year = last(PERIODS) + num_years_per_period;

# first and last study hour of each study date
param first_hour_of_date {d in DATES} = min { h in TIMEPOINTS: date[h] = d } h;
param last_hour_of_date {d in DATES} = max { h in TIMEPOINTS: date[h] = d } h;

# cyclical implementation of previous timepoint by date used in determining startup costs
param previous_timepoint {h in TIMEPOINTS} =
	if h <> first_hour_of_date[date[h]]
	then prev(h, TIMEPOINTS)
	else last_hour_of_date[date[h]];

###############################################
# System loads and areas

# Load Areas are the smallest unit of load in the model. 
set LOAD_AREAS;

# load area id, useful for rapidly referencing the database
param load_area_id {LOAD_AREAS} >= 0;

# primary state of each load area
param primary_state {LOAD_AREAS} symbolic;

# system load (MW)
param system_load {LOAD_AREAS, TIMEPOINTS} >= 0;

# max system load (MW) - Used for determining max local T&D
set PRESENT_YEAR = {present_year};
set PERIODS_AND_PRESENT ordered = PRESENT_YEAR union PERIODS;
param max_system_load {LOAD_AREAS, PERIODS_AND_PRESENT} >= 0;

# the load in current day instead of a future investment period
# this is used to calculate the present day cost of power
# and will be referenced to present day timepoints in ??
param present_day_system_load {LOAD_AREAS, TIMEPOINTS} >= 0;

# Regional cost multipliers
param economic_multiplier {LOAD_AREAS} >= 0;

# distance to build a pipeline from load areas that don't have adequate carbon sinks to the nearest adequate sink
param ccs_distance_km {LOAD_AREAS} >= 0;

# the amount of biogas available in each load area in MMBtu per hour 
param bio_gas_capacity_limit_mmbtu_per_hour {LOAD_AREAS} >= 0;

# system load aggregated in various ways
param total_loads_by_period {p in PERIODS} = 
	sum {a in LOAD_AREAS, h in TIMEPOINTS: period[h]=p} system_load[a, h];
param total_loads_by_period_weighted {p in PERIODS} = 
	sum {a in LOAD_AREAS, h in TIMEPOINTS: period[h]=p} system_load[a, h] * hours_in_sample[h];

# Balancing areas are the unit -- each including multiple load areas -- at which operating reserves are met in the model. Those are currently the same as the primary NERC subregions.
set BALANCING_AREAS;

# Balancing areas param in LOAD_AREAS
param balancing_area {LOAD_AREAS} symbolic in BALANCING_AREAS;

param nems_fuel_region {LOAD_AREAS} symbolic;
set NEMS_FUEL_REGIONS = setof {a in LOAD_AREAS} (nems_fuel_region[a]);


###################
# Financial data

# the year to which all costs should be discounted and the year for which all costs are specified
# so this means that the capital cost of a generator is in $base_year and would have cost $overnight_cost in $base_year
# overnight_costs of generators march down their overnight_cost_change curves in years past this number
param base_year = 2007;

# annual rate (real) to use to discount future costs to current year
# a 7% real discount rate was chosen as per the recommendations of the Office of Managment and Budget
# see http://www.whitehouse.gov/omb/rewrite/circulars/a094/a094.html#8 or subsequent revisions
# (inflation is not included in a real discount rate so we're discounting constant year dollars here)
param discount_rate = 0.07;

# this parameter converts uniform payments made in each year of the period to a lump-sum value in the first year of the period
param bring_annual_costs_to_start_of_period =
	# CRF to convert uniform annual payments to a lump sum in the year before the period begins
	( 1 - ( 1 + discount_rate )^( -1 * num_years_per_period ) ) / discount_rate
	# Convert the value from the year before the period starts to the value in the first year of the period.
	* ( 1 + discount_rate );

# this parameter discounts costs incurred at the start of each period back to the base year
param discount_to_base_year {p in PERIODS} =
	bring_annual_costs_to_start_of_period
	# future value (in the year the period starts) to present value (in the base year)
	* 1 / ( 1 + discount_rate ) ^ ( p - base_year );

# planning reserve margin - fractional extra load the system must be able able to serve
# when there are no forced outages
param planning_reserve_margin = 0.15;

###############################################
#
# Technology and Fuel specifications for generators
# (most of these come from generator_info.tab)

set TECHNOLOGIES;

# database ids for technologies
param technology_id {TECHNOLOGIES} >= 0;

# earliest time when each technology can be built
param min_build_year {TECHNOLOGIES} >= 0;

# all possible years in the study 
set YEARS ordered = 2000 .. 2100 by 1;

# list of all possible fuels.  The fuel 'Storage' is included but lacks many of the params of normal fuels is it's a metafuel
# CAES has a fuel of natural gas here but also has a 'Storage' component implicit in its dispatch
set FUELS; 

# bio solid nonccs and ccs
set BIO_SOLID_FUELS = {"Bio_Solid", "Bio_Solid_CCS"};

# fuel used by this type of plant
param fuel {TECHNOLOGIES} symbolic in FUELS;

# is the fuel a biofuel?
param biofuel {FUELS} binary default 0;

# annual fuel price forecast in $/MMBtu
param fuel_price {a in LOAD_AREAS, f in FUELS, y in YEARS} >= 0;
	
# carbon content (tons) per MBtu of each fuel.  Can be negative for bio ccs projects.
param carbon_content {FUELS} default 0;

# the amount of carbon per MBtu of fuel that is sequestered by CCS projects (is zero for non CCS)
param carbon_sequestered {FUELS} default 0;

# biomass supply curve params
set LOAD_AREAS_AND_BIO_BREAKPOINTS dimen 3;

param num_bio_breakpoints {a in LOAD_AREAS, p in PERIODS_AND_PRESENT} = max( { (la, p, bp) in LOAD_AREAS_AND_BIO_BREAKPOINTS: la = a } bp , 0 );
param price_dollars_per_mmbtu_surplus_adjusted {a in LOAD_AREAS, p in PERIODS_AND_PRESENT, bp in 1..num_bio_breakpoints[a, p]}
	>= if bp = 1 then 0 else price_dollars_per_mmbtu_surplus_adjusted[a, p, bp-1];
param breakpoint_mmbtu_per_year {a in LOAD_AREAS, p in PERIODS_AND_PRESENT, bp in 1..num_bio_breakpoints[a, p]-1}
	> if bp = 1 then 0 else breakpoint_mmbtu_per_year[a, p, bp-1];
param breakpoint_mmbtu_per_period {a in LOAD_AREAS, p in PERIODS, bp in 1..num_bio_breakpoints[a, p]-1}
	= breakpoint_mmbtu_per_year[a, p, bp] * num_years_per_period;
param maximum_mmbtu_per_hour {a in LOAD_AREAS, p in PERIODS}
	= max{ bp in 1..num_bio_breakpoints[a, p]-1 } breakpoint_mmbtu_per_period[a, p, bp] / hours_in_period[p];

# the set of load areas that have Bio_Solid and/or Bio_Gas resources available
set BIO_FUELS_LOAD_AREAS := { f in FUELS, a in LOAD_AREAS, p in PERIODS: ( f = 'Bio_Solid' or f = 'Bio_Gas' ) };

# the amount of fuel, in MMBtu/period available for each biofuel for each load area
# this is the same in each period for bio gas
# and varies by period for bio solid, which is taken from the top of the bio solid supply curve
param bio_fuel_limit_by_load_area { (f, a, p) in BIO_FUELS_LOAD_AREAS }
	= 	( if f = 'Bio_Gas' then bio_gas_capacity_limit_mmbtu_per_hour[a]
		else if f = 'Bio_Solid' then maximum_mmbtu_per_hour[a, p] )
		* hours_in_period[p];
		  
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

# are new generators of this type installable (existing plant types are included in the set of TECHNOLOGIES)
param can_build_new {TECHNOLOGIES} binary;

# does the generator have a fixed hourly capacity factor?
param intermittent {TECHNOLOGIES} binary;

# is this type of plant run in baseload mode?
param baseload {TECHNOLOGIES} binary;

# is this type of plant capable of deep cycling (although not fully dispatchable)?
param flexible_baseload {TECHNOLOGIES} binary;

# is this technology an electricity storage technology?
param storage {TECHNOLOGIES} binary;

# is this plant dispatchable?  This includes compressed air energy storage but not battery storage
param dispatchable {TECHNOLOGIES} binary;

# is this plant a cogeneration plant?
param cogen {TECHNOLOGIES} binary;

# is this technology a hydro technology?
param hydro {t in TECHNOLOGIES} binary = if fuel[t] = 'Water' then 1 else 0;

# the fraction of time a generator is expected to be up
# it's assumed that for dispatchable or intermittent generators or for storage
# that their scheduled maintenence can be done when they're not going to be producing energy
# while for baseload this is not the case.
param gen_availability { t in TECHNOLOGIES } >= 0 <= 1 =
	if ( dispatchable[t] or intermittent[t] or storage[t] or hydro[t] ) then ( 1 - forced_outage_rate[t] )
	else if ( baseload[t] or flexible_baseload[t] ) then ( ( 1 - forced_outage_rate[t] ) * ( 1 - scheduled_outage_rate[t] ) );

# can this type of project only be installed in limited amounts?
param resource_limited {TECHNOLOGIES} binary;

# is this project a carbon capture and sequestration project?
param ccs {TECHNOLOGIES} binary;

# does this type of project have a minimum feasable installation size?
# only in place for Nuclear at the moment
# other technologies such as Coal, CSP and CCGT that hit their minimum feasable/economical size at ~100-300MW
# are left out of this constraint because the decrease in runtime is more important than added resolution on minimum install capacity,
# especially considering that if a project is economical, normally Switch will build a few hundred MW per load area
param min_build_capacity {TECHNOLOGIES} >= 0;

# Whether or not technologies located at the same place will compete for space
param competes_for_space {TECHNOLOGIES} binary;

# Solar-based technologies
set SOLAR_TECHNOLOGIES = {t in TECHNOLOGIES: fuel[t] = 'Solar'};
set SOLAR_CSP_TECHNOLOGIES = {"CSP_Trough_No_Storage", "CSP_Trough_6h_Storage"};
set SOLAR_DIST_PV_TECHNOLOGIES = {"Residential_PV", "Commercial_PV"};

# Peaker techonlogies that incur startup costs
set PEAKER_TECHNOLOGIES = { "Gas_Combustion_Turbine", "Gas_Combustion_Turbine_CCS", "Gas_Combustion_Turbine_EP", "Gas_Internal_Combustion_Engine_EP", "DistillateFuelOil_Combustion_Turbine_EP", "DistillateFuelOil_Internal_Combustion_Engine_EP", "Compressed_Air_Energy_Storage" };

# Intermediate technologies that incur startup and deep cycling costs
set INTERMEDIATE_TECHNOLOGIES = { "CCGT", "CCGT_CCS", "CCGT_EP", "Gas_Steam_Turbine_EP"};

#####################

# new storage techs ######

# what is the efficiency of storing electricity with this storage technology?
param storage_efficiency {TECHNOLOGIES} >= 0 <= 1;
# how fast can this technology store electricity relative to the releasing capacity
param max_store_rate {TECHNOLOGIES} >=0;

# Round-trip efficiency for compressed air energy storage
# this is inclusive of energy added from natural gas and stored energy, so it's greater than 1
param round_trip_efficiency_caes = 1.4;

#    Dispatch(stored) = Dispatch(NG) * caes_storage_to_ng_ratio
param caes_storage_to_ng_ratio {t in TECHNOLOGIES: t = 'Compressed_Air_Energy_Storage'} = storage_efficiency[t] / (round_trip_efficiency_caes - storage_efficiency[t]);

  
##################################################################
#
# Project data

set PROJECTS dimen 3; # Project ID, load area, technology

param location_id {PROJECTS} >= 0;
param capacity_limit {PROJECTS} >= 0;
param capacity_limit_conversion {PROJECTS} >= 0;

# set of the location ids of all central station solar projects, and the corresponding capacity_limit_by_location
# AMPL doesn't have good join syntax so the 'min' just picks the only value of capacity_limit 
# (all the values should be the same for a given location)
# sets that give the location of different technologies that are going to be competing for resources
set PROJECT_CENTRAL_STATION_SOLAR := { (pid, a, t) in PROJECTS: fuel[t] = 'Solar' and competes_for_space[t] };
set CENTRAL_STATION_SOLAR_LOCATIONS := 	setof { (pid, a, t) in PROJECT_CENTRAL_STATION_SOLAR } ( location_id[pid, a, t], a );
param central_station_solar_capacity_limit { (l, a) in CENTRAL_STATION_SOLAR_LOCATIONS }
	= min { (pid, a, t) in PROJECT_CENTRAL_STATION_SOLAR: location_id[pid, a, t] = l } capacity_limit[pid, a, t];

# an id that links entries in proposed_projects with an existing plant
# in order to constrain the amount of new generation installed to the existing plant capacity... for cogen only currently
param ep_project_replacement_id {PROJECTS} >= 0 default 0;
set PROJECT_EP_REPLACMENTS := { (pid, a, t) in PROJECTS: ep_project_replacement_id[pid, a, t] > 0 };

set EP_COGEN_REPLACEMENT_PLANT_LOCATIONS := setof { (pid, a, t) in PROJECTS: cogen[t] and can_build_new[t] } ( ep_project_replacement_id[pid, a, t], a );
param cogen_plant_capacity_limit { (l, a) in EP_COGEN_REPLACEMENT_PLANT_LOCATIONS }
	= min {(pid, a, t) in PROJECTS: cogen[t] and can_build_new[t] and ep_project_replacement_id[pid, a, t] = l } capacity_limit[pid, a, t];

# heat rate of each project (in MMBtu/MWh)
param heat_rate {PROJECTS} >= 0 ;

# the cogen thermal demand of each project per MWh of electricity out (in MMBtu/MWh)
param cogen_thermal_demand {PROJECTS} >= 0 ;

# cost of grid upgrades to support a new project, in dollars per peak MW.
# these are needed in order to deliver power from the interconnect point to
# the load center (or make it deliverable to other zones)
param connect_cost_per_mw {PROJECTS} >= 0;

# overnight cost for the plant ($/MW)
param overnight_cost {PROJECTS} >= 0;

# fixed O&M ($/MW-year)
param fixed_o_m {PROJECTS} >= 0;

# variable O&M ($/MWh)
param variable_o_m {PROJECTS} >= 0;

# annual rate of change of overnight cost, beginning at the base_year
param overnight_cost_change {PROJECTS};

# maximum capacity factors (%) for each project, each hour. 
# generally based on renewable resources available
set PROJ_INTERMITTENT_HOURS dimen 4;  # PROJECT_ID, LOAD_AREAS, TECHNOLOGIES, TIMEPOINTS
set PROJ_INTERMITTENT = setof {(pid, a, t, h) in PROJ_INTERMITTENT_HOURS} (pid, a, t);

check: card({(pid, a, t) in PROJECTS: intermittent[t] and resource_limited[t] and not ccs[t]} diff PROJ_INTERMITTENT) = 0;
param cap_factor {PROJ_INTERMITTENT_HOURS};

# make sure all hours are represented, and that cap factors make sense.
# Solar thermal can be parasitic, which means negative cap factors are allowed (just not TOO negative)
check {(pid, a, t, h) in PROJ_INTERMITTENT_HOURS: t in SOLAR_CSP_TECHNOLOGIES}: cap_factor[pid, a, t, h] >= -0.1;
# No other technology can be parasitic, so only positive cap factors allowed
check {(pid, a, t, h) in PROJ_INTERMITTENT_HOURS: not( t in SOLAR_CSP_TECHNOLOGIES) }: cap_factor[pid, a, t, h] >= 0;
# cap factors for solar can be greater than 1 because sometimes the sun shines more than 1000W/m^2
# which is how PV cap factors are defined.
# The below checks make sure that for other plants the cap factors
# are <= 1 but for solar they are <= 1.4
# (roughly the irradiation coming in from space, though the cap factor shouldn't ever approach this number)
check {(pid, a, t, h) in PROJ_INTERMITTENT_HOURS: not( t in SOLAR_TECHNOLOGIES )}: cap_factor[pid, a, t, h] <= 1;
check {(pid, a, t, h) in PROJ_INTERMITTENT_HOURS: t in SOLAR_TECHNOLOGIES }: cap_factor[pid, a, t, h] <= 1.4;
check {(pid, a, t) in PROJ_INTERMITTENT}: intermittent[t];

###############################################
# Existing generators

# name of each plant
set EXISTING_PLANTS dimen 3;  # project_id, load_area, technology

check {a in setof {(pid, a, t) in EXISTING_PLANTS} (a)}: a in LOAD_AREAS;

# the SWITCH database ids of the existing plant
param ep_plant_name {EXISTING_PLANTS} symbolic;
param ep_eia_id {EXISTING_PLANTS} >= 0;

# the size of the plant in MW
param ep_capacity_mw {EXISTING_PLANTS} >= 0;

# heat rate (in MBtu/MWh)
param ep_heat_rate {EXISTING_PLANTS} >= 0;

# the amount of thermal cogeneration that is produced per MWh of electricity produced (in MBtu/MWh)
# ep_heat_rate + ep_cogen_thermal_demand = total Mbtus used by the cogen plant
param ep_cogen_thermal_demand {EXISTING_PLANTS} >= 0;

# year when the plant was built (used to calculate annual capital cost and retirement date)
param ep_vintage {EXISTING_PLANTS} >= 0;

# overnight cost of the plant ($/MW)
param ep_overnight_cost {EXISTING_PLANTS} >= 0;

# connect cost of the plant ($/MW)
param ep_connect_cost_per_mw {EXISTING_PLANTS} >= 0;

# fixed O&M ($/MW-year)
param ep_fixed_o_m {EXISTING_PLANTS} >= 0;

# variable O&M ($/MWh)
param ep_variable_o_m {EXISTING_PLANTS} >= 0;

# location_id, which links existing bio projects with new bio projects through competing locations
# a location_id of zero is null.
param ep_location_id {EXISTING_PLANTS} >= 0;

###############################################
# Existing intermittent generators (existing wind, csp and pv)

# hours in which each existing intermittent renewable adds power to the grid
set EP_INTERMITTENT_HOURS dimen 4;  # project_id, load_area, technology, hour

# check that the existing plant cap factors are in order
set EP_INTERMITTENT = setof {(pid, a, t, h) in EP_INTERMITTENT_HOURS} (pid, a, t);
check: card({(pid, a, t) in EXISTING_PLANTS: intermittent[t] } diff EP_INTERMITTENT) = 0;

# capacity factor for existing intermittent renewables
# generally between 0 and 1, but for some solar plants the capacity factor may be more than 1
# due to capacity factor definition, so the limit here is 1.4
param eip_cap_factor {EP_INTERMITTENT_HOURS} >= 0 <=1.4;

###############################################
# year when the plant will be retired
# this is rounded up to the end of the study period when the retirement would occur,
# so power is generated and capital & O&M payments are made until the end of that period.
param ep_end_year {(pid, a, t) in EXISTING_PLANTS} =
  min( end_year, start_year + ceil( ( ep_vintage[pid, a, t] + max_age_years[t] - start_year ) / num_years_per_period ) * num_years_per_period );

# plant-period combinations when existing plants can run
# these are the times when a decision must be made about whether a plant will be kept available for the period
# or retired to save on fixed O&M (or fuel, for baseload plants)
# existing nuclear plants are assumed to be kept operational indefinitely, as their O&M costs generally keep them in really good condition
# hydro plants are kept operational indefinitely
set EP_PERIODS :=
  { (pid, a, t) in EXISTING_PLANTS, p in PERIODS:
  		( p < ep_end_year[pid, a, t] ) or
		( hydro[t] ) or
  		( t = 'Nuclear_EP' ) };

# if a period exists that is >= ep_end_year[pid, a, t], then this plant can be operational past the expected lifetime of the plant
param ep_could_be_operating_past_expected_lifetime { (pid, a, t, p) in EP_PERIODS } =
  (if p >= ep_end_year[pid, a, t]
   then 1
   else 0);

# do a join of EXISTING_PLANTS and PROJECT_EP_REPLACMENTS to find the end year of the original existing plant
# such that we can only allow it to install new replacement plants after the old plant has finished its operational lifetime
param original_ep_end_year { (pid, a, t) in PROJECT_EP_REPLACMENTS } = 
	min { (pid_ep, a_ep, t_ep) in EXISTING_PLANTS: pid_ep = ep_project_replacement_id[pid, a, t] } ep_end_year[pid_ep, a_ep, t_ep];

# project-vintage combinations that can be installed
# the second part of the union keeps existing plants from being prematurly replaced by making p >= original_ep_end_year
set PROJECT_VINTAGES = { (pid, a, t) in PROJECTS, p in PERIODS: (pid, a, t) not in PROJECT_EP_REPLACMENTS and p >= min_build_year[t] + construction_time_years[t] }
	union
	{ (pid, a, t) in PROJECT_EP_REPLACMENTS, p in PERIODS: p >= original_ep_end_year[pid, a, t] and p >= min_build_year[t] + construction_time_years[t] };
	
# date when a plant of each type and vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made) 
# until the end of that period. This avoids having artificial gaps
# between retirements and starting new plants.
param project_end_year {(pid, a, t, p) in PROJECT_VINTAGES} =
	min(end_year, p + ceil(max_age_years[t]/num_years_per_period)*num_years_per_period);

# a set that easily enables the summing over periods to represent the total installed capacity of a project
set PROJECT_VINTAGE_INSTALLED_PERIODS :=
	{ (pid, a, t, online_yr) in PROJECT_VINTAGES, p in PERIODS: online_yr <= p < project_end_year[pid, a, t, online_yr] };

# union of new projects and existing plants
set ALL_PLANTS := EXISTING_PLANTS union PROJECTS;

# union of new projects' and existing plants' available periods
set AVAILABLE_VINTAGES = PROJECT_VINTAGES union EP_PERIODS;

# plant-hour combinations when generators and storage can be available. 
set AVAILABLE_HOURS := { (pid, a, t, p) in AVAILABLE_VINTAGES, h in TIMEPOINTS: period[h] = p};

# plant-hour combinations when existing plants can be available. 
set EP_AVAILABLE_HOURS := { (pid, a, t, p, h) in AVAILABLE_HOURS: not can_build_new[t] };

# project-vintage-hour combinations when new plants are available. 
set PROJECT_VINTAGE_HOURS := { (pid, a, t, p, h) in AVAILABLE_HOURS: can_build_new[t] };

# project-vintage-date combinations when new plants are available
set AVAILABLE_DATES := setof { (pid, a, t, p, h) in AVAILABLE_HOURS, d in DATES: date[h] = d } (pid, a, t, p, d);
set PROJECT_AVAILABLE_DATES := { (pid, a, t, p, d) in AVAILABLE_DATES: can_build_new[t] };
set EP_AVAILABLE_DATES := { (pid, a, t, p, d) in AVAILABLE_DATES: not can_build_new[t] };


##################################################################
# RPS goals for each load area 

param enable_rps binary default 1;

# RPS compliance entity for each load area
param rps_compliance_entity {LOAD_AREAS} symbolic;
set RPS_AREAS = setof { a in LOAD_AREAS } (rps_compliance_entity[a]);

# determines if fuel falls in solar/wind/geo or gas/coal/nuclear/hydro
param rps_fuel_category {FUELS} symbolic;

param tech_qualifies_for_rps {t in TECHNOLOGIES: t <> 'Battery_Storage'} binary
	= if rps_fuel_category[fuel[t]] = 'renewable' then 1 else 0;

# read in the set of all rps targets, even the rps_areas with targets of zero
set RPS_TARGETS_ALL dimen 3; #RPS_AREAS, RPS_COMPLIANCE_TYPES, YEARS
set RPS_COMPLIANCE_TYPES = setof { (r, rps_compliance_type, yr) in RPS_TARGETS_ALL } (rps_compliance_type);

# rps compliance fraction as a function of yearly load
param rps_compliance_fraction {RPS_AREAS, RPS_COMPLIANCE_TYPES, YEARS} >= 0, <= 1;

# average the RPS compliance percentages over a period to get the RPS target for that period
# the end year is the year after the last period, so this sum doesn't include it.
param rps_compliance_fraction_in_period { r in RPS_AREAS, c in RPS_COMPLIANCE_TYPES, p in PERIODS } = 
	sum { yr in YEARS: yr >= p and yr < p + num_years_per_period }
	rps_compliance_fraction[r, c, yr] / num_years_per_period;

# now restrict the RPS_TARGETS set to periods for which there is a target of > 0.
set RPS_TARGETS = { r in RPS_AREAS, c in RPS_COMPLIANCE_TYPES, p in PERIODS: rps_compliance_fraction_in_period[r, c, p] > 0 };

# a small but pesky amount of rps area/period combos don't have enough energy to meet the distributed rps in toy problems
# these are really small rps areas, so droping the distributed rps requirement won't change the solution significantally
# the able_to_meet_rps param will be used below to drop Satisfy_RPS for these distributed rps area/period combos
# (able_to_meet_rps = 1 for all primary RPS)
param able_to_meet_rps { (r, c, p) in RPS_TARGETS } binary =
  if c = 'Distributed' and 
   ( ( sum { (pid, a, t, p, h) in AVAILABLE_HOURS: rps_compliance_entity[a] = r and t in SOLAR_DIST_PV_TECHNOLOGIES }
      ( if can_build_new[t] then capacity_limit[pid, a, t] * cap_factor[pid, a, t, h]
        else ep_capacity_mw[pid, a, t] * eip_cap_factor[pid, a, t, h] )
	  * hours_in_sample[h] * gen_availability[t] )
  < ( sum { a in LOAD_AREAS, h in TIMEPOINTS: rps_compliance_entity[a] = r and period[h] = p } 
      system_load[a, h] * hours_in_sample[h]* rps_compliance_fraction_in_period[r, c, p] ) )
  then 0 else 1;
	
###############################################
# Carbon Policy

### Carbon Cost
# cost of carbon emissions ($/ton), e.g., from a carbon tax
# can also be set negative to drive renewables out of the system
param carbon_cost default 0;

# set and parameters used to make carbon cost curves
set CARBON_COSTS ordered;

### Carbon Cap
# does this scenario include a cap on carbon emissions?
param enable_carbon_cap >= 0, <= 1 default 1;

# the base (1990) carbon emissions in tCO2/Yr
param base_carbon_emissions = 284800000;
# the fraction of emissions relative to the base year of 1990 that should be allowed in a given year
param carbon_emissions_relative_to_base {YEARS};
# add up all the targets for each period to get the total cap level in each period
param carbon_cap {p in PERIODS} = base_carbon_emissions *
		( sum{ y in YEARS: y >= p and y < p + num_years_per_period } carbon_emissions_relative_to_base[y] );

##############################################
# Existing hydro plants (assumed impossible to build more, but these last forever)

# indexing sets for hydro data (read in along with data tables)
# (this should probably be monthly data, but this has equivalent effect,
# and doesn't require adding a month dataset and month <-> date links)
set PROJ_HYDRO_DATES dimen 4; # project_id, load_area, technology, date

# average output (in MW) for dams aggregated to the load area level for each day
# (note: we assume that the average dispatch for each day must come out at this average level,
# and flow will always be between minimum and maximum levels)
# average is based on historical power production for each month
# for simple hydro, minimum output is a fixed fraction of average output
# for pumped hydro, minimum output is a negative value, showing the maximum pumping rate
param avg_hydro_output {PROJ_HYDRO_DATES};

# Make sure hydro outputs aren't outside the bounds of the turbine capacities (should have already been fixed in mysql)
check {(pid, a, t) in EXISTING_PLANTS, d in DATES: hydro[t]}: 
  -ep_capacity_mw[pid, a, t] <= avg_hydro_output[pid, a, t, d] <= ep_capacity_mw[pid, a, t];
check {(pid, a, t) in EXISTING_PLANTS, d in DATES: t = 'Hydro_NonPumped'}: 
  0 <= avg_hydro_output[pid, a, t, d] <= ep_capacity_mw[pid, a, t];

# make sure each hydro plant has an entry for each date.
check {(pid, a, t) in EXISTING_PLANTS: hydro[t]}:
	card(DATES symdiff setof {(pid, a, t, d) in PROJ_HYDRO_DATES} (d)) = 0;

# minimum dispatch that non-pumped hydro generators must do in each hour
# TODO this should be derived from USGS stream flow data
# right now, it's set at 50% of the average stream flow for each month
# there isn't a similar paramter for pumped hydro because it is assumed that the lower resevoir is large enough
# such that hourly stream flow can be maintained independent of the pumped hydro dispatch
# especially because the daily flow through the turbine will be constrained to be within historical monthly averages below
param min_nonpumped_hydro_dispatch_fraction = 0.5;

# useful pumped hydro sets for recording results 
set PUMPED_HYDRO_AVAILABLE_HOURS_BY_PID := { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: t = 'Hydro_Pumped' };
set PUMPED_HYDRO_AVAILABLE_HOURS := setof { (pid, a, t, p, h) in PUMPED_HYDRO_AVAILABLE_HOURS_BY_PID } (a, t, p, h);

# load_area-hour combinations when hydro existing plants can be available. 
set NONPUMPED_HYDRO_AVAILABLE_HOURS := setof { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: t = 'Hydro_NonPumped' } (a, t, p, h);
set NONPUMPED_HYDRO_DATES := setof { (pid, a, t, p) in EP_PERIODS, d in DATES: t = 'Hydro_NonPumped' and period_of_date[d] = p } (a, t, p, d);
set PUMPED_HYDRO_DATES := setof { (pid, a, t, p) in EP_PERIODS, d in DATES: t = 'Hydro_Pumped' and period_of_date[d] = p } (a, t, p, d);
set HYDRO_AVAILABLE_HOURS := NONPUMPED_HYDRO_AVAILABLE_HOURS union PUMPED_HYDRO_AVAILABLE_HOURS;
set HYDRO_DATES := NONPUMPED_HYDRO_DATES union PUMPED_HYDRO_DATES;

# sum up the hydro capacity in each load area
set HYDRO_TECH_LOAD_AREAS := {a in LOAD_AREAS, t in TECHNOLOGIES: hydro[t]
	and ( sum{(pid, a, t) in EXISTING_PLANTS} ep_capacity_mw[pid, a, t] > 0 ) };
param hydro_capacity_mw_in_load_area { (a, t) in HYDRO_TECH_LOAD_AREAS }
	= sum{(pid, a, t) in EXISTING_PLANTS: hydro[t]} ep_capacity_mw[pid, a, t];

# also sum up the hydro output to load area level because it's going to be dispatched at that level of aggregation
param avg_hydro_output_load_area_agg_unrestricted { (a, t, p, d) in HYDRO_DATES }
	= sum {(pid, a, t) in EXISTING_PLANTS: hydro[t]} avg_hydro_output[pid, a, t, d];
# as avg_hydro_output_load_area_agg_unrestricted has gen_availability[t] built in because it's from historical generation data,
# it may exceed hydro_capacity_mw_in_load_area[a, t] * gen_availability[t],
# so the param below restricts generation to the amount expected to be available in the future for each date 
param avg_hydro_output_load_area_agg { (a, t, p, d) in HYDRO_DATES }
	= 	if ( avg_hydro_output_load_area_agg_unrestricted[a, t, p, d] > hydro_capacity_mw_in_load_area[a, t] * gen_availability[t] )
		then hydro_capacity_mw_in_load_area[a, t] * gen_availability[t]
		else avg_hydro_output_load_area_agg_unrestricted[a, t, p, d];
	

###############################################
# calculate discounted costs for plants

# apply projected annual real cost changes to each technology,
# to get the capital, fixed and variable costs if it is installed 
# at each possible vintage date

# first, the capital cost of the plant and any 
# interconnecting lines and grid upgrades
# (all costs are in $/MW)

# calculate fraction of capital cost incurred in each year of the construction period based on declination schedule

# capital cost fractions during construction period and resulting annual payment streams
# YEAR_OF_CONSTRUCTION set used to calculate time between first payment on each cost fraction and
# the project end-year or the model base
# this number is subtracted from the construction time in the discounting process
set YEAR_OF_CONSTRUCTION ordered = 0 .. 5 by 1;

param cost_fraction {t in TECHNOLOGIES, yr in YEAR_OF_CONSTRUCTION};

param project_vintage_overnight_costs {(pid, a, t, p) in PROJECT_VINTAGES} = 
	# Overnight cost, adjusted for projected cost changes.
	overnight_cost[pid, a, t] * ( 1 + overnight_cost_change[pid, a, t] )^( p - construction_time_years[t] - base_year );


# CCS projects incur extra pipeline costs if their load area doesn't have a viable sink
# we'll use the assumptions of R.S. Middleton, J.M. Bielicki / Energy Policy 37 (2009) 1052–1060 
# their fig 2 gives CO2 flow [kt/yr] vs unit cost [$/km/t],
# we assume that we're building relativly large pipelines (small ones quickly combine to form bigger ones)
# which puts us at $100/km/ktCO2 (a 16" pipeline).
# This pipeline can transport ~5000 ktCO2 (per year), roughly the output of a new 1GW coal plant.
# the pipeline cost is therefore $90/km/ktCO2*yr 
# NOTE: Bielicki's y-axis is wrong... it says tonnes when it's really ktonnes
# this is corroborated by a document found in switch_input_data/CCS called
# 'Using Natural Gas Transmission Pipeline Costs to Estimate Hydrogen Pipeline Costs' by Nathan Parker
# this source uses similar pipline data to Bielicki but differes in costs by 10^3 (hence Bielicki's error)

# we'll assume the the pipeline has to be sized for maximum carbon capacity (i.e. no local carbon storage)
# the kt of carbon generated per year is given on the last line
# gen_availability is not used because the pipeline should be sized for max capacity, not average
# also, this cost doesn't decrease over time because most pipeline learning has already been done
param ccs_pipeline_cost_per_mw { (pid, a, t) in PROJECTS: ccs[t] and ccs_distance_km[a] > 0 } =
	90 * ccs_distance_km[a] * 
	( heat_rate[pid, a, t] * carbon_sequestered[fuel[t]] * 8766 ) / 1000;


# The equations below make a working assumption that the "finance rate" and "discount rate" are the same value. 
# If those numbers take on different values, the equation will need to be inspected for correctness. 
# Bring the series of lump-sum costs made during construction up to the year before the plant starts operation. 
param cost_of_plant_one_year_before_operational {(pid, a, t, p) in AVAILABLE_VINTAGES} =
  # Connect costs and ccs pipeline costs are incurred in said year, so they don't accrue interest
  ( if can_build_new[t] then connect_cost_per_mw[pid, a, t] else ep_connect_cost_per_mw[pid, a, t] ) +
  ( if ( ccs[t] and ccs_distance_km[a] > 0 ) then ccs_pipeline_cost_per_mw[pid, a, t] else 0 ) +  
  # Construction costs are incurred annually during the construction phase. 
  sum{ yr_of_constr in YEAR_OF_CONSTRUCTION } (
  	cost_fraction[t, yr_of_constr] * ( if can_build_new[t] then project_vintage_overnight_costs[pid, a, t, p] else ep_overnight_cost[pid, a, t] )
  	# This exponent will range from (construction_time - 1) to 0, meaning the cost of the last year's construction doesn't accrue interest.
  	* (1 + discount_rate) ^ ( construction_time_years[t] - yr_of_constr - 1 )
  	);

# Spread the costs of the plant evenly over the plant's operation. 
# This doesn't represent the cash flow. Rather, it spreads the costs of bringing the plant online evenly over the operational period
# so the linear program optimization won't experience "boundary conditions"
# and avoid making long-term investments close to the last year of the simulation. 
param capital_cost_annual_payment {(pid, a, t, p) in AVAILABLE_VINTAGES} = 
  cost_of_plant_one_year_before_operational[pid, a, t, p] *
  discount_rate / ( 1 - (1 + discount_rate) ^ ( -1 * max_age_years[t] ) );

# Convert annual payments made in each period the plant is operational to a lump-sum in the first year of the period and then discount back to the base year
param capital_cost {(pid, a, t, online_yr) in PROJECT_VINTAGES} = 
  sum {p in PERIODS: online_yr <= p < project_end_year[pid, a, t, online_yr]}
  	capital_cost_annual_payment [pid, a, t, online_yr] * discount_to_base_year[p];

# discount capital costs to a lump-sum value at the start of the study.
param ep_capital_cost { (pid, a, t, p) in EP_PERIODS } =
  if ep_could_be_operating_past_expected_lifetime[pid, a, t, p] then 0
    else capital_cost_annual_payment[pid, a, t, p] * discount_to_base_year[p];

# discount fixed operations and maintenence costs to a lump-sum value at the start of the study.
param fixed_o_m_discounted { (pid, a, t, online_yr) in PROJECT_VINTAGES } = 
  sum {p in PERIODS: online_yr <= p < project_end_year[pid, a, t, online_yr]} fixed_o_m[pid, a, t]
  * discount_to_base_year[p];

# same for existing plants
# these are for each period rather than the whole plant lifetime because OperateEPDuringPeriod determines the plant's end_year.
param ep_fixed_o_m_by_period { (pid, a, t, p) in EP_PERIODS } = 
	ep_fixed_o_m[pid, a, t] * discount_to_base_year[p];

# For now, all hours in each study period use the same fuel cost which averages annual prices over the course of each study period.
# This could be updated to use fuel costs that vary by month, or for an hourly model, it could interpolate between annual forecasts
# Bio solid fuel costs and natural gas costs are zero here - they'll be included via separate supply curves
param fuel_price_in_period { (pid, a, t, p) in AVAILABLE_VINTAGES } := 
		( sum{ y in YEARS: y >= p and y < p + num_years_per_period } fuel_price[a, fuel[t], y] ) / num_years_per_period;

# variable operations and maintence cost per MWh in each period for each generator for hourly dispatch 
# In variable costs, hours_in_sample is a weight intended to reflect how many hours are represented by a timepoint.
param variable_o_m_cost_hourly { (pid, a, t, p, h) in AVAILABLE_HOURS } =
	( if can_build_new[t] then variable_o_m[pid, a, t] else ep_variable_o_m[pid, a, t] )
	* ( hours_in_sample[h] / num_years_per_period ) * discount_to_base_year[p];

# same for the fuel cost per MWh
# fuel_price_in_period is 0 for bio solid and natural gas fuels as all bio solid and NG fuel costs are calculated via their respective supply curves
param fuel_cost_hourly { (pid, a, t, p, h) in AVAILABLE_HOURS } =
	( if can_build_new[t] then heat_rate[pid, a, t] else ep_heat_rate[pid, a, t] )
  	* fuel_price_in_period[pid, a, t, p]
	* ( hours_in_sample[h] / num_years_per_period ) * discount_to_base_year[p];

# same for the carbon cost per MWh
param carbon_cost_per_mwh_hourly { (pid, a, t, p, h) in AVAILABLE_HOURS } = 
	( if can_build_new[t] then heat_rate[pid, a, t] else ep_heat_rate[pid, a, t] )
	* carbon_content[fuel[t]] * carbon_cost
	* ( hours_in_sample[h] / num_years_per_period ) * discount_to_base_year[p];

# now tally all variable costs ($/MWh costs) by period for generators that aren't dispached hourly (i.e. intermittent and baseload)
# variable_cost is inclusive of variable o & m, fuel and carbon
param variable_cost { (pid, a, t, online_yr) in PROJECT_VINTAGES: intermittent[t] or baseload[t] } = 
  sum { p in PERIODS, h in TIMEPOINTS: online_yr <= p < project_end_year[pid, a, t, online_yr] and period[h] = p }
	( ( if baseload[t] then 1 else if intermittent [t] then cap_factor[pid, a, t, h] ) * gen_availability[t]
	* ( variable_o_m_cost_hourly[pid, a, t, p, h] + fuel_cost_hourly[pid, a, t, p, h] + carbon_cost_per_mwh_hourly[pid, a, t, p, h] ) );


#######################################
# Operating reserves

# Operating reserve level parameters

# fraction of load that must be covered by 10-min spinning reserves
param load_only_spinning_reserve_requirement {BALANCING_AREAS};

# fraction of wind generation that must be covered by spinning reserves
param wind_spinning_reserve_requirement {BALANCING_AREAS};

# fraction of solar generation that must be covered by spinning reserves
# Solar CSP with 6h of thermal storage is excluded as its output is steady and does not impose additional spinning reserve requirements
param solar_spinning_reserve_requirement {BALANCING_AREAS};

# spinning reserve is usually at least half of the total operating reserve requirement (spin + quickstart), so the param below is set to 1
param quickstart_requirement_relative_to_spinning_reserve_requirement {BALANCING_AREAS};

# Solar CSP with no storage contributes to th quickstart but not to the spinning reserve requirement
# We assume that same fraction of no storage CSP generation will contribute to the quickstart requirements as non-CSP solar generation contributes to spinning reserve requirements
param csp_quickstart_reserve_requirement { b in BALANCING_AREAS } = solar_spinning_reserve_requirement[b];

# We assume that providing spinning reserves means that thermal generators incur an extra cost by backing off from their optimal output and incurring a heat rate penalty, so fuel costs and carbon costs are affected.
# The heat_rate_penalty_spinning_reserve param is a fraction; it is multiplied by the full-load heat rate to get the actual heat rate for spinning reserve.
param heat_rate_penalty_spinning_reserve { t in TECHNOLOGIES };

param heat_rate_spinning_reserve { (pid, a, t) in ALL_PLANTS } =
	heat_rate_penalty_spinning_reserve[t] 
	* ( if can_build_new[t] then heat_rate[pid, a, t] else ep_heat_rate[pid, a, t] );

param fuel_cost_hourly_spinning_reserve { (pid, a, t, p, h) in AVAILABLE_HOURS } =
	heat_rate_spinning_reserve[pid, a, t] * fuel_price_in_period[pid, a, t, p]
	* ( hours_in_sample[h] / num_years_per_period ) * discount_to_base_year[p];

param carbon_cost_per_mwh_hourly_spinning_reserve { (pid, a, t, p, h) in AVAILABLE_HOURS } = 
	heat_rate_spinning_reserve[pid, a, t] * carbon_content[fuel[t]] * carbon_cost
	* ( hours_in_sample[h] / num_years_per_period ) * discount_to_base_year[p];

# The maximum percentage of generator capacity that can be dedicated to spinning reserves (as opposed to useful generation)
# In general, the amount of capacity that can be provided for spinning reserves is the generator's 10-minute ramp rate
param max_spinning_reserve_fraction_of_capacity { t in TECHNOLOGIES };

# the fraction of time that operating reserves will actually be deployed for useful energy
# this is used in the hydro and storage energy balance constraints
param fraction_of_time_operating_reserves_are_deployed := 0.01;


#######################################
# Deep-cycling (flexible baseload coal and intermediate plants) and startup costs (peakers and intermediate plants)

# fraction of flexible baseload generator capacity that must run in baseload mode
param minimum_loading {TECHNOLOGIES} >= 0;

# cycling penalty incurred by flexible baseload plants when below full load
param deep_cycling_penalty {TECHNOLOGIES} >= 0;

# startup fuel use (MMBtu/MW) and other nonfuel costs ($/MW)
param startup_mmbtu_per_mw {TECHNOLOGIES} >= 0;
param startup_nonfuel_cost_dollars_per_mw {TECHNOLOGIES} >= 0;

param startup_nonfuel_cost_per_mw_hourly { (pid, a, t, p, h) in AVAILABLE_HOURS } =
	hours_in_sample[h]
	* startup_nonfuel_cost_dollars_per_mw[t]
  	/ num_years_per_period
    * discount_to_base_year[p];

# fuel_price_in_period is 0 for natural gas plants (handled via the NG supply curve), but this does apply to oil peaker plants
param startup_fuel_cost_per_mw_hourly { (pid, a, t, p, h) in AVAILABLE_HOURS } =
	hours_in_sample[h]
	* startup_mmbtu_per_mw[t] * fuel_price_in_period[pid, a, t, p]
  	/ num_years_per_period
    * discount_to_base_year[p];

param startup_carbon_cost_per_mw_hourly { (pid, a, t, p, h) in AVAILABLE_HOURS } = 
   	hours_in_sample[h] 
   	* ( startup_mmbtu_per_mw[t] * carbon_content[fuel[t]] * carbon_cost
	) / num_years_per_period
	* discount_to_base_year[p];
	
    

###############################################
# Local T&D

# parameters for local transmission and distribution from the large-scale network to distributed loads
param local_td_max_age_years = 20;
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

# amount of local transmission and distribution capacity
# (to carry peak power from transmission network to distributed loads)
param install_local_td {a in LOAD_AREAS, p in PERIODS} = 
  max( 0, # This max ensures that the value will never fall below 0. 
  (max_system_load[a,p] - existing_local_td[a] - sum { build in PERIODS: build < p } install_local_td[a, build] ) );

# date when a when local T&D infrastructure of each vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made).
param local_td_end_year {p in PERIODS} =
  min(end_year, p + ceil(local_td_max_age_years/num_years_per_period)*num_years_per_period);

# discounted cost per MW for local T&D
# the costs are already regionalized, so no need to do it again here
param local_td_cost_per_mw {a in LOAD_AREAS, online_yr in PERIODS} = 
  sum {p in PERIODS: online_yr <= p < local_td_end_year[p]}
  local_td_new_annual_payment_per_mw[a]
  * discount_to_base_year[p];

# distribution losses, expressed as percentage of system load
# this is not applied to distributed solar PV systems, which are assumed to be located within the distribution system, close to load
# we took 5.3% losses value from ReEDS Solar Vision documentation, http://www1.eere.energy.gov/solar/pdfs/svs_appendix_a_model_descriptions_data.pdf
param distribution_losses = 0.053;

###############################################
# Transmission lines

# the cost to maintain the existing transmission infrustructure over all of WECC
param transmission_sunk_annual_payment {LOAD_AREAS} >= 0;

# forced outage rate for transmission lines, used for probabilistic dispatch(!)
param transmission_forced_outage_rate = 0.01;

# possible transmission lines are listed in advance;
# these include all possible combinations of LOAD_AREAS, with no double-counting
# The model could be simplified by only allowing lines to be built between neighboring zones.
set TRANSMISSION_LINES in {LOAD_AREAS, LOAD_AREAS};

# unique ID for each transmission line, used for reporting results
param transmission_line_id {TRANSMISSION_LINES};

# length of each transmission line
param transmission_length_km {TRANSMISSION_LINES};

# delivery efficiency on each transmission line
param transmission_efficiency {TRANSMISSION_LINES};

# the rating of existing lines in MW 
param existing_transfer_capacity_mw {TRANSMISSION_LINES} >= 0 default 0;

# are new builds of transmission lines allowed along this transmission corridor?
param new_transmission_builds_allowed {TRANSMISSION_LINES} binary;
set TRANSMISSION_LINES_NEW_BUILDS_ALLOWED := { (a1, a2) in TRANSMISSION_LINES: new_transmission_builds_allowed[a1, a2] };

# now get discounted costs per MW for transmission lines

# $ cost per mw-km for new transmission lines
# because transmission lines are built in one direction only and then constrained to have the same capacity in both directions
# the per direction value needs to be half of what it would cost to install each line
param transmission_capital_cost_per_mw_km = 1000;
param transmission_capital_cost_per_mw_km_per_direction = transmission_capital_cost_per_mw_km / 2;

# costs for transmission maintenance, which is quoted as 3% of the installation cost in the 2009 WREZ transmission model transmission data
# costs for existing transmission maintenance is included in the transmission_sunk_annual_payment (most of the lines are old, so this is primarily O&M costs)
param transmission_fixed_o_m_annual_payment { (a1, a2) in TRANSMISSION_LINES_NEW_BUILDS_ALLOWED } =
	0.03 * transmission_capital_cost_per_mw_km_per_direction * transmission_length_km[a1, a2]
		 * ( (economic_multiplier[a1] + economic_multiplier[a2]) / 2 );

# financial age for transmission lines - from the 2009 WREZ transmission model transmission data
param transmission_max_age_years = 20;

# the time it takes to construct transmission lines.  An expedited permitting process is assumed here, making this value 5 years.
param transmission_construction_time_years = 5;

# date when a transmission line of each vintage will stop paying capital costs in the simulation
# it will continue to pay O&M costs because transmission lines are rarely retired (and are not allowed to be retired in SWITCH)
param transmission_end_year {p in PERIODS} =
  min( end_year, p + ceil( transmission_max_age_years / num_years_per_period ) * num_years_per_period );

# cost per MW for transmission lines
param transmission_capital_cost_annual_payment { (a1, a2) in TRANSMISSION_LINES_NEW_BUILDS_ALLOWED } = 
  discount_rate / ( 1 - ( 1 + discount_rate ) ^ ( -1 * transmission_max_age_years ) ) 
  * transmission_capital_cost_per_mw_km_per_direction * transmission_length_km[a1, a2]
  * ( (economic_multiplier[a1] + economic_multiplier[a2]) / 2 );

# the set of all periods in which transmission decisions must be made
set TRANSMISSION_LINE_PERIODS := { (a1, a2) in TRANSMISSION_LINES, p in PERIODS };

# the set of periods in which new transmission lines can be built
# if an investment period is longer than the construction time of transmission lines, then let them be built in any period
# because we're generally more interested in what happens in later parts of an investment period, by which transmission could have been built
set TRANSMISSION_LINE_NEW_PERIODS := { (a1, a2, p) in TRANSMISSION_LINE_PERIODS:
		(a1, a2) in TRANSMISSION_LINES_NEW_BUILDS_ALLOWED
		and p >= ( if num_years_per_period > transmission_construction_time_years then present_year else present_year + transmission_construction_time_years ) };

# discounted transmission cost per MW up to their financial lifetime - the non-discounted cost of transmission doesn't decrease (or increase) by period
param transmission_cost_per_mw { (a1, a2, online_yr) in TRANSMISSION_LINE_NEW_PERIODS } =
  sum { p in PERIODS: online_yr <= p < transmission_end_year[p] } transmission_capital_cost_annual_payment[a1, a2] * discount_to_base_year[p];

# Fixed annual O&M costs that are paid while the transmission line is operating (up to the end of the study period)
param transmission_fixed_o_m_by_period { (a1, a2, online_yr) in TRANSMISSION_LINE_NEW_PERIODS } = 
  sum { p in PERIODS: online_yr <= p } transmission_fixed_o_m_annual_payment[a1, a2] * discount_to_base_year[p];

# Hourly transmission decisions are made on the basis of transmission fuel category, as defined below

# this param tracks whether a transmission corridor is between different RPS areas
# because the transmission between rps areas will be divided in to renewable and fossilish,
# while transmission within a single rps area will only have one transmission flavor of 'na'
# (see the definition of the set TRANSMISSION_LINES_FUEL_CATEGORIES right below)
# if RPS is not enabled, transmission_line_is_between_rps_areas always returns zero, which will define all corridors to have the transmission flavor of 'na'
param transmission_line_is_between_rps_areas { (a1, a2) in TRANSMISSION_LINES } binary = 
	if enable_rps = 1 and rps_compliance_entity[a1] != rps_compliance_entity[a2] then 1 else 0;
set ALL_TRANSMISSION_FUEL_CATEGORIES = {"renewable", "fossilish", "na"};
set TRANSMISSION_LINES_FUEL_CATEGORIES := { (a1, a2) in TRANSMISSION_LINES, fc in ALL_TRANSMISSION_FUEL_CATEGORIES:
		( transmission_line_is_between_rps_areas[a1, a2] and ( fc = "renewable" or fc = "fossilish" ) )
		or ( not transmission_line_is_between_rps_areas[a1, a2] and fc = 'na' ) };

# trans_line-vintage-hour combinations for which dispatch decisions must be made
set TRANSMISSION_LINE_HOURS := { (a1, a2, fc) in TRANSMISSION_LINES_FUEL_CATEGORIES, p in PERIODS, h in TIMEPOINTS: p = period[h] };

######## TRANSMISSION VARIABLES ########

# number of MW to install in each transmission corridor at each vintage
var InstallTrans { TRANSMISSION_LINE_NEW_PERIODS } >= 0;

# number of MW to transmit through each transmission corridor in each hour for each transmission fuel category
var DispatchTrans { (a1, a2, fc, p, h) in TRANSMISSION_LINE_HOURS } >= 0;

######## GENERATOR AND STORAGE VARIABLES ########

# Number of MW of power consumed in each load area in each hour for non distributed and distributed projects
# in terms of actual load met - distribution losses are NOT consumed
# This is needed for RPS in cases where some excess power is spilled.
var ConsumeNonDistributedPower {LOAD_AREAS, TIMEPOINTS} >= 0;
# same on a reserve basis
var ConsumeNonDistributedPower_Reserve {LOAD_AREAS, TIMEPOINTS} >= 0;

# MW of Renewable Energy Certificates (RECs) to consume in each RPS area in each hour
var ConsumeREC {r in RPS_AREAS, h in TIMEPOINTS} >= 0;


# Project-level decision variables about how much generation to make available and how much power to dispatch

# number of MW to install for each project in each investment period
var InstallGen {PROJECT_VINTAGES} >= 0;

# derived variable which represents the total amount of capacity installed and active for each project in each investment period
var Installed_To_Date { (pid, a, t, p) in PROJECT_VINTAGES } =
	sum { (pid, a, t, online_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, online_yr];

# number of MW to dispatch from each dispatchable generator
var DispatchGen {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t]} >= 0;

# number of MW to dispatch from each flexible baseload generator each day
var DispatchFlexibleBaseload { (pid, a, t, p, d) in AVAILABLE_DATES: flexible_baseload[t] } >= 0;

# CCGT capacity committed and online in each hour
var Commit_Intermediate_Gen { (pid, a, t, p, h) in AVAILABLE_HOURS: t in INTERMEDIATE_TECHNOLOGIES } >= 0;

  
# binary constraint that restricts small plants of certain types of generators from being built
# this quantity is one when there is there is not a constraint on how small plants can be
# and is zero when there is a constraint
# currently only enforced for new Nuclear generators
var BuildGenOrNot { (pid, a, t, p) in PROJECT_VINTAGES: min_build_capacity[t] > 0 } >= 0, <= 1, integer;

# binary variable that decides to either operate or mothball an existing plant during each study period.
# existing intermittent plants generally have low operational costs and are therefore kept running, hence are excluded from this variable definition
var OperateEPDuringPeriod { (pid, a, t, p) in EP_PERIODS: not intermittent[t] and not hydro[t] } >= 0, <= 1, integer;

# number of MW to generate from each existing plant, in each hour
var ProducePowerEP { (pid, a, t, p, h) in EP_AVAILABLE_HOURS } >= 0;

# a derived variable of how far down its cycle each flexible baseload generator is ramped down each day
# this amount is multiplied by the deep_cycling_penalty to calculate extra fuel use and costs incurred
var Deep_Cycle_Amount { (pid, a, t, p, d) in AVAILABLE_DATES: flexible_baseload[t] } = 
 if can_build_new[t]
 then ( Installed_To_Date[pid, a, t, p] * gen_availability[t]
	    - DispatchFlexibleBaseload[pid, a, t, p, d] )
 else ( OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] * gen_availability[t]
		- DispatchFlexibleBaseload[pid, a, t, p, d] );

# Startup variables
# how much peaker and CCGT capacity was started up since the previous hour
# variable has to be non-negative as a penalty is only applied when ramping up
var Startup_MW_from_Last_Hour { (pid, a, t, p, h) in AVAILABLE_HOURS: t in PEAKER_TECHNOLOGIES or t in INTERMEDIATE_TECHNOLOGIES } >= 0;

# a derived variable indicating the number of MMbtu of Biomass Solid fuel to consume each period in each load area,
# as a function of the installed biomass generation capacity.
# this corresponds via the objective function to a price level on the biomass solid supply curve
# if this variable is changed, check subject to Maximum_Resource_Bio below - it may need to be changed as well
var ConsumeBioSolid {a in LOAD_AREAS, p in PERIODS: num_bio_breakpoints[a, p] > 0 } = 
	# the hourly MWh output of biomass solid projects in baseload mode is below
		(
		( sum { (pid, a, t, p) in PROJECT_VINTAGES: fuel[t] in BIO_SOLID_FUELS } 
			( Installed_To_Date[pid, a, t, p] * gen_availability[t]
			* ( heat_rate[pid, a, t] + cogen_thermal_demand[pid, a, t] ) ) )
		+ ( sum { (pid, a, t, p) in EP_PERIODS: fuel[t] in BIO_SOLID_FUELS } 
			( OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] * gen_availability[t]
			* ( ep_heat_rate[pid, a, t] + ep_cogen_thermal_demand[pid, a, t] ) ) )
		# multiply by the number of hours in each period to get the total fuel consumed
		) * hours_in_period[p];

# the load in MW drawn from grid from storing electrons in new storage plants
var StoreEnergy {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t]} >= 0;
# number of MW to generate from each storage project, in each hour. 
var ReleaseEnergy {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t]} >= 0;

# amount of hydro to store and dispatch during each hour
# note: Store_Pumped_Hydro represents the load on the grid so the amount of energy available for release
# is Store_Pumped_Hydro * storage_efficiency[t]
var DispatchHydro {HYDRO_AVAILABLE_HOURS} >= 0;
var Dispatch_Pumped_Hydro_Storage {PUMPED_HYDRO_AVAILABLE_HOURS} >= 0;
var Store_Pumped_Hydro {PUMPED_HYDRO_AVAILABLE_HOURS} >= 0;


# Operating reserve variables

# Operating reserve requirement in each balancing area by period, divided into a spining reserve component and a quickstart component
# The WECC standard on operating reserves is the
#"Regional Reliability Standard to address the Operating Reserve requirements of the Western Interconnection."
# It prescribes that "[t]he sum of five percent of the load responsibility served by hydro generation and seven percent of the load responsibility served by thermal generation" be covered by contingency reserves, and that at least half of that be spinning
# we assume that the quickstart requirement is a multiple of the spinning reserve requirement at a 1 to 1 ratio)
# The spinning reserve requirement level depends on load level, wind generation level, and solar generation level
# For now, we apply a conservative esitmate of the reserve requirement: the 3-5 rule from WWSIS, i.e. 3 percent load and 5 percent of wind is kept as spinning reserves in all hours
# We also assume that solar generation, with the exception of CSP with 6 hours of storage, which exhibits little 10-min variability, impose reserve requirements similar to wind's (i.e. 5 percent of generation). Solar CSP without storage contributes only to the quickstart requirement
var Spinning_Reserve_Requirement { b in BALANCING_AREAS, h in TIMEPOINTS } >= 0;
var Quickstart_Reserve_Requirement { b in BALANCING_AREAS, h in TIMEPOINTS } >= 0;

# Spinning reserve and quickstart capacity can be provided by dispatchable generators, hydro, and storage
# Because hydro and storage are assumed to be able to ramp up to full capacity very quickly, the operating reserve provided by them is not divided into
# a spinning and quickstart component (all of their operating reserve can count as spinning)

var Provide_Spinning_Reserve { (pid, a, t, p, h) in AVAILABLE_HOURS: dispatchable[t] } >= 0;
var Provide_Quickstart_Capacity { (pid, a, t, p, h) in AVAILABLE_HOURS: dispatchable[t] } >= 0;
var Storage_Operating_Reserve { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t] } >= 0;
var Hydro_Operating_Reserve { (a, t, p, h) in HYDRO_AVAILABLE_HOURS} >= 0;
var Pumped_Hydro_Storage_Operating_Reserve { (a, t, p, h) in PUMPED_HYDRO_AVAILABLE_HOURS } >= 0;


############ Fuel consumption ###############

set NG_SUPPLY_CURVE_PERIOD_BREAKPOINTS dimen 2;
set NG_REGIONAL_PRICE_ADDERS_PERIODS dimen 2;

# natural gas supply curve parameters; the surplus-adjusted price and regional price adder are in $/MMBtu; the natural gas consumption is in MMBtu
param num_ng_breakpoints { p in PERIODS_AND_PRESENT} = card ( { (p, bp) in NG_SUPPLY_CURVE_PERIOD_BREAKPOINTS } );
param ng_price_surplus_adjusted { (p, bp) in NG_SUPPLY_CURVE_PERIOD_BREAKPOINTS } >= if bp = 1 then 0 else ng_price_surplus_adjusted[p, bp-1];
param ng_consumption_breakpoint { p in PERIODS_AND_PRESENT, bp in 1..(num_ng_breakpoints[p]-1) } > if bp = 1 then 0 else ng_consumption_breakpoint[p, bp-1];
param ng_consumption_breakpoint_per_period {p in PERIODS, bp in 1..num_ng_breakpoints[p]-1}
	= ng_consumption_breakpoint[p, bp] * num_years_per_period;
param ng_regional_price_adder { (nr, p) in NG_REGIONAL_PRICE_ADDERS_PERIODS }; 


# Derived variable for total fuel consumption by NEMS fuel region
# Region-specific fuel consumption (used to calculate additional cost to reflect variations in wellhead prices and/or transportation costs across regions)
var ConsumeNaturalGasRegional { (nr, p) in NG_REGIONAL_PRICE_ADDERS_PERIODS } =
  # New plants
	( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: nems_fuel_region[a] = nr and ( fuel[t] = 'Gas' or fuel[t] = 'Gas_CCS' ) } 
	  ( if t = 'Compressed_Air_Energy_Storage' then ( 1 + caes_storage_to_ng_ratio[t] ) else 1 )
	  * ( if dispatchable[t] then DispatchGen[pid, a, t, p, h] 
	      else if baseload[t] then ( Installed_To_Date[pid, a, t, p] * gen_availability[t] )
	             else 0 
	       ) * heat_rate[pid, a, t] * hours_in_sample[h] )
  # Existing plants
	+ ( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: nems_fuel_region[a] = nr and ( fuel[t] = 'Gas' or fuel[t] = 'Gas_CCS' ) } 
	    ProducePowerEP[pid, a, t, p, h] * ep_heat_rate[pid, a, t] * hours_in_sample[h] )
 # Spinning reserves: fuel use for providing spinning reserves from new and existing plants
    + ( sum {(pid, a, t, p, h) in AVAILABLE_HOURS: nems_fuel_region[a] = nr and dispatchable[t] and ( fuel[t] = 'Gas' or fuel[t] = 'Gas_CCS' ) } 	  
      ( if t = 'Compressed_Air_Energy_Storage' then ( 1 + caes_storage_to_ng_ratio[t] ) else 1 )
      * Provide_Spinning_Reserve[pid, a, t, p, h] *  heat_rate_spinning_reserve[pid, a, t] * hours_in_sample[h] )
 # fuel use for keeping CCGT plants below full load (beyond spinning reserves; if DispatchGen + Provide_Spinning_Reserve = Commit_Intermediate_Gen, no additional cost is incurred as the cost for keeping spinning_reserves is already taken into account above )
	 + ( sum { (pid, a, t, p, h) in AVAILABLE_HOURS: nems_fuel_region[a] = nr and ( t in INTERMEDIATE_TECHNOLOGIES ) and ( fuel[t] = 'Gas' or fuel[t] = 'Gas_CCS' ) } (
	 	( Commit_Intermediate_Gen[pid, a, t, p, h] - ( ( if can_build_new[t] then DispatchGen[pid, a, t, p, h] else ProducePowerEP[pid, a, t, p, h] ) + Provide_Spinning_Reserve[pid, a, t, p, h] ) )
	 	* deep_cycling_penalty[t] * ( if can_build_new[t] then heat_rate[pid, a, t] else ep_heat_rate[pid, a, t] ) * hours_in_sample[h] )
	 	)
  # fuel use for starting up intermediate and peaker plants
	+ ( sum { (pid, a, t, p, h) in AVAILABLE_HOURS: nems_fuel_region[a] = nr and ( t in PEAKER_TECHNOLOGIES or t in INTERMEDIATE_TECHNOLOGIES ) and ( fuel[t] = 'Gas' or fuel[t] = 'Gas_CCS' ) } (
	    Startup_MW_from_Last_Hour[pid, a, t, p, h] * startup_mmbtu_per_mw[t] * hours_in_sample[h] ) 
	    )
  ;

var ConsumeNaturalGas {p in PERIODS} = 
  sum { nr in NEMS_FUEL_REGIONS } ConsumeNaturalGasRegional [nr, p];

#### OBJECTIVE ####

# minimize the total cost of power over all study periods and hours, including carbon tax
# pid = project specific id
# a = load area
# t = technology
# p = PERIODS, the start of an investment period as well as the date when a power plant starts running.
# h = study hour - unique timepoint considered
# p = investment period

minimize Power_Cost:

	#############################
	#    NEW PLANTS
	# Capital costs and fixed costs
      ( sum { (pid, a, t, p) in PROJECT_VINTAGES } 
        InstallGen[pid, a, t, p] * ( capital_cost[pid, a, t, p] + fixed_o_m_discounted[pid, a, t, p] ) )
	# Variable, fuel, and carbon costs for intermittent and baseload generators
	# Bio_solid fuel cost isn't included here - it's in the bio supply curve
    + ( sum { (pid, a, t, p) in PROJECT_VINTAGES: intermittent[t] or baseload[t] } 
        InstallGen[pid, a, t, p] * variable_cost[pid, a, t, p] )
	# BioSolid fuel costs - ConsumeBioSolid is the MMbtu of biomass consumed per period per load area
	# this is annualized because costs in the objective function are annualized for proper discounting
	+ ( sum { a in LOAD_AREAS, p in PERIODS: num_bio_breakpoints[a, p] > 0 } 
		<< { bp in 1..num_bio_breakpoints[a, p] - 1 } breakpoint_mmbtu_per_period[a, p, bp]; 
		   { bp in 1..num_bio_breakpoints[a, p] } price_dollars_per_mmbtu_surplus_adjusted[a, p, bp] >>
	   		ConsumeBioSolid[a, p] * ( 1 / num_years_per_period ) * discount_to_base_year[p]  )
	# Natural gas fuel costs
   		# WECC-wide supply curves
   + ( sum { p in PERIODS } 
		<< { bp in 1..num_ng_breakpoints[p] - 1  } ng_consumption_breakpoint_per_period[p, bp]; 
		   { bp in 1..num_ng_breakpoints[p]} ng_price_surplus_adjusted[p, bp] >>
	   		ConsumeNaturalGas[p] * ( 1 / num_years_per_period ) * discount_to_base_year[p]  )
   		# Regional adder NG fuel costs
   	+ ( sum { nr in NEMS_FUEL_REGIONS, p in PERIODS } 
     ConsumeNaturalGasRegional[nr, p] * ng_regional_price_adder[nr, p] * ( 1 / num_years_per_period ) * discount_to_base_year[p] )
    # Variable costs for dispatchable, non-storage projects
    # fuel_cost_hourly is 0 for bio solid and natural gas plants (fuel costs are calculated via the supply curves instead), so NG and bio solid fuel costs are not double counted here
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t] and t <> 'Compressed_Air_Energy_Storage' } 
		DispatchGen[pid, a, t, p, h] * ( variable_o_m_cost_hourly[pid, a, t, p, h] + carbon_cost_per_mwh_hourly[pid, a, t, p, h] + fuel_cost_hourly[pid, a, t, p, h] ) )
	# Variable costs for new flexible baseload projects
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: flexible_baseload[t] } 
		DispatchFlexibleBaseload[pid, a, t, p, date[h]] * ( variable_o_m_cost_hourly[pid, a, t, p, h] + carbon_cost_per_mwh_hourly[pid, a, t, p, h] + fuel_cost_hourly[pid, a, t, p, h] ) )
	# Variable costs for storage projects: currently attributed to the dispatch side of storage
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t] and t <> 'Compressed_Air_Energy_Storage' } 
		ReleaseEnergy[pid, a, t, p, h] * variable_o_m_cost_hourly[pid, a, t, p, h])
	# for CAES, power output is apportioned between DispatchGen and ReleaseEnergy by caes_storage_to_ng_ratio through the constraint CAES_Combined_Dispatch
	# the sum of DispatchGen and ReleaseEnergy simplifies to DispatchGen * ( 1 + caes_storage_to_ng_ratio )
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: t = 'Compressed_Air_Energy_Storage' } 
	  DispatchGen[pid, a, t, p, h] * ( 1 + caes_storage_to_ng_ratio[t] ) * ( variable_o_m_cost_hourly[pid, a, t, p, h] + carbon_cost_per_mwh_hourly[pid, a, t, p, h] + fuel_cost_hourly[pid, a, t, p, h] ) )
	# fuel and carbon costs for keeping spinning reserves from new dispatchable plants (oil and gas except for CAES)
	# for natural gas plants, fuel costs for spinning reserves are handled via the NG supply curve so for NG, fuel_cost_hourly_spinning_reserve = 0; however, fuels cost are calculated here for oil plants
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t] and t <> 'Compressed_Air_Energy_Storage' } 
		Provide_Spinning_Reserve[pid, a, t, p, h] * ( carbon_cost_per_mwh_hourly_spinning_reserve[pid, a, t, p, h] + fuel_cost_hourly_spinning_reserve[pid, a, t, p, h] ) )
	# fuel and carbon costs for keeping spinning reserves from CAES
	# the sum of spinning reserve provided by the natural gas and storage parts of CAES simplifies to
	# Provide_Spinning_Reserve * ( 1 + caes_storage_to_ng_ratio )
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: t = 'Compressed_Air_Energy_Storage' } 
		Provide_Spinning_Reserve[pid, a, t, p, h] * ( 1 + caes_storage_to_ng_ratio[t] ) * ( carbon_cost_per_mwh_hourly_spinning_reserve[pid, a, t, p, h] + fuel_cost_hourly_spinning_reserve[pid, a, t, p, h] ) )
	# cost incurred for keeping new flexible baseload plants below full load
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: flexible_baseload[t] } (
	    Deep_Cycle_Amount[pid, a, t, p, date[h]]
	    * deep_cycling_penalty[t] * ( carbon_cost_per_mwh_hourly[pid, a, t, p, h] + fuel_cost_hourly[pid, a, t, p, h] ) )
	    )
	# carbon cost incurred for keeping new intermediate plants below full load (fuel costs are handled via the NG supply curve)
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: t in INTERMEDIATE_TECHNOLOGIES } (
	    ( Commit_Intermediate_Gen[pid, a, t, p, h] - ( DispatchGen[pid, a, t, p, h] + Provide_Spinning_Reserve[pid, a, t, p, h] ) ) * deep_cycling_penalty[t] * carbon_cost_per_mwh_hourly[pid, a, t, p, h] )
		)
	# costs for starting up intermediate and peaker plants (fuel costs are included here for oil generators only; for gas, they are handled via the natural gas supply curve so startup_fuel_cost_per_mw_hourly is 0 )
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: t in PEAKER_TECHNOLOGIES or t in INTERMEDIATE_TECHNOLOGIES } (
	    Startup_MW_from_Last_Hour[pid, a, t, p, h] * ( startup_fuel_cost_per_mw_hourly[pid, a, t, p, h] + startup_nonfuel_cost_per_mw_hourly[pid, a, t, p, h] + startup_carbon_cost_per_mw_hourly[pid, a, t, p, h] ) ) 
	    )
		      
	#############################
	#    EXISTING PLANTS
	# Capital costs (sunk cost)
	+ ( sum {(pid, a, t, p) in EP_PERIODS: not ep_could_be_operating_past_expected_lifetime[pid, a, t, p]}
		ep_capacity_mw[pid, a, t] * ep_capital_cost[pid, a, t, p] )
	# Calculate fixed costs for all existing plants
	+ ( sum {(pid, a, t, p) in EP_PERIODS} 
		( if ( intermittent[t] or hydro[t] ) then 1 else OperateEPDuringPeriod[pid, a, t, p] ) * ep_capacity_mw[pid, a, t] * ep_fixed_o_m_by_period[pid, a, t, p] )
	# Calculate variable, fuel, and carbon costs for all existing plants
	# Bio_solid fuel cost isn't included here - it's in the bio supply curve
	+ ( sum {(pid, a, t, p, h) in EP_AVAILABLE_HOURS}
		ProducePowerEP[pid, a, t, p, h] * ( variable_o_m_cost_hourly[pid, a, t, p, h] + fuel_cost_hourly[pid, a, t, p, h] + carbon_cost_per_mwh_hourly[pid, a, t, p, h] ) )
	# variable costs for releasing energy from pumped hydro storage - currently zero because the variable O&M value is zero
	# decision variables are on the load area level - this shares them out by plant (pid) in case plants have different variable costs within a load area
	+ ( sum {(pid, a, t, p, h) in PUMPED_HYDRO_AVAILABLE_HOURS_BY_PID}
		Dispatch_Pumped_Hydro_Storage[a, t, p, h] * ( ep_capacity_mw[pid, a, t] / hydro_capacity_mw_in_load_area[a, t] ) * variable_o_m_cost_hourly[pid, a, t, p, h] )
	# carbon costs for keeping spinning reserves from existing dispatchable thermal plants (fuel costs for NG generators are handled via the NG supply curve, but is included in fuel_cost_hourly_spinning_reserve for oil plants)
	+ ( sum {(pid, a, t, p, h) in EP_AVAILABLE_HOURS: dispatchable[t] }
		Provide_Spinning_Reserve[pid, a, t, p, h] * ( fuel_cost_hourly_spinning_reserve[pid, a, t, p, h] + carbon_cost_per_mwh_hourly_spinning_reserve[pid, a, t, p, h] ) )
	+ ( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: flexible_baseload[t] }
	    Deep_Cycle_Amount[pid, a, t, p, date[h]]
	    * deep_cycling_penalty[t] * ( carbon_cost_per_mwh_hourly[pid, a, t, p, h] + fuel_cost_hourly[pid, a, t, p, h] ) )
	# carbon cost incurred for keeping existing intermediate plants below full load (fuel costs are handled via the NG supply curve)
	+ ( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: t in INTERMEDIATE_TECHNOLOGIES } (
	    ( Commit_Intermediate_Gen[pid, a, t, p, h] - ( ProducePowerEP[pid, a, t, p, h] + Provide_Spinning_Reserve[pid, a, t, p, h] ) ) * deep_cycling_penalty[t] * carbon_cost_per_mwh_hourly[pid, a, t, p, h] )
		)
	# costs for starting up existing intermediate and peaker plants (fuel costs are included here for oil generators only; for gas, they are handled via the natural gas supply curve and startup_fuel_cost_per_mw_hourly is 0
	+ ( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: t in PEAKER_TECHNOLOGIES or t in INTERMEDIATE_TECHNOLOGIES } (
	    Startup_MW_from_Last_Hour[pid, a, t, p, h] * ( startup_fuel_cost_per_mw_hourly[pid, a, t, p, h] + startup_nonfuel_cost_per_mw_hourly[pid, a, t, p, h] + startup_carbon_cost_per_mw_hourly[pid, a, t, p, h] ) ) 
	    )
	    
	########################################
	#    TRANSMISSION & DISTRIBUTION
	# Sunk costs of operating the existing transmission grid
	+ ( sum {a in LOAD_AREAS, p in PERIODS}
		transmission_sunk_annual_payment[a] * discount_to_base_year[p] )
	# Calculate the cost of installing new transmission lines between load areas
	+ ( sum { (a1, a2, p) in TRANSMISSION_LINE_NEW_PERIODS } 
		InstallTrans[a1, a2, p] * transmission_cost_per_mw[a1, a2, p] )
	+ ( sum { (a1, a2, p) in TRANSMISSION_LINE_NEW_PERIODS } 
		InstallTrans[a1, a2, p] * transmission_fixed_o_m_by_period[a1, a2, p] )
	# Calculate the cost of installing new local (intra-load area) transmission and distribution
	+ ( sum {a in LOAD_AREAS, p in PERIODS}
		install_local_td[a, p] * local_td_cost_per_mw[a, p] )
	# Sunk costs of operating the existing local (intra-load area) transmission and distribution
	+ ( sum {a in LOAD_AREAS, p in PERIODS} local_td_sunk_annual_payment[a] * discount_to_base_year[p] )
;

############## CONSTRAINTS ##############

###### Policy Constraints #######

# RPS constraint
# load.run will drop this constraint if enable_rps is 0
subject to Satisfy_Primary_RPS { (r, c, p) in RPS_TARGETS: c = 'Primary' }:
	# primary RPS is an RPS target without generator-specific requirements
	# this RPS can be met with any qualifying distributed or non-distributed power
  	( sum { h in TIMEPOINTS: period[h] = p } ConsumeREC[r, h] * hours_in_sample[h] )
      >= rps_compliance_fraction_in_period[r, c, p]
      		* ( sum { a in LOAD_AREAS, h in TIMEPOINTS: rps_compliance_entity[a] = r and period[h] = p } 
      		  system_load[a, h] * hours_in_sample[h] );


subject to Satisfy_Distributed_RPS { (r, c, p) in RPS_TARGETS: c = 'Distributed' and able_to_meet_rps[r, c, p] }:
	# distributed RPS is an RPS target that must be met by distributed power, modeled in SWITCH currently as distributed PV
      ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: rps_compliance_entity[a] = r and t in SOLAR_DIST_PV_TECHNOLOGIES and tech_qualifies_for_rps[t] }
          Installed_To_Date[pid, a, t, p] * cap_factor[pid, a, t, h] * gen_availability[t] * hours_in_sample[h] )
	+ ( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: rps_compliance_entity[a] = r and t in SOLAR_DIST_PV_TECHNOLOGIES and tech_qualifies_for_rps[t] }
   	      ep_capacity_mw[pid, a, t] * gen_availability[t] * eip_cap_factor[pid, a, t, h] * hours_in_sample[h] ) 
      >= rps_compliance_fraction_in_period[r, c, p]
      		* ( sum { a in LOAD_AREAS, h in TIMEPOINTS: rps_compliance_entity[a] = r and period[h] = p } 
      		  system_load[a, h] * hours_in_sample[h] );

# the California Solar Initiative has the goal (and funding to back the goal)
# of bringing on 3000 MW of distributed solar by 2016 in California (http://www.cpuc.ca.gov/PUC/energy/Solar/aboutsolar.htm)
subject to Meet_California_Solar_Initiative { p in PERIODS: p >= 2016 }:
  sum { (pid, a, t, p) in PROJECT_VINTAGES: t in SOLAR_DIST_PV_TECHNOLOGIES and primary_state[a] = 'CA' }
     Installed_To_Date[pid, a, t, p]
     >= 3000;

# Carbon Cap constraint
# load.run will drop this constraint if enable_carbon_cap is 0
subject to Carbon_Cap {p in PERIODS}:
	# Carbon emissions from new dispatchable plants except for CAES - none from intermittent plants
	  ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t] and t <> 'Compressed_Air_Energy_Storage' } (
	  DispatchGen[pid, a, t, p, h] * heat_rate[pid, a, t]
	  + Provide_Spinning_Reserve[pid, a, t, p, h] * heat_rate_spinning_reserve[pid, a, t] )
	  * carbon_content[fuel[t]] * hours_in_sample[h] )
	# Carbon emissions from CAES; the total power from CAES is DispatchGen + ReleaseEnergy, which simplifes to 
	# DispatchGen * ( 1 + caes_storage_to_ng_ratio ), and the total spinning reserve simplifies to
	# ProvideSpinningReserve * ( 1 + caes_storage_to_ng_ratio )
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: t = 'Compressed_Air_Energy_Storage' } (
	  DispatchGen[pid, a, t, p, h] * ( 1 + caes_storage_to_ng_ratio[t] ) * heat_rate[pid, a, t]
	  + Provide_Spinning_Reserve[pid, a, t, p, h] * ( 1 + caes_storage_to_ng_ratio[t] ) * heat_rate_spinning_reserve[pid, a, t] )
	  * carbon_content[fuel[t]] * hours_in_sample[h] )
	# Carbon emissions from new baseload plants
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: baseload[t]}
		Installed_To_Date[pid, a, t, p] * gen_availability[t] * heat_rate[pid, a, t] * carbon_content[fuel[t]] * hours_in_sample[h] )
	# Carbon emissions from new flexible baseload plants
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: flexible_baseload[t] } (
	   DispatchFlexibleBaseload[pid, a, t, p, date[h]] * heat_rate[pid, a, t] * carbon_content[fuel[t]] * hours_in_sample[h] ) )
	# Carbon emissions from existing plants
	+ ( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS } (
	ProducePowerEP[pid, a, t, p, h] * ep_heat_rate[pid, a, t]
	+ ( ( if dispatchable[t] then Provide_Spinning_Reserve[pid, a, t, p, h] else 0 ) * heat_rate_spinning_reserve[pid, a, t] )
	) * carbon_content[fuel[t]] * hours_in_sample[h] )
	# Carbon emissions from heat rate degradation of flexible baseload plants operating below full load
	+ ( sum { (pid, a, t, p, h) in AVAILABLE_HOURS: flexible_baseload[t] } (
	    Deep_Cycle_Amount[pid, a, t, p, date[h]] * deep_cycling_penalty[t] 
	    * ( if can_build_new[t] then heat_rate[pid, a, t] else ep_heat_rate[pid, a, t] )
	    * carbon_content[fuel[t]] * hours_in_sample[h] )
	    )
	# carbon emissions from keeping intermediate plants below full load
	 + ( sum { (pid, a, t, p, h) in AVAILABLE_HOURS: t in INTERMEDIATE_TECHNOLOGIES } (
	 	( Commit_Intermediate_Gen[pid, a, t, p, h] - ( ( if can_build_new[t] then DispatchGen[pid, a, t, p, h] else ProducePowerEP[pid, a, t, p, h] ) + Provide_Spinning_Reserve[pid, a, t, p, h] ) )
	 	* deep_cycling_penalty[t] * ( if can_build_new[t] then heat_rate[pid, a, t] else ep_heat_rate[pid, a, t] ) * carbon_content[fuel[t]] * hours_in_sample[h] )
	 	)
	 # emissions from starting up new and existing intermediate plants and peaker plants
	+ ( sum { (pid, a, t, p, h) in AVAILABLE_HOURS: t in PEAKER_TECHNOLOGIES or t in INTERMEDIATE_TECHNOLOGIES } (
	    Startup_MW_from_Last_Hour[pid, a, t, p, h] * startup_mmbtu_per_mw[t] 
	    * carbon_content[fuel[t]] * hours_in_sample[h] )
	    )
  	<= carbon_cap[p];


#################################################
# Power conservation constraints

# System needs to meet the load in each load area in each study hour, with all available flows of power.
subject to Satisfy_Load {a in LOAD_AREAS, h in TIMEPOINTS}:
	  ConsumeNonDistributedPower[a, h]
	# distributed power production doesn't experience distribution losses and must be consumed immediately on site or spilled
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: t in SOLAR_DIST_PV_TECHNOLOGIES }
          Installed_To_Date[pid, a, t, p] * cap_factor[pid, a, t, h] * gen_availability[t])
	+ ( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: t in SOLAR_DIST_PV_TECHNOLOGIES }
   	      ep_capacity_mw[pid, a, t] * gen_availability[t] * eip_cap_factor[pid, a, t, h] ) 
	>= system_load[a, h] ;

# non-distributed power production experiences distribution losses when consumed
# but it can also be stored, transmitted, or spilled (hence the <=).
subject to Conservation_Of_Energy_NonDistributed {a in LOAD_AREAS, h in TIMEPOINTS}:
  ConsumeNonDistributedPower[a, h] * (1 + distribution_losses)
  <= 
  (
	# power produced from new non-battery-storage projects  
	  ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t] } DispatchGen[pid, a, t, p, h] )
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: flexible_baseload[t] } DispatchFlexibleBaseload[pid, a, t, p, date[h]] )
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: intermittent[t] and t not in SOLAR_DIST_PV_TECHNOLOGIES }
		Installed_To_Date[pid, a, t, p] * cap_factor[pid, a, t, h] * gen_availability[t] )
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: baseload[t] }
		Installed_To_Date[pid, a, t, p] * gen_availability[t] )
	# power from new storage
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t]} ( ReleaseEnergy[pid, a, t, p, h] - StoreEnergy[pid, a, t, p, h] ) )
	# power produced from existing plants
	+ ( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: t not in SOLAR_DIST_PV_TECHNOLOGIES} ProducePowerEP[pid, a, t, p, h] )
	# power from existing (pumped hydro) storage
 	+ ( sum { (a, t, p, h) in PUMPED_HYDRO_AVAILABLE_HOURS} ( Dispatch_Pumped_Hydro_Storage[a, t, p, h] - Store_Pumped_Hydro[a, t, p, h] ) )
	# transmission in and out of each load area
	+ ( sum { (a2, a, fc, p, h) in TRANSMISSION_LINE_HOURS } DispatchTrans[a2, a, fc, p, h] * transmission_efficiency[a2, a] )
	- ( sum { (a, a1, fc, p, h) in TRANSMISSION_LINE_HOURS } DispatchTrans[a, a1, fc, p, h] )
  	);

# make sure that we're only consuming generated or transmitted RECs
# RECs don't undergo transmission or storage losses by defintion,
# so DispatchTrans isn't derated for losses in this constraint (it is above when carries actual energy)
# Transmitted RECs are denoted here by having a fuel category of fc = 'renewable'
subject to Conservation_of_REC {r in RPS_AREAS, h in TIMEPOINTS}:
	ConsumeREC[r, h]
	<=
	# Generated RECs
	  ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t] and rps_compliance_entity[a] = r and tech_qualifies_for_rps[t] }
	  	DispatchGen[pid, a, t, p, h] )
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: flexible_baseload[t] and rps_compliance_entity[a] = r and tech_qualifies_for_rps[t] }
		DispatchFlexibleBaseload[pid, a, t, p, date[h]] )
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: intermittent[t] and rps_compliance_entity[a] = r and tech_qualifies_for_rps[t] }
		Installed_To_Date[pid, a, t, p] * cap_factor[pid, a, t, h] * gen_availability[t] )
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: baseload[t] and rps_compliance_entity[a] = r and tech_qualifies_for_rps[t] }
		Installed_To_Date[pid, a, t, p] * gen_availability[t] )
	+ ( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: rps_compliance_entity[a] = r and tech_qualifies_for_rps[t] }
		ProducePowerEP[pid, a, t, p, h] )
	# transmission of RECs in and out of an RPS area
	+ ( sum { (a2, a, fc, p, h) in TRANSMISSION_LINE_HOURS: rps_compliance_entity[a] = r and fc = 'renewable' }
		DispatchTrans[a2, a, fc, p, h] )
	- ( sum { (a, a1, fc, p, h) in TRANSMISSION_LINE_HOURS: rps_compliance_entity[a] = r and fc = 'renewable' }
		DispatchTrans[a, a1, fc, p, h] )
	;


################################################################################
# same on a reserve basis
# note: these are not derated by forced outage rate, because that is incorporated in the reserve margin
subject to Satisfy_Load_Reserve {a in LOAD_AREAS, h in TIMEPOINTS}:
	ConsumeNonDistributedPower_Reserve[a,h] + 
	  ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: t in SOLAR_DIST_PV_TECHNOLOGIES}
          Installed_To_Date[pid, a, t, p] * cap_factor[pid, a, t, h] )
	+ ( sum {(pid, a, t, p, h) in EP_AVAILABLE_HOURS: t in SOLAR_DIST_PV_TECHNOLOGIES}
   	      eip_cap_factor[pid, a, t, h] * ep_capacity_mw[pid, a, t] ) 
	>=
	( 1 + planning_reserve_margin ) * system_load[a, h]
	;


subject to Conservation_Of_Energy_NonDistributed_Reserve {a in LOAD_AREAS, h in TIMEPOINTS}:
  ( ConsumeNonDistributedPower_Reserve[a,h] * (1 + distribution_losses) )
  <= 
  (
	#    NEW PLANTS
  # new dispatchable capacity (no need to decide how to dispatch it; we just need to know it's available)
	  ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t] and not storage[t]}
		Installed_To_Date[pid, a, t, p] )
  # output from new intermittent projects. 
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: intermittent[t] and t not in SOLAR_DIST_PV_TECHNOLOGIES} 
		Installed_To_Date[pid, a, t, p] * cap_factor[pid, a, t, h] )
  # new baseload plants
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: baseload[t] or flexible_baseload[t] } 
		Installed_To_Date[pid, a, t, p] * ( 1 - scheduled_outage_rate[t] ) )
  # new storage projects
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t]}
		( ReleaseEnergy[pid, a, t, p, h] - StoreEnergy[pid, a, t, p, h] ) )
	#############################
	#    EXISTING PLANTS
  # existing dispatchable capacity
	+ ( sum {(pid, a, t, p, h) in EP_AVAILABLE_HOURS: dispatchable[t]}
		OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] )
  # existing intermittent plants
	+ ( sum {(pid, a, t, p, h) in EP_AVAILABLE_HOURS: intermittent[t] and t not in SOLAR_DIST_PV_TECHNOLOGIES} 
		eip_cap_factor[pid, a, t, h] * ep_capacity_mw[pid, a, t] )
  # existing baseload plants
	+ ( sum {(pid, a, t, p, h) in EP_AVAILABLE_HOURS: baseload[t] or flexible_baseload[t] } 
		OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] * ( 1 - scheduled_outage_rate[t] ) )
	#	HYDRO
  # non-storage hydro dispatch (includes pumped storage watershed electrons)
	+ ( sum {(a, t, p, h) in HYDRO_AVAILABLE_HOURS}
		DispatchHydro[a, t, p, h] )
  # pumped hydro storage and dispatch
	+ ( sum {(a, t, p, h) in PUMPED_HYDRO_AVAILABLE_HOURS} 
	( Dispatch_Pumped_Hydro_Storage[a, t, p, h] - Store_Pumped_Hydro[a, t, p, h] ) )
	########################################
	#    TRANSMISSION
  # the treatment of transmission is slightly different from that of generators
  # in that DispatchTrans is constrained to be less than the transmission capacity derated for outage rates
  # whereas the full capacity of generators (not de-rated) is allowed to contribute to the reserve margin
	# transmission in and out of each load area
	+ ( sum { (a2, a, fc, p, h) in TRANSMISSION_LINE_HOURS } DispatchTrans[a2, a, fc, p, h] * transmission_efficiency[a2, a] )
	- ( sum { (a, a1, fc, p, h) in TRANSMISSION_LINE_HOURS } DispatchTrans[a, a1, fc, p, h] )
	);


##########################################
# OPERATING RESERVE CONSTRAINTS

subject to Spinning_Reserve_Requirement_in_Balancing_Area_in_Hour {b in BALANCING_AREAS, h in TIMEPOINTS}: 
	Spinning_Reserve_Requirement[b, h]
	>= load_only_spinning_reserve_requirement[b]
	* (	sum {a in LOAD_AREAS: balancing_area[a] = b} system_load[a, h] )
	+ wind_spinning_reserve_requirement[b]
	* (
	# existing wind
	( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: balancing_area[a] = b and fuel[t] = 'Wind' } 
		eip_cap_factor[pid, a, t, h] * ep_capacity_mw[pid, a, t] )
	# new wind
	+ ( sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: balancing_area[a] = b and fuel[t] = 'Wind' } (
	Installed_To_Date[pid, a, t, p] * cap_factor[pid, a, t, h] ) )
	)
	+ solar_spinning_reserve_requirement[b] 
	* (
	# solar CSP with and without storage does not contribute to the spinning reserve requirement
	# existing solar
	( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: balancing_area[a] = b and fuel[t] = 'Solar' and t not in SOLAR_CSP_TECHNOLOGIES } 
		eip_cap_factor[pid, a, t, h] * ep_capacity_mw[pid, a, t] )
	# new solar
	+ (	sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: balancing_area[a] = b and fuel[t] = 'Solar' and t not in SOLAR_CSP_TECHNOLOGIES } (
	Installed_To_Date[pid, a, t, p] * cap_factor[pid, a, t, h] ) )
	);

subject to Quickstart_Reserve_Requirement_in_Balancing_Area_in_Hour {b in BALANCING_AREAS, h in TIMEPOINTS}:
	Quickstart_Reserve_Requirement[b, h] 
	>= quickstart_requirement_relative_to_spinning_reserve_requirement[b]
	* Spinning_Reserve_Requirement[b, h]
	# CSP trough with no storage contributes only to the quickstart requirement
	# CSP trough with storage doesn't contribute to either spinning or quickstart
	+ csp_quickstart_reserve_requirement[b] 
	* (
	# existing CSP
	( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: balancing_area[a] = b and t = 'CSP_Trough_No_Storage' } 
		eip_cap_factor[pid, a, t, h] * ep_capacity_mw[pid, a, t] )
	# new CSP
	+ (	sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: balancing_area[a] = b and t = 'CSP_Trough_No_Storage' } (
	Installed_To_Date[pid, a, t, p] * cap_factor[pid, a, t, h] ) )
	);

# Ensure that the spinning reserve requirement is met in each hour in each balancing area
subject to Satisfy_Spinning_Reserve_Requirement {b in BALANCING_AREAS, h in TIMEPOINTS}:
	Spinning_Reserve_Requirement[b, h]
	<=
    # new and existing dispatchable plants
    sum { (pid, a, t, p, h) in AVAILABLE_HOURS: dispatchable[t] and t <> 'Compressed_Air_Energy_Storage' and balancing_area[a] = b }
    Provide_Spinning_Reserve[pid, a, t, p, h]
   	# CAES storage; 
   	# because spinning reserve from the storage part of CAES is tied to the NG part, not all of the CAES storage operating reserve can count as spinning; we assume that if the CAES plant is providing spinning reserve, the ratio between the NG and the storage components will be the same as the NG:Stored dispatch 
	+ sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: t = 'Compressed_Air_Energy_Storage' and balancing_area[a] = b }
	( Provide_Spinning_Reserve[pid, a, t, p, h] * ( 1 + caes_storage_to_ng_ratio[t] ) )
    # non-CAES storage projects; this sum is over PROJECT_VINTAGE_HOURS so excludes existing pumped hydro storage, which is added separately
    + sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t] and t <> 'Compressed_Air_Energy_Storage' and balancing_area[a] = b }
    Storage_Operating_Reserve[pid, a, t, p, h]
    # hydro projects
    + sum { (a, t, p, h) in HYDRO_AVAILABLE_HOURS: balancing_area[a] = b } 
    Hydro_Operating_Reserve[a, t, p, h]
    # pumped hydro storage
    + sum { (a, t, p, h) in PUMPED_HYDRO_AVAILABLE_HOURS: balancing_area[a] = b }
    Pumped_Hydro_Storage_Operating_Reserve[a, t, p, h]
    ;

# Ensure that the quickstart reserve requirement is met in each hour in each balancing area in addition to the spinning reserve requirement
subject to Satisfy_Quickstart_Reserve_Requirement {b in BALANCING_AREAS, h in TIMEPOINTS}:
	Quickstart_Reserve_Requirement[b, h]
	<=
	# first add all operating reserve provided
    # new and existing dispatchable plants, including the NG part of CAES
    sum { (pid, a, t, p, h) in AVAILABLE_HOURS: dispatchable[t] and balancing_area[a] = b } 
    ( Provide_Spinning_Reserve[pid, a, t, p, h] + Provide_Quickstart_Capacity[pid, a, t, p, h] )
    # storage projects; this sum is over PROJECT_VINTAGE_HOURS so excludes existing pumped hydro storage, which is added separately
    + sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t] and balancing_area[a] = b } 
    Storage_Operating_Reserve[pid, a, t, p, h]
    # hydro projects
    + sum { (a, t, p, h) in HYDRO_AVAILABLE_HOURS: balancing_area[a] = b } 
    Hydro_Operating_Reserve[a, t, p, h]
    # pumped hydro storage
    + sum { (a, t, p, h) in PUMPED_HYDRO_AVAILABLE_HOURS: balancing_area[a] = b } Pumped_Hydro_Storage_Operating_Reserve[a, t, p, h]
    # Subtract whatever is being used for spinning reserves
    - Spinning_Reserve_Requirement[b, h]
    ;


################################################################################
# GENERATOR OPERATIONAL CONSTRAINTS

# system can only dispatch as much of each project as is EXPECTED to be available
# i.e., we only dispatch up to gen_availability[t], so the system will work on an expected-value basis
# the total amount of useful energy, spinning reserve, and quickstart capacity cannot exceed the turbine capacity in any given hour
subject to Power_and_Operating_Reserve_From_Dispatchable_Plants 
	{ (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t] and t <> 'Compressed_Air_Energy_Storage' }:
	DispatchGen[pid, a, t, p, h] + Provide_Spinning_Reserve[pid, a, t, p, h] + Provide_Quickstart_Capacity[pid, a, t, p, h] 
	<=
	Installed_To_Date[pid, a, t, p] * gen_availability[t]
;

# flexible baseload plants are dispatched on a daily basis, with output the same in each hour of that day
subject to Power_From_New_Flexible_Baseload_Plants 
	{ (pid, a, t, p, d) in PROJECT_AVAILABLE_DATES: flexible_baseload[t] }:
	DispatchFlexibleBaseload[pid, a, t, p, d]
	<=
	Installed_To_Date[pid, a, t, p]	* gen_availability[t]
;

# flexible baseload plants must produce at least a pre-specified fraction of their capacity each day/hour
subject to Minimum_Loading_New_Flexible_Baseload_Plants { (pid, a, t, p, d) in PROJECT_AVAILABLE_DATES: flexible_baseload[t] }:
	DispatchFlexibleBaseload[pid, a, t, p, d]
	  >= 
	minimum_loading[t] * Installed_To_Date[pid, a, t, p]
;

# intermediate plants; can't have more intermediate capacity online that the total capacity installed
subject to Maximum_Intermediate_Capacity_Online { (pid, a, t, p, h) in AVAILABLE_HOURS: t in INTERMEDIATE_TECHNOLOGIES }:
	Commit_Intermediate_Gen[pid, a, t, p, h]
	<= 
	( if can_build_new[t] then Installed_To_Date[pid, a, t, p] else OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] ) * gen_availability[t] ;

# CCGTs can't provide more energy and spinning reserves than the capacity of plants committed in that hour
subject to Maximum_Dispatch_Intermediate_Gen { (pid, a, t, p, h) in AVAILABLE_HOURS: t in INTERMEDIATE_TECHNOLOGIES }:
	( if can_build_new[t] then DispatchGen[pid, a, t, p, h] else ProducePowerEP[pid, a, t, p, h] ) + Provide_Spinning_Reserve[pid, a, t, p, h]
	<= Commit_Intermediate_Gen[pid, a, t, p, h];

# Minimum loading for intermediate generation
subject to Minimum_Loading_Intermediate_Gen { (pid, a, t, p, h) in AVAILABLE_HOURS: t in INTERMEDIATE_TECHNOLOGIES }:
	( if can_build_new[t] then DispatchGen[pid, a, t, p, h] else ProducePowerEP[pid, a, t, p, h] ) 
	>= minimum_loading[t] * Commit_Intermediate_Gen[pid, a, t, p, h] ;

# Intermediate generation started up (new and existing)
# this constraint ensures that the variable Startup_MW_from_Last_Hour equals the difference between
# the power dispatched in the current hour minus the power dispatched in the previous hour
# Startup_MW_from_Last_Hour also has to be non-negative by definition
# so this constraint is not binding when ramping down (i.e. when the difference is negative)
# The implementation is cyclical over the course of a day: the previous timepoint for the first timepoint of each date is assumed to be the last timepoint of that date
subject to Intermediate_Gen_Startup { (pid, a, t, p, h) in AVAILABLE_HOURS: t in INTERMEDIATE_TECHNOLOGIES }:
  Startup_MW_from_Last_Hour[pid, a, t, p, h] >= Commit_Intermediate_Gen[pid, a, t, p, h] - Commit_Intermediate_Gen[pid, a, t, p, previous_timepoint[h]] ;

# Peaker plant startup
subject to Peaker_Plant_Startup { (pid, a, t, p, h) in AVAILABLE_HOURS: t in PEAKER_TECHNOLOGIES }: 
	Startup_MW_from_Last_Hour[pid, a, t, p, h] 
	>= if can_build_new[t] 
	   then ( DispatchGen[pid, a, t, p, h] - DispatchGen[pid, a, t, p, previous_timepoint[h]] )
	   else ( ProducePowerEP[pid, a, t, p, h] - ProducePowerEP[pid, a, t, p, previous_timepoint[h]] );
 
subject to EP_Operational_Continuity {(pid, a, t, p) in EP_PERIODS: p > first(PERIODS) and not intermittent[t] and not hydro[t]}:
	OperateEPDuringPeriod[pid, a, t, p] <= OperateEPDuringPeriod[pid, a, t, prev(p, PERIODS)];

# existing dispatchable plants can only be used if they are operational this period
# the total amount of useful energy, spinning reserve, and quickstart capacity cannot exceed the turbine capacity in any given hour
subject to EP_Power_and_Operating_Reserve_From_Dispatchable_Plants { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: dispatchable[t] }:
	ProducePowerEP[pid, a, t, p, h] 
	+ Provide_Spinning_Reserve[pid, a, t, p, h] + Provide_Quickstart_Capacity[pid, a, t, p, h] 
	<= 
	OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] * gen_availability[t];

# existing intermittent plants are kept operational until their end of life, with no option to extend life
subject to EP_Power_From_Intermittent_Plants { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: intermittent[t] }: 
	ProducePowerEP[pid, a, t, p, h] = ep_capacity_mw[pid, a, t] * eip_cap_factor[pid, a, t, h] * gen_availability[t];

# existing baseload plants are operational if OperateEPDuringPeriod is 1.
subject to EP_Power_From_Baseload_Plants { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: baseload[t] }: 
    ProducePowerEP[pid, a, t, p, h] = OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] * gen_availability[t];

# existing flexible baseload plants produce am amount equal DispatchFlexibleBaseload, which is constrained below
subject to EP_Power_From_Flexible_Baseload_Plants { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: flexible_baseload[t] }: 
    ProducePowerEP[pid, a, t, p, h] = DispatchFlexibleBaseload[pid, a, t, p, date[h]];

subject to Maximum_Loading_Existing_Flexible_Baseload_Plants { (pid, a, t, p, d) in EP_AVAILABLE_DATES: flexible_baseload[t] }: 
    DispatchFlexibleBaseload[pid, a, t, p, d] 
    <=  OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] * gen_availability[t];

subject to Minimum_Loading_Existing_Flexible_Baseload_Plants { (pid, a, t, p, d) in EP_AVAILABLE_DATES: flexible_baseload[t] }:
	DispatchFlexibleBaseload[pid, a, t, p, d]
	>= minimum_loading[t] * OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t]
;

# hydro dispatch is done on a load area basis, but it's helpful to have plant level decision variables
# so the load area variables are apportioned to each plant by capacity (this assumes that each plant operates similarly)
# DispatchHydro is derated by gen_availability[t] in the hydro constraints below
subject to EP_Power_From_Hydro_Plants { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: hydro[t] }: 
	ProducePowerEP[pid, a, t, p, h] = DispatchHydro[a, t, p, h] * ( ep_capacity_mw[pid, a, t] / hydro_capacity_mw_in_load_area[a, t] );
	
	
# Max capacity that can be dedicated to spinning reserves
# Spinning reserve is constrained to dispatch to ensure that spinning reserve is provided only when the plant is also providing useful energy
# Not enforced for storage and hydro plants as it is assumed that they can ramp up very quickly to full capacity
# For new CCGTs, the maximum spinning reserve is constrained by the total capacity that is online rather than DispatchGen because the plant may be operating below full load, i.e. Dispatch+Spinning can be less than online capacity
subject to Spinning_Reserve_as_Fraction_of_Dispatch { (pid, a, t, p, h) in AVAILABLE_HOURS: dispatchable[t] }:
	Provide_Spinning_Reserve[pid, a, t, p, h] <= 
	if t in INTERMEDIATE_TECHNOLOGIES
	then ( max_spinning_reserve_fraction_of_capacity[t] * Commit_Intermediate_Gen[pid, a, t, p, h] )
	else (	
	( max_spinning_reserve_fraction_of_capacity[t] / ( 1 - max_spinning_reserve_fraction_of_capacity[t] ) ) 
	* ( if can_build_new[t] then DispatchGen[pid, a, t, p, h] else ProducePowerEP[pid, a, t, p, h] ) );


########################################
# GENERATOR INSTALLATION CONSTRAINTS           
# there are limits on total installations in certain projects

# for residential and commercial PV, geothermal, offshore and onshore wind, and CAES,
# the max resource is plant specific and is given by the capacity_limit
subject to Maximum_Resource_Single_Location { (pid, a, t, p) in PROJECT_VINTAGES: resource_limited[t] and not competes_for_space[t] }:
	Installed_To_Date[pid, a, t, p]
  		<= capacity_limit[pid, a, t];
  
# for solar, installation constraints are in the form of land area (capacity_limit_by_location) and the capacity_limit_conversion denotes the MW/km^2
# if you multiply capacity_limit * capacity_limit_conversion for any given central station solar project,
# you get the max MW that could be installed for that project if no other competing projects were installed on the same chunk of land
# but because central station solar projects do compete for land, only the Maximum_Resource_Central_Station_Solar constraint is enforced,
# (i.e. there is no Maximum_Resource_Single_Location constraint for central station solar projects)
subject to Maximum_Resource_Central_Station_Solar { (l, a) in CENTRAL_STATION_SOLAR_LOCATIONS, p in PERIODS }:
	( sum { (pid, a, t) in PROJECT_CENTRAL_STATION_SOLAR: location_id[pid, a, t] = l } 
		Installed_To_Date[pid, a, t, p] / capacity_limit_conversion[pid, a, t] )
		<= central_station_solar_capacity_limit[l, a];

# for Bio_Solid and Bio_Gas, bio_fuel_limit_by_load_area is in MMBtu/period
# which is then converted into MWh via the heat_rate rate and cogen_thermal_demand
# cogen_thermal_demand is zero for non-cogen plants
# Bio_Liquid isn't included here because it only has replacements of existing cogen plants,
# so their installation constraint is Maximum_Resource_EP_Cogen_Replacement
# also, we need both CCS and non CCS bio fuels to be constrained together here (they're the same fuel really), hence the fuel matching with f = sub(fuel[t],'_CCS', '')
# if this constraint is changed, check var ConsumeBioSolid above - it may need to be changed as well
subject to Maximum_Resource_Bio { (f, a, p) in BIO_FUELS_LOAD_AREAS: bio_fuel_limit_by_load_area[f, a, p] > 0 }:
	(
	( sum { (pid, a, t, p) in PROJECT_VINTAGES: f = sub(fuel[t],'_CCS', '') } 
		( Installed_To_Date[pid, a, t, p] * gen_availability[t]
		* ( heat_rate[pid, a, t] + cogen_thermal_demand[pid, a, t] ) ) )
	+ ( sum { (pid, a, t, p) in EP_PERIODS: f = sub(fuel[t],'_CCS', '') } 
		( OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] * gen_availability[t]
		* ( ep_heat_rate[pid, a, t] + ep_cogen_thermal_demand[pid, a, t] ) ) )
		) * hours_in_period[p]
		<= bio_fuel_limit_by_load_area[f, a, p];


# for plants that replace existing cogen plants, this is just the old plant capacity
subject to Maximum_Resource_EP_Cogen_Replacement { (l, a) in EP_COGEN_REPLACEMENT_PLANT_LOCATIONS, p in PERIODS }:
  ( sum { (pid, a, t, p) in PROJECT_VINTAGES: cogen[t] and ep_project_replacement_id[pid, a, t] = l } Installed_To_Date[pid, a, t, p] )
  		<= cogen_plant_capacity_limit[l, a];

# Some generators (currently only Nuclear) have a minimum build size. This enforces that constraint
# If a generator is installed, then BuildGenOrNot is 1, and InstallGen has to be >= min_build_capacity
# If a generator is NOT installed, then BuildGenOrNot is 0, and InstallGen has to be >= 0
subject to Minimum_GenSize 
  {(pid, a, t, p) in PROJECT_VINTAGES: min_build_capacity[t] > 0}:
  InstallGen[pid, a, t, p] >= min_build_capacity[t] * BuildGenOrNot[pid, a, t, p];

# This binds BuildGenOrNot to InstallGen. The number below (1e5) is somewhat arbitrary. 
# I picked a number that would be far above the largest generator that would possibly be built
# If a generator is installed, then BuildGenOrNot is 1, and InstallGen can be between 0 & 1e5 - basically no upper limit
# If a generator is NOT installed, then BuildGenOrNot is 0, and InstallGen has to be <= 0
subject to BuildGenOrNot_Constraint 
  {(pid, a, t, p) in PROJECT_VINTAGES: min_build_capacity[t] > 0}:
  InstallGen[pid, a, t, p] <= 100000 * BuildGenOrNot[pid, a, t, p];


########################################
# TRANSMISSION CONSTRAINTS

# the system can only use as much transmission as is expected to be available, which is availability * ( existing + new )
subject to Maximum_DispatchTrans
  { (a1, a2, p) in TRANSMISSION_LINE_PERIODS, h in TIMEPOINTS: period[h] = p }:
  sum { (a1, a2, fc, p, h) in TRANSMISSION_LINE_HOURS } DispatchTrans[a1, a2, fc, p, h] 
    <= ( 1 - transmission_forced_outage_rate ) * 
          ( existing_transfer_capacity_mw[a1, a2] + sum { (a1, a2, online_yr) in TRANSMISSION_LINE_NEW_PERIODS: online_yr <= p } InstallTrans[a1, a2, online_yr] );

# Simple fix to the problem of asymetrical transmission build-out
subject to SymetricalTrans
  { (a1, a2, p) in TRANSMISSION_LINE_NEW_PERIODS }: InstallTrans[a1, a2, p] = InstallTrans[a2, a1, p];


# Mexican exports are capped as to not power all of LA from Tijuana
# The historical precedent for this constraint is that Baja has exported a small fraction of their power to the US in the past
# In 2008, they had a load of 11418 GWh and exported a net of 857 GWh.
# The growth rate of exports is capped at 3.2%, as this is historical growth rate from 2003-2008
# (when they started to export power, rather than import).
# this cap is imposed in the middle of the period
# see the Mexico folder of in Switch_Input_Data for calculations and reference.

# the net amount of power mexican baja california sent to the US in 2008, in MWh
param mex_baja_net_export_in_2008 = 857000;
param mex_baja_export_growth_rate = 0.032;
param mex_baja_export_limit_mwh { p in PERIODS }
	= sum { y in YEARS: y >= p and y < p + num_years_per_period } mex_baja_net_export_in_2008 * ( 1 + mex_baja_export_growth_rate ) ^ ( y - 2008 );

subject to Mexican_Export_Limit
  { a in LOAD_AREAS, p in PERIODS: a = 'MEX_BAJA' }:
	# transmission into Baja Mexico
	- ( sum { (a2, a, fc, p, h) in TRANSMISSION_LINE_HOURS } DispatchTrans[a2, a, fc, p, h] * hours_in_sample[h] )
	# transmission out of Baja Mexico
	+ ( sum { (a, a2, fc, p, h) in TRANSMISSION_LINE_HOURS } DispatchTrans[a, a2, fc, p, h] * hours_in_sample[h] )
	<=
	mex_baja_export_limit_mwh[p];

#################################
# Installable (non pumped hydro) storage constraints

# Energy output from CAES plants is apportioned into two separate decision variables:
# DispatchGen for the power attributable to NG combustion and ReleaseEnergy for the power attributable to stored energy.
# The ratio of NG:Stored is fixed at plant design and this constraint enforces that relationship. 
subject to CAES_Combined_Dispatch { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: t = 'Compressed_Air_Energy_Storage' }:
  	ReleaseEnergy[pid, a, t, p, h] = 
  	  DispatchGen[pid, a, t, p, h] * caes_storage_to_ng_ratio[t];

subject to CAES_Combined_Operating_Reserve { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: t = 'Compressed_Air_Energy_Storage' }:
  	Storage_Operating_Reserve[pid, a, t, p, h] = 
  	  ( Provide_Spinning_Reserve[pid, a, t, p, h] + Provide_Quickstart_Capacity[pid, a, t, p, h] )
  	  * caes_storage_to_ng_ratio[t];
 	  
# Maximum store rate, derated for occasional forced outages
# StoreEnergy represents the load on the grid from storing electrons
subject to Maximum_Store_Rate {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t]}:
  	StoreEnergy[pid, a, t, p, h]
  		<= Installed_To_Date[pid, a, t, p] * max_store_rate[t] * gen_availability[t];

# Maximum dispatch rate, derated for occasional forced outages
# CAES dispatch is apportioned between DispatchGen and ReleaseEnergy for NG and stored energy respectivly
# Operating reserves are also apportioned between Provide_Spinning_Reserve/Provide_Quickstart_Capacity and Storage_Operating_reserve
# while other storage projects (currently only Battery_Storage) don't have input energy other than grid electricity
subject to Maximum_Release_and_Operating_Reserve_Storage_Rate { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t] }:
  	ReleaseEnergy[pid, a, t, p, h] 
  	+ ( if t = 'Compressed_Air_Energy_Storage'
  		then ( DispatchGen[pid, a, t, p, h] + Provide_Spinning_Reserve[pid, a, t, p, h] + Provide_Quickstart_Capacity[pid, a, t, p, h] ) else 0 )
  	+ Storage_Operating_Reserve[pid, a, t, p, h] 
  		<= Installed_To_Date[pid, a, t, p] * gen_availability[t];

# Energy balance
# The parameter round_trip_efficiency below expresses the relationship between the amount of electricity from the grid used
# to charge the storage device and the amount that is dispatched back to the grid.
# For hybrid technologies like compressed-air energy storage (CAES), the round-trip efficiency will be higher than 1
# because natural gas is added to run the turbine. For CAES, this parameter is therefore only a "partial energy balance,"
# i.e. only one form of energy -- electricity -- is included in the balancing.
# The input of natural gas is handeled in CAES_Combined_Dispatch above
  
# this energy balance constraint also takes into account the useful energy released by storage projects when the operating reserve is actually deployed
subject to Storage_Projects_Energy_Balance { (pid, a, t, p) in PROJECT_VINTAGES, d in DATES: storage[t] and period_of_date[d] = p }:
	sum { h in TIMEPOINTS: date[h] = d } ( 
		ReleaseEnergy[pid, a, t, p, h]
		+ fraction_of_time_operating_reserves_are_deployed * Storage_Operating_Reserve[pid, a, t, p, h]
			)
		<= sum { h in TIMEPOINTS: date[h] = d } ( StoreEnergy[pid, a, t, p, h] * storage_efficiency[t] );
		

################################################################################
# HYDRO CONSTRAINTS

# The variable Store_Pumped_Hydro represents the MW of electricity required to pump water uphill (the load on the grid from pumping)
# To represent efficiency losses, the electrons stored by Store_Pumped_Hydro are then derated by the storage_efficiency[t] when dispatched
# so the stock of MW available to be dispatched from pumping hydro projects 
# is anything already in the upstream flow (ProducePowerEP) plus Store_Pumped_Hydro * storage_efficiency[t]

# RPS for Pumped Hydro storage: electrons come in three RPS colors:
# any electron that is from upstream gets labeled blue - i.e. whatever color hydro is... currently this equates to brown
# also, any stored electron (less the storage_efficiency[t]) must retain its color - either brown or green 

# for every hour, the amount of water released plus any operating reserve provided can't be more than the turbine capacity
subject to Maximum_Dispatch_and_Operating_Reserve_Hydro { (a, t, p, h) in HYDRO_AVAILABLE_HOURS }:
 	DispatchHydro[a, t, p, h]
	+ Hydro_Operating_Reserve[a, t, p, h]
	+ (if t = 'Hydro_Pumped'
		then ( Dispatch_Pumped_Hydro_Storage[a, t, p, h] + Pumped_Hydro_Storage_Operating_Reserve[a, t, p, h] )
		else 0 )
    <= hydro_capacity_mw_in_load_area[a, t] * gen_availability[t];

# for every hour, for NONPUMPED hydro,
# the amount of water released can't be less than that necessary to maintain stream flow
# there is no pumped minimum output from streamflow constraint
# because water can be released from the lower reservoir at will into the stream
subject to Minimum_Dispatch_Hydro { (a, t, p, h) in NONPUMPED_HYDRO_AVAILABLE_HOURS }:
  DispatchHydro[a, t, p, h] >= avg_hydro_output_load_area_agg[a, t, p, date[h]] * min_nonpumped_hydro_dispatch_fraction;

# for every day, the historical monthly average flow must be met to maintain downstream flow
# these electrons will be labeled blue by other constraints
# this energy balance constraint also takes into account the energy provided by hydro
# when operating reserve is actually deployed
subject to Average_Hydro_Output { (a, t, p, d) in HYDRO_DATES }:
  sum { h in TIMEPOINTS: date[h]=d } ( DispatchHydro[a, t, p, h] + fraction_of_time_operating_reserves_are_deployed * Hydro_Operating_Reserve[a, t, p, h] )
# The sum below is equivalent to the daily hydro flow, but only over the study hours considered in each day
  <= sum {h in TIMEPOINTS: date[h]=d} avg_hydro_output_load_area_agg[a, t, p, d];

	
# maximum operating reserve that can be provided by hydro projects as a fraction of nameplate capacity
subject to Max_Operating_Reserve_Hydro { (a, t, p, h) in HYDRO_AVAILABLE_HOURS }:
	Hydro_Operating_Reserve[a, t, p, h] 
	+ ( if t = 'Hydro_Pumped' then Pumped_Hydro_Storage_Operating_Reserve[a, t, p, h] else 0 )
	<= 0.20 * hydro_capacity_mw_in_load_area[a, t]; 

# Can't pump more water uphill than the pump capacity (in MW)
# As mentioned above, Store_Pumped_Hydro represents the grid load of storage
# so the storage efficiency is taken into account in dispatch
# TODO: Research how MW pumping capacity translates into water flows - 
# it's unclear whether these pumps can only take their capacity_mw in load,
# or if they can take capacity_mw / storage_efficiency[t] in load thereby storing their capacity_mw uphill.
# We'll take the conservative assumption here that they can only store capacity_mw * storage_efficiency[t]
subject to Maximum_Store_Pumped_Hydro { (a, t, p, h) in PUMPED_HYDRO_AVAILABLE_HOURS }:
  Store_Pumped_Hydro[a, t, p, h] <= hydro_capacity_mw_in_load_area[a, t] * gen_availability[t] ;

# Pumped hydro has to dispatch all electrons it stored each day 
subject to Pumped_Hydro_Energy_Balance { (a, t, p, d) in PUMPED_HYDRO_DATES: period_of_date[d] = p }:
    sum { h in TIMEPOINTS: date[h]=d } ( 
    Dispatch_Pumped_Hydro_Storage[a, t, p, h]
    + fraction_of_time_operating_reserves_are_deployed * Pumped_Hydro_Storage_Operating_Reserve[a, t, p, h] ) 
    <= 
	sum { h in TIMEPOINTS: date[h]=d } Store_Pumped_Hydro[a, t, p, h] * storage_efficiency[t];


################################################################################

problem Investment_Cost_Minimization: 
  # Objective function 
	Power_Cost, 
  # Satisfy Load and Power Consumption
    Satisfy_Load,
	Conservation_Of_Energy_NonDistributed, ConsumeNonDistributedPower, 
  # Policy Constraints
	Satisfy_Primary_RPS, Satisfy_Distributed_RPS, Meet_California_Solar_Initiative, Carbon_Cap,
	ConsumeREC, Conservation_of_REC,
  # Investment Decisions
	InstallGen, BuildGenOrNot, InstallTrans, 
  # Installation Constraints
	Maximum_Resource_Central_Station_Solar, Maximum_Resource_Bio, Maximum_Resource_Single_Location, Maximum_Resource_EP_Cogen_Replacement,
	Minimum_GenSize, BuildGenOrNot_Constraint, SymetricalTrans, 
  # Dispatch Decisions
	DispatchGen, DispatchFlexibleBaseload, Deep_Cycle_Amount, Commit_Intermediate_Gen, Startup_MW_from_Last_Hour, OperateEPDuringPeriod, ProducePowerEP, ConsumeBioSolid, ConsumeNaturalGas, ConsumeNaturalGasRegional,
	DispatchTrans,  
	StoreEnergy, ReleaseEnergy,
	DispatchHydro, Dispatch_Pumped_Hydro_Storage, Store_Pumped_Hydro,
	Provide_Spinning_Reserve, Provide_Quickstart_Capacity, Storage_Operating_Reserve, Hydro_Operating_Reserve, Pumped_Hydro_Storage_Operating_Reserve,
  # Dispatch Constraints
	Power_and_Operating_Reserve_From_Dispatchable_Plants, Maximum_Intermediate_Capacity_Online, Maximum_Dispatch_Intermediate_Gen, Minimum_Loading_Intermediate_Gen,
    Intermediate_Gen_Startup, Peaker_Plant_Startup, Power_From_New_Flexible_Baseload_Plants, Minimum_Loading_New_Flexible_Baseload_Plants,
    EP_Operational_Continuity, EP_Power_and_Operating_Reserve_From_Dispatchable_Plants, EP_Power_From_Intermittent_Plants, EP_Power_From_Hydro_Plants, 
	EP_Power_From_Baseload_Plants, EP_Power_From_Flexible_Baseload_Plants, Maximum_Loading_Existing_Flexible_Baseload_Plants, Minimum_Loading_Existing_Flexible_Baseload_Plants, Spinning_Reserve_as_Fraction_of_Dispatch,
	Maximum_DispatchTrans, 
	Mexican_Export_Limit, 
	Maximum_Dispatch_and_Operating_Reserve_Hydro, Minimum_Dispatch_Hydro, Average_Hydro_Output, Max_Operating_Reserve_Hydro,
	Maximum_Store_Pumped_Hydro, Pumped_Hydro_Energy_Balance,
	CAES_Combined_Dispatch, CAES_Combined_Operating_Reserve, Maximum_Store_Rate, Maximum_Release_and_Operating_Reserve_Storage_Rate, Storage_Projects_Energy_Balance,
  # Contigency Planning Constraints
	Satisfy_Load_Reserve, 
	Conservation_Of_Energy_NonDistributed_Reserve, ConsumeNonDistributedPower_Reserve,
  # Operating Reserve Variables
    Spinning_Reserve_Requirement, Quickstart_Reserve_Requirement,
  # Operating Reserve Constraints
    Spinning_Reserve_Requirement_in_Balancing_Area_in_Hour, Quickstart_Reserve_Requirement_in_Balancing_Area_in_Hour, Satisfy_Spinning_Reserve_Requirement,
    Satisfy_Quickstart_Reserve_Requirement
;


problem Present_Day_Cost_Minimization: 
  # Objective function 
	Power_Cost, 
  # Satisfy Load and Power Consumption
    Satisfy_Load,
	Conservation_Of_Energy_NonDistributed, ConsumeNonDistributedPower, 
  # Installation Decisions - only gas combustion turbines for the present day optimization
	{(pid, a, t, p) in PROJECT_VINTAGES: t='Gas_Combustion_Turbine'} InstallGen[pid, a, t, p], 
  # Dispatch Decisions
	DispatchGen, DispatchFlexibleBaseload, Deep_Cycle_Amount, Commit_Intermediate_Gen, Startup_MW_from_Last_Hour, ProducePowerEP, ConsumeBioSolid, ConsumeNaturalGas, ConsumeNaturalGasRegional,
	DispatchTrans, 
	{(pid, a, t, p) in EP_PERIODS: not intermittent[t] and not hydro[t] and ep_could_be_operating_past_expected_lifetime[pid, a, t, p]} OperateEPDuringPeriod[pid, a, t, p],
	DispatchHydro, Dispatch_Pumped_Hydro_Storage, Store_Pumped_Hydro,
	Provide_Spinning_Reserve, Provide_Quickstart_Capacity, Hydro_Operating_Reserve, Pumped_Hydro_Storage_Operating_Reserve, 
  # Dispatch Constraints
	Power_and_Operating_Reserve_From_Dispatchable_Plants, Maximum_Intermediate_Capacity_Online, Maximum_Dispatch_Intermediate_Gen, Minimum_Loading_Intermediate_Gen,
    Intermediate_Gen_Startup, Peaker_Plant_Startup,
	EP_Power_and_Operating_Reserve_From_Dispatchable_Plants, EP_Power_From_Intermittent_Plants, EP_Power_From_Hydro_Plants,
	EP_Power_From_Baseload_Plants, EP_Power_From_Flexible_Baseload_Plants,
    Maximum_Loading_Existing_Flexible_Baseload_Plants, Minimum_Loading_Existing_Flexible_Baseload_Plants, Spinning_Reserve_as_Fraction_of_Dispatch,
	Maximum_DispatchTrans, Mexican_Export_Limit,
	Maximum_Dispatch_and_Operating_Reserve_Hydro, Average_Hydro_Output, Minimum_Dispatch_Hydro,
	Max_Operating_Reserve_Hydro,
	Maximum_Store_Pumped_Hydro, Pumped_Hydro_Energy_Balance,
  # Operating Reserve Variables
    Spinning_Reserve_Requirement, Quickstart_Reserve_Requirement,
  # Operating Reserve Constraints
    Spinning_Reserve_Requirement_in_Balancing_Area_in_Hour, Quickstart_Reserve_Requirement_in_Balancing_Area_in_Hour, Satisfy_Spinning_Reserve_Requirement,
    Satisfy_Quickstart_Reserve_Requirement
;