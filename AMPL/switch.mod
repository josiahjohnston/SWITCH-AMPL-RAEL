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
param period_of_date {d in DATES} = min {h in TIMEPOINTS:date[h] = d} period[h];

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


###############################################
# System loads and areas

# Load Areas are the smallest unit of load in the model. 
set LOAD_AREAS;

# load area id, useful for rapidly referencing the database
param load_area_id {LOAD_AREAS} >= 0;

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

# system load aggregated in various ways
param total_loads_by_period {p in PERIODS} = 
	sum {a in LOAD_AREAS, h in TIMEPOINTS: period[h]=p} system_load[a, h];
param total_loads_by_period_weighted {p in PERIODS} = 
	sum {a in LOAD_AREAS, h in TIMEPOINTS: period[h]=p} system_load[a, h] * hours_in_sample[h];

###################
# Financial data

# the year to which all costs should be discounted
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

# annual fuel price forecast in $/MBtu
param fuel_price {LOAD_AREAS, FUELS, YEARS} default 0, >= 0;
	
# carbon content (tons) per MBtu of each fuel.  Can be negative for bio ccs projects.
param carbon_content {FUELS} default 0;

# For now, all hours in each study period use the same fuel cost which averages annual prices over the course of each study period.
# This could be updated to use fuel costs that vary by month, or for an hourly model, it could interpolate between annual forecasts 
param fuel_cost_nominal {a in LOAD_AREAS, t in TECHNOLOGIES, p in PERIODS: fuel[t] not in BIO_SOLID_FUELS} := 
		( sum{ y in YEARS: y >= p and y < p + num_years_per_period } fuel_price[a, fuel[t], y] ) / num_years_per_period;

# biomass supply curve params
set LOAD_AREAS_AND_BIO_BREAKPOINTS dimen 2;

param num_bio_breakpoints {a in LOAD_AREAS} = max( { (la, bp) in LOAD_AREAS_AND_BIO_BREAKPOINTS: la = a } bp , 0 );
param price_dollars_per_mbtu {a in LOAD_AREAS, bp in 1..num_bio_breakpoints[a]}
	>= if bp = 1 then 0 else price_dollars_per_mbtu[a, bp-1];
param breakpoint_mbtus_per_year {a in LOAD_AREAS, bp in 1..num_bio_breakpoints[a]-1}
	> if bp = 1 then 0 else breakpoint_mbtus_per_year[a, bp-1];
param breakpoint_mbtus_per_period {a in LOAD_AREAS, bp in 1..num_bio_breakpoints[a]-1}
	= breakpoint_mbtus_per_year[a, bp] * num_years_per_period;
			  
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

# are new generators of this type installable (existing plant types are included in the set of TECHNOLOGIES)
param can_build_new {TECHNOLOGIES} binary;

# does the generator have a fixed hourly capacity factor?
param intermittent {TECHNOLOGIES} binary;

# is this type of plant run in baseload mode?
param baseload {TECHNOLOGIES} binary;

# is this technology an electricity storage technology?
param storage {TECHNOLOGIES} binary;

# is this plant dispatchable?  This includes compressed air energy storage but not battery storage
param dispatchable {TECHNOLOGIES} binary;

# is this plant a cogeneration plant?  Only existing plants can be cogen at the moment
# they are allowed ($) to extend their life past their expected lifetimes to keep serving thermal and electric loads
param cogen {TECHNOLOGIES} binary;

# is this technology a hydro technology?
param hydro {t in TECHNOLOGIES} binary = if fuel[t] = 'Water' then 1 else 0;

# the fraction of time a generator is expected to be up
# it's assumed that for dispatchable or intermittent generators or for storage
# that their scheduled maintenence can be done when they're not going to be producing energy
# while for baseload this is not the case.
param gen_availability { t in TECHNOLOGIES } >= 0 <= 1 =
	if ( dispatchable[t] or intermittent[t] or storage[t] or hydro[t] ) then ( 1 - forced_outage_rate[t] )
	else if baseload[t] then ( ( 1 - forced_outage_rate[t] ) * ( 1 - scheduled_outage_rate[t] ) );

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

# maximum capacity factors (%) for each project, each hour. 
# generally based on renewable resources available
set PROJ_INTERMITTENT_HOURS dimen 4;  # PROJECT_ID, LOAD_AREAS, TECHNOLOGIES, TIMEPOINTS
set PROJ_INTERMITTENT = setof {(pid, a, t, h) in PROJ_INTERMITTENT_HOURS} (pid, a, t);

check: card({(pid, a, t) in PROJECTS: intermittent[t] and resource_limited[t] and not ccs[t]} diff PROJ_INTERMITTENT) = 0;
param cap_factor {PROJ_INTERMITTENT_HOURS};

# project-vintage combinations that can be installed
# Combustion turbines are assumed to be installable quickly to meet peak load in present day dispatch
# as the historical existing plant data that SWITCH uses is always a year or two old
set PROJECT_VINTAGES = { (pid, a, t) in PROJECTS, p in PERIODS: p >= min_build_year[t] + construction_time_years[t] };

# date when a plant of each type and vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made) 
# until the end of that period. This avoids having artificial gaps
# between retirements and starting new plants.
param project_end_year {(pid, a, t, p) in PROJECT_VINTAGES} =
	min(end_year, p + ceil(max_age_years[t]/num_years_per_period)*num_years_per_period);

set PROJECT_VINTAGE_INSTALLED_PERIODS :=
	{ (pid, a, t, install_yr) in PROJECT_VINTAGES, p in PERIODS: install_yr <= p < project_end_year[pid, a, t, install_yr] };

# maximum capacity that can be installed in each project. These are units of MW for most technologies. The exceptions are Central PV and CSP, which have units of km^2 and a conversion factor of MW / km^2
set LOCATIONS_WITH_COMPETING_TECHNOLOGIES dimen 2 ;
param capacity_limit_by_location {(l, a) in LOCATIONS_WITH_COMPETING_TECHNOLOGIES} =
	min {(pid, a, t) in PROJECTS: resource_limited[t] and not ccs[t] and project_location[pid, a, t] = l } capacity_limit[pid, a, t];

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

param rps_fuel_category_tech {t in TECHNOLOGIES: t <> 'Battery_Storage'} symbolic = rps_fuel_category[fuel[t]];

# rps compliance fraction as a function of yearly load
param rps_compliance_fraction {LOAD_AREAS, YEARS} >= 0 default 0;

# average the RPS compliance percentages over a period to get the RPS target for that period
# the end year is the year after the last period, so this sum doesn't include it.
param rps_compliance_fraction_in_period {a in LOAD_AREAS, p in PERIODS} = 
	( sum {yr in YEARS: yr >= p and yr < p + num_years_per_period}
	rps_compliance_fraction[a, yr] ) / num_years_per_period;

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

# year when the plant was built (used to calculate annual capital cost and retirement date)
param ep_vintage {EXISTING_PLANTS} >= 0;

# overnight cost of the plant ($/MW)
param ep_overnight_cost {EXISTING_PLANTS} >= 0;

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
  min(end_year, start_year+ceil((ep_vintage[pid, a, t]+max_age_years[t]-start_year)/num_years_per_period)*num_years_per_period);

# plant-period combinations when existing plants can run
# these are the times when a decision must be made about whether a plant will be kept available for the year
# or mothballed to save on fixed O&M (or fuel, for baseload plants)
# cogen, geothermal and Bio_Liquid plants can be operated past their normal lifetime by paying O & M costs during each period, plus paying into a capital replacement fund
# existing nuclear plants are assumed to be kept operational indefinitely, as their O&M costs generally keep them in really good condition
# hydro plants are kept operational indefinitely
set EP_PERIODS :=
  { (pid, a, t) in EXISTING_PLANTS, p in PERIODS:
  		( not cogen[t] and p < ep_end_year[pid, a, t] ) or
  		( cogen[t] ) or
		( hydro[t] ) or
  		( t = 'Geothermal_EP' ) or
  		( t = 'Nuclear_EP' ) or
  		( fuel[t] = 'Bio_Liquid' ) };

# if a period exists that is >= ep_end_year[pid, a, t], then this plant can be operational past the expected lifetime of the plant
param ep_could_be_operating_past_expected_lifetime { (pid, a, t, p) in EP_PERIODS } =
  (if p >= ep_end_year[pid, a, t]
   then 1
   else 0);

# union new projects and existing plants
set AVAILABLE_VINTAGES = PROJECT_VINTAGES union EP_PERIODS;

# plant-hour combinations when generators and storage can be available. 
set AVAILABLE_HOURS := { (pid, a, t, p) in AVAILABLE_VINTAGES, h in TIMEPOINTS: period[h] = p};

# plant-hour combinations when existing plants can be available. 
set EP_AVAILABLE_HOURS := { (pid, a, t, p, h) in AVAILABLE_HOURS: not can_build_new[t] };

# project-vintage-hour combinations when new plants are available. 
set PROJECT_VINTAGE_HOURS := { (pid, a, t, p, h) in AVAILABLE_HOURS: can_build_new[t] };

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
# right now, it's set at 25% of the average stream flow for each month
# there isn't a similar paramter for pumped hydro because it is assumed that the lower resevoir is large enough
# such that hourly stream flow can be maintained independent of the pumped hydro dispatch
# especially because the daily flow through the turbine will be constrained to be within historical monthly averages below
param min_nonpumped_hydro_dispatch_fraction = 0.25;

# useful pumped hydro sets for recording results 
set PUMPED_HYDRO_AVAILABLE_HOURS_BY_FC_AND_PID := { (pid, a, t, p, h) in EP_AVAILABLE_HOURS, fc in RPS_FUEL_CATEGORY: t = 'Hydro_Pumped' };
set PUMPED_HYDRO_AVAILABLE_HOURS_BY_FC := setof { (pid, a, t, p, h, fc) in PUMPED_HYDRO_AVAILABLE_HOURS_BY_FC_AND_PID } (a, t, p, h, fc);

# load_area-hour combinations when hydro existing plants can be available. 
set NONPUMPED_HYDRO_AVAILABLE_HOURS := setof { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: t = 'Hydro_NonPumped' } (a, t, p, h);
set PUMPED_HYDRO_AVAILABLE_HOURS := setof { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: t = 'Hydro_Pumped' } (a, t, p, h);
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
# Transmission lines

# $ cost per mw-km for transmission lines
# because transmission lines are built in one direction only and then constrained to have the same capacity in both directions
# the per direction value needs to be half of what it would cost to install each line
param transmission_cost_per_mw_km = 1000;
param transmission_cost_per_mw_km_per_direction = transmission_cost_per_mw_km / 2;

# should also at some point include costs for transmission maintenance: 
# which is quoted as 3% of the installation cost in the 2009 WREZ transmission model transmission data
# param transmission_annual_payment_per_mw_km := 0.03 * transmission_cost_per_mw_km;

# the cost to maintin the existing transmission infrustructure over all of WECC
param transmission_sunk_annual_payment {LOAD_AREAS} >= 0;

# financial age for transmission lines - from the 2009 WREZ transmission model transmission data
param transmission_max_age_years = 20;

# forced outage rate for transmission lines, used for probabilistic dispatch(!)
param transmission_forced_outage_rate = 0.01;

# possible transmission lines are listed in advance;
# these include all possible combinations of LOAD_AREAS, with no double-counting
# The model could be simplified by only allowing lines to be built between neighboring zones.
set TRANSMISSION_LINES in {LOAD_AREAS, LOAD_AREAS};

# length of each transmission line
param transmission_length_km {TRANSMISSION_LINES};

# delivery efficiency on each transmission line
param transmission_efficiency {TRANSMISSION_LINES};

# are new builds of transmission lines allowed along this transmission corridor?
param new_transmission_builds_allowed {TRANSMISSION_LINES} binary;

set TRANSMISSION_LINES_NEW_BUILDS_ALLOWED := { (a1, a2) in TRANSMISSION_LINES: new_transmission_builds_allowed[a1, a2] };

# distribution losses, expressed as percentage of system load
# this is not applied to distributed solar PV systems, which are assumed to be located within the distribution system, close to load
# we took 5.3% losses value from ReEDS Solar Vision documentation, http://www1.eere.energy.gov/solar/pdfs/svs_appendix_a_model_descriptions_data.pdf
param distribution_losses = 0.053;

# the rating of existing lines in MW (can be different for the two directions, but each direction is
# represented by an individual entry in the table)
param existing_transfer_capacity_mw {TRANSMISSION_LINES} >= 0 default 0;

# unique ID for each transmission line, used for reporting results
param transmission_line_id {TRANSMISSION_LINES};

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


#####################
# calculate discounted costs for new plants

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
	overnight_cost[pid, a, t] * (1+overnight_cost_change[pid, a, t])^(p - construction_time_years[t] - price_and_dollar_year[pid, a, t]);

# The equations below make a working assumption that the "finance rate" and "discount rate" are the same value. 
# If those numbers take on different values, the equation will need to be inspected for correctness. 
# Bring the series of lump-sum costs made during construction up to the year before the plant starts operation. 
param cost_of_plant_one_year_before_operational {(pid, a, t, p) in AVAILABLE_VINTAGES} =
  # Connect costs are incurred in said year, so they don't accrue interest
  ( if can_build_new[t] then connect_cost_per_mw[pid, a, t] else 0 ) + 
  # Construction costs are incurred annually during the construction phase. 
  sum{ yr_of_constr in YEAR_OF_CONSTRUCTION } (
  	cost_fraction[t, yr_of_constr] * ( if can_build_new[t] then project_vintage_overnight_costs[pid, a, t, p] else ep_overnight_cost[pid, a, t] )*
  	# This exponent will range from (construction_time - 1) to 0, meaning the cost of the last year's construction doesn't accrue interest.
  	(1 + discount_rate) ^ ( construction_time_years[t] - yr_of_constr - 1 )
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
  sum {p in PERIODS: online_yr <= p < project_end_year[pid, a, t, online_yr]} capital_cost_annual_payment [pid, a, t, online_yr]
  * discount_to_base_year[p];

# discount capital costs to a lump-sum value at the start of the study.
param ep_capital_cost { (pid, a, t, p) in EP_PERIODS } =
    if (ep_could_be_operating_past_expected_lifetime[pid, a, t, p] and ( t = 'Nuclear_EP' or hydro[t] ) )
    then 0
    else capital_cost_annual_payment[pid, a, t, p] * discount_to_base_year[p];


# Take the stream of fixed annual O & M payments over the duration of the each period,
# and discount to a lump-sum value at the start of the period,
# then discount from there to the base_year.
param fixed_o_m_by_period {(pid, a, t, p) in AVAILABLE_VINTAGES} = 
  # Fixed annual costs that are paid while the plant is operating (up to the end of the study period)
	( if can_build_new[t] then fixed_o_m[pid, a, t] else ep_fixed_o_m[pid, a, t] )
    * discount_to_base_year[p];

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
# In variable costs, hours_in_sample is a weight intended to reflect how many hours are represented by a timepoint.
# hours_in_sample is calculated using period length in MySQL: period_length * (days represented) * (subsampling factors),
# so if you work through the math, variable costs are multiplied by period_length.
param variable_cost {(pid, a, t, p, h) in AVAILABLE_HOURS} =
	( if can_build_new[t] then variable_o_m[pid, a, t] else ep_variable_o_m[pid, a, t] )
  	* ( hours_in_sample[h] / num_years_per_period )
    * discount_to_base_year[p];

param fuel_cost {(pid, a, t, p, h) in AVAILABLE_HOURS: fuel[t] not in BIO_SOLID_FUELS } =
	( if can_build_new[t] then heat_rate[t] else ep_heat_rate[pid, a, t] )
  	* fuel_cost_nominal[a, t, p]
  	* ( hours_in_sample[h] / num_years_per_period )
    * discount_to_base_year[p];

param carbon_cost_per_mwh {(pid, a, t, p, h) in AVAILABLE_HOURS} = 
   	hours_in_sample[h] * (
	  ( if can_build_new[t] then heat_rate[t] else ep_heat_rate[pid, a, t] ) * carbon_content[fuel[t]] * carbon_cost
	) / num_years_per_period
	* discount_to_base_year[p];

########
# now get discounted costs per MW for transmission lines and local T&D on similar terms

# cost per MW for transmission lines
# TODO: Move the regional cost adjustment into the database. 
param transmission_annual_payment {(a1, a2) in TRANSMISSION_LINES_NEW_BUILDS_ALLOWED } = 
  discount_rate / ( 1 - ( 1 + discount_rate ) ^ ( -1 * transmission_max_age_years ) ) 
  * transmission_cost_per_mw_km_per_direction * ( (economic_multiplier[a1] + economic_multiplier[a2]) / 2 )
  * transmission_length_km[a1, a2];

# date when a transmission line built of each vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made).
param transmission_end_year {p in PERIODS} =
  min(end_year, p + ceil(transmission_max_age_years/num_years_per_period)*num_years_per_period);

# trans_line-vintage-hour combinations for which dispatch decisions must be made
set TRANS_VINTAGE_HOURS := 
  {(a1, a2) in TRANSMISSION_LINES_NEW_BUILDS_ALLOWED, p in PERIODS, h in TIMEPOINTS: p <= period[h] < transmission_end_year[p]};

# discounted transmission cost per MW
param transmission_cost_per_mw {(a1, a2) in TRANSMISSION_LINES_NEW_BUILDS_ALLOWED, install_yr in PERIODS } =
  sum {p in PERIODS: install_yr <= p < transmission_end_year[p]}
  transmission_annual_payment[a1, a2]
  * discount_to_base_year[p];

# date when a when local T&D infrastructure of each vintage will stop being included in the simulation
# note: if it would be expected to retire between study periods,
# it is kept running (and annual payments continue to be made).
param local_td_end_year {p in PERIODS} =
  min(end_year, p + ceil(local_td_max_age_years/num_years_per_period)*num_years_per_period);

# discounted cost per MW for local T&D
# the costs are already regionalized, so no need to do it again here
param local_td_cost_per_mw {a in LOAD_AREAS, install_yr in PERIODS} = 
  sum {p in PERIODS: install_yr <= p < transmission_end_year[p]}
  local_td_new_annual_payment_per_mw[a]
  * discount_to_base_year[p];

# local_td-vintage-hour combinations which must be reconciled
set LOCAL_TD_HOURS := 
  {a in LOAD_AREAS, p in PERIODS, h in TIMEPOINTS: p <= period[h] < local_td_end_year[p]};

######## VARIABLES ########

# Number of MW of power consumed in each load area in each hour for non distributed and distributed projects
# in terms of actual load met - distribution losses are NOT consumed
# This is needed for RPS in cases where some excess power is spilled.
var ConsumeNonDistributedPower {LOAD_AREAS, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;
var ConsumeDistributedPower {LOAD_AREAS, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;

# same on a reserve basis
var ConsumeNonDistributedPower_Reserve {LOAD_AREAS, TIMEPOINTS} >= 0;
var ConsumeDistributedPower_Reserve {LOAD_AREAS, TIMEPOINTS} >= 0;

# variables to decide whether to redirect distributed power to the larger transmission-level grid for consumption elsewhere
var RedirectDistributedPower {LOAD_AREAS, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;
var RedirectDistributedPower_Reserve {LOAD_AREAS, TIMEPOINTS} >= 0;


# Project-level decision variables about how much generation to make available and how much power to dispatch

# number of MW to install for each project in each investment period
var InstallGen {PROJECT_VINTAGES} >= 0;

# number of MW to dispatch each dispatchable generator
var DispatchGen {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t]} >= 0;

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

# a derived variable indicating the number of Mbtu of Biomass Solid fuel to consume each period in each load area,
# as a function of the installed biomass generation capacity.
var ConsumeBioSolid {a in LOAD_AREAS, p in PERIODS: num_bio_breakpoints[a] > 0 }
	= sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: fuel[t] in BIO_SOLID_FUELS } 
	# the hourly MWh output of biomass solid projects in baseload mode is below
		( ( sum {(pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] ) * gen_availability[t]
	# weight each hour to get the total biomass consumed
      	* hours_in_sample[h] * heat_rate[t] );

# the load in MW drawn from grid from storing electrons in new storage plants
var StoreEnergy {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS, fc in RPS_FUEL_CATEGORY: storage[t]} >= 0;
# number of MW to generate from each storage project, in each hour. 
var ReleaseEnergy {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS, fc in RPS_FUEL_CATEGORY: storage[t]} >= 0;

# storage reserve variables. 
# ReleaseEnergy_Reserve is different from ReleaseEnergy in that all power from a CAES plant is attributed to ReleaseEnergy_Reserve rather than being spread over two decision variables. 
var StoreEnergy_Reserve {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t]} >= 0;
var ReleaseEnergy_Reserve {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t]} >= 0;

# amount of hydro to store and dispatch during each hour
# note: Store_Pumped_Hydro represents the load on the grid so the amount of energy available for release
# is Store_Pumped_Hydro * storage_efficiency[t]
var DispatchHydro {HYDRO_AVAILABLE_HOURS} >= 0;
var Dispatch_Pumped_Hydro_Storage {PUMPED_HYDRO_AVAILABLE_HOURS_BY_FC} >= 0;
var Store_Pumped_Hydro {PUMPED_HYDRO_AVAILABLE_HOURS_BY_FC} >= 0;
# hydro reserve variables
var DispatchHydro_Reserve {HYDRO_AVAILABLE_HOURS} >= 0;
var Dispatch_Pumped_Hydro_Storage_Reserve {PUMPED_HYDRO_AVAILABLE_HOURS} >= 0;
var Store_Pumped_Hydro_Reserve {PUMPED_HYDRO_AVAILABLE_HOURS} >= 0;

#############################
# Transmission and Local T&D variables

# number of MW to install in each transmission corridor at each vintage
var InstallTrans {TRANSMISSION_LINES_NEW_BUILDS_ALLOWED, PERIODS } >= 0;

# number of MW to transmit through each transmission corridor in each hour
var DispatchTransFromXToY {TRANSMISSION_LINES, TIMEPOINTS, RPS_FUEL_CATEGORY} >= 0;
var DispatchTransFromXToY_Reserve {TRANSMISSION_LINES, TIMEPOINTS} >= 0;


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
	# Capital costs
     (sum {(pid, a, t, p) in PROJECT_VINTAGES} 
        InstallGen[pid, a, t, p] * capital_cost[pid, a, t, p] )
	# Fixed Costs
	+(sum {(pid, a, t, p) in PROJECT_VINTAGES} 
	    ( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
	    	* fixed_o_m_by_period[pid, a, t, p] )
	# Variable costs for non-storage projects and the natural gas part of CAES
	+(sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t]} 
		DispatchGen[pid, a, t, p, h] * ( variable_cost[pid, a, t, p, h] + carbon_cost_per_mwh[pid, a, t, p, h] + fuel_cost[pid, a, t, p, h] ) )
	+(sum { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: intermittent[t]} 
		( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
			* cap_factor[pid, a, t, h] * gen_availability[t] * ( variable_cost[pid, a, t, p, h] + carbon_cost_per_mwh[pid, a, t, p, h] ) )
	+(sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: baseload[t]} 
	    ( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
	    	* gen_availability[t] * ( variable_cost[pid, a, t, p, h] + carbon_cost_per_mwh[pid, a, t, p, h] ) )
	# Fuel costs - intermittent generators don't have fuel costs as they're either solar or wind
	+(sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: baseload[t] and fuel[t] not in BIO_SOLID_FUELS} 
	    ( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
	    	* gen_availability[t] * fuel_cost[pid, a, t, p, h] )
	# BioSolid fuel costs - ConsumeBioSolid is the Mbtus of biomass consumed per period per load area
	# so this is annualized because costs in the objective function are annualized for proper discounting
	+(sum {a in LOAD_AREAS, p in PERIODS: num_bio_breakpoints[a] > 0} 
		<< { bp in 1..num_bio_breakpoints[a]-1 } breakpoint_mbtus_per_period[a, bp]; 
	   { bp in 1..num_bio_breakpoints[a] } price_dollars_per_mbtu[a, bp] >>
	   		ConsumeBioSolid[a, p] * ( 1 / num_years_per_period ) * discount_to_base_year[p]  )

	# Variable costs for storage projects: currently attributed to the dispatch side of storage
	# for CAES, power output is apportioned between DispatchGen and ReleaseEnergy by storage_efficiency_caes through the constraint CAES_Combined_Dispatch
	+(sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS, fc in RPS_FUEL_CATEGORY: storage[t]} 
	    ReleaseEnergy[pid, a, t, p, h, fc] * variable_cost[pid, a, t, p, h])
      
	#############################
	#    EXISTING PLANTS
	# Capital costs (sunk cost)
	+(sum {(pid, a, t, p) in EP_PERIODS: not ep_could_be_operating_past_expected_lifetime[pid, a, t, p]}
	  ep_capacity_mw[pid, a, t] * ep_capital_cost[pid, a, t, p] )
	# Calculate capital costs for all cogen plants that are operated beyond their expected retirement. 
	# This can be thought of as making payments into a capital replacement fund
	+(sum {(pid, a, t, p) in EP_PERIODS: not intermittent[t] and not hydro[t] and ep_could_be_operating_past_expected_lifetime[pid, a, t, p]} 
      OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] * ep_capital_cost[pid, a, t, p] )
	# Calculate fixed costs for all existing plants
	+(sum {(pid, a, t, p) in EP_PERIODS} 
       ( if ( intermittent[t] or hydro[t] ) then 1 else OperateEPDuringPeriod[pid, a, t, p] ) * ep_capacity_mw[pid, a, t] * fixed_o_m_by_period[pid, a, t, p] )
	# Calculate variable and carbon costs for all existing plants
	+(sum {(pid, a, t, p, h) in EP_AVAILABLE_HOURS}
	  ProducePowerEP[pid, a, t, p, h] * ( variable_cost[pid, a, t, p, h] + carbon_cost_per_mwh[pid, a, t, p, h] ) )
	# Calculate fuel costs for all existing plants except for bio_solid - that's included in the supply curve
	+(sum {(pid, a, t, p, h) in EP_AVAILABLE_HOURS: fuel[t] not in BIO_SOLID_FUELS}
	  ProducePowerEP[pid, a, t, p, h] * fuel_cost[pid, a, t, p, h] )

	########################################
	#    TRANSMISSION & DISTRIBUTION
	# Calculate the cost of installing new transmission lines between load areas
	+(sum {(a1, a2) in TRANSMISSION_LINES_NEW_BUILDS_ALLOWED, p in PERIODS } 
      InstallTrans[a1, a2, p] * transmission_cost_per_mw[a1, a2, p] )
	# Sunk costs of operating the existing transmission grid
	+(sum {a in LOAD_AREAS, p in PERIODS} transmission_sunk_annual_payment[a] * discount_to_base_year[p])
	# Calculate the cost of installing new local (intra-load area) transmission and distribution
	+(sum {a in LOAD_AREAS, p in PERIODS}
      install_local_td[a, p] * local_td_cost_per_mw[a, p] )
	# Sunk costs of operating the existing local (intra-load area) transmission and distribution
	+(sum {a in LOAD_AREAS, p in PERIODS} local_td_sunk_annual_payment[a] * discount_to_base_year[p])
;


############## CONSTRAINTS ##############

###### Policy Constraints #######

# RPS constraint
# windsun.run will drop this constraint if enable_rps is 0
subject to Satisfy_RPS {a in LOAD_AREAS, p in PERIODS: rps_compliance_fraction_in_period[a, p] > 0 }:
    ( sum { h in TIMEPOINTS, fc in RPS_FUEL_CATEGORY: period[h] = p and fuel_qualifies_for_rps[a, fc] } 
      ( ConsumeNonDistributedPower[a,h,fc] + ConsumeDistributedPower[a,h,fc] ) * hours_in_sample[h] )
  / ( sum {h in TIMEPOINTS: period[h]=p} 
      system_load[a, h] * hours_in_sample[h] )
     
   >= rps_compliance_fraction_in_period[a, p];

# Carbon Cap constraint
# windsun.run will drop this constraint if enable_carbon_cap is 0
subject to Carbon_Cap {p in PERIODS}:
	# Carbon emissions from new plants - none from intermittent plants
	  ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t]} DispatchGen[pid, a, t, p, h] * heat_rate[t] * carbon_content[fuel[t]] * hours_in_sample[h] )
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: baseload[t]} ( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
		* gen_availability[t] * heat_rate[t] * carbon_content[fuel[t]] * hours_in_sample[h] )
	# Carbon emissions from existing plants
	+ ( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS } ProducePowerEP[pid, a, t, p, h] * ep_heat_rate[pid, a, t] * carbon_content[fuel[t]] * hours_in_sample[h] )
  	<= carbon_cap[p];


#################################################
# Power conservation constraints

# System needs to meet the load in each load area in each study hour, with all available flows of power.
subject to Satisfy_Load {a in LOAD_AREAS, h in TIMEPOINTS}:
	 ( sum{ fc in RPS_FUEL_CATEGORY} ( ConsumeNonDistributedPower[a,h,fc] + ConsumeDistributedPower[a,h,fc] ) )
		 = system_load[a, h] ;

# non-distributed power production experiences distribution losses
# and can be consumed, stored or transmitted or spilled (hence the <=).
subject to Conservation_Of_Energy_NonDistributed {a in LOAD_AREAS, h in TIMEPOINTS, fc in RPS_FUEL_CATEGORY}:
  ConsumeNonDistributedPower[a,h,fc] * (1 + distribution_losses)
  <= 
  (
	# power redirected from distributed sources to the larger grid
    RedirectDistributedPower[a,h,fc]
	# power produced from new non-battery-storage projects  
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t] and rps_fuel_category_tech[t] = fc} DispatchGen[pid, a, t, p, h] )
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: intermittent[t] and t not in SOLAR_DIST_PV_TECHNOLOGIES and rps_fuel_category_tech[t] = fc }
		( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
			* cap_factor[pid, a, t, h] * gen_availability[t] )
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: baseload[t] and rps_fuel_category_tech[t] = fc }
		( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
			* gen_availability[t] )
	# power from new storage
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t]} ( ReleaseEnergy[pid, a, t, p, h, fc] - StoreEnergy[pid, a, t, p, h, fc] ) )
	# power produced from exiting plants
	+ ( sum { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: rps_fuel_category_tech[t] = fc and t not in SOLAR_DIST_PV_TECHNOLOGIES} ProducePowerEP[pid, a, t, p, h] )
	# power from existing (pumped hydro) storage
 	+ ( sum { (a, t, p, h) in PUMPED_HYDRO_AVAILABLE_HOURS} ( Dispatch_Pumped_Hydro_Storage[a, t, p, h, fc] - Store_Pumped_Hydro[a, t, p, h, fc] ) )
	# transmission in and out of each load area
	+ ( sum {(a2, a) in TRANSMISSION_LINES} DispatchTransFromXToY[a2, a, h, fc] * transmission_efficiency[a2, a] )
	- ( sum {(a, a1) in TRANSMISSION_LINES} DispatchTransFromXToY[a, a1, h, fc] )
  	);

# distributed power production doesn't experience distribution losses
# and must be either consumed immediately on site
# or added to the transmission-level power mix of a load area, incurring distribution losses going out of the distribution network
subject to Conservation_Of_Energy_Distributed {a in LOAD_AREAS, h in TIMEPOINTS, fc in RPS_FUEL_CATEGORY}:
  ConsumeDistributedPower[a,h,fc] + RedirectDistributedPower[a,h,fc] * (1 + distribution_losses)
  <= 
	  (sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: t in SOLAR_DIST_PV_TECHNOLOGIES and rps_fuel_category_tech[t] = fc}
          ( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
          	* gen_availability[t] * cap_factor[pid, a, t, h])
	+ (sum {(pid, a, t, p, h) in EP_AVAILABLE_HOURS: t in SOLAR_DIST_PV_TECHNOLOGIES and rps_fuel_category_tech[t] = fc}
   	      ep_capacity_mw[pid, a, t] * gen_availability[t] * eip_cap_factor[pid, a, t, h] ) 
  ;


################################################################################
# same on a reserve basis
# note: these are not derated by forced outage rate, because that is incorporated in the reserve margin
subject to Satisfy_Load_Reserve {a in LOAD_AREAS, h in TIMEPOINTS}:
	( ConsumeNonDistributedPower_Reserve[a,h] + ConsumeDistributedPower_Reserve[a,h] )
	=
	( 1 + planning_reserve_margin ) * system_load[a, h]
	;


subject to Conservation_Of_Energy_NonDistributed_Reserve {a in LOAD_AREAS, h in TIMEPOINTS}:
  ( ConsumeNonDistributedPower_Reserve[a,h] * (1 + distribution_losses) )
  <= 
  (
  # power redirected from distributed sources to the larger grid
    RedirectDistributedPower_Reserve[a,h]
	#    NEW PLANTS
  # new dispatchable capacity (no need to decide how to dispatch it; we just need to know it's available)
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t] and not storage[t]}
		( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] ) )
  # output from new intermittent projects. 
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: intermittent[t] and t not in SOLAR_DIST_PV_TECHNOLOGIES} 
		( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
			* cap_factor[pid, a, t, h] )
  # new baseload plants
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: baseload[t]} 
		( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
			* ( 1 - scheduled_outage_rate[t] ) )
  # new storage projects
	+ ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t]} (
		ReleaseEnergy_Reserve[pid, a, t, p, h] - StoreEnergy_Reserve[pid, a, t, p, h] ) )
	#############################
	#    EXISTING PLANTS
  # existing dispatchable capacity
	+ ( sum {(pid, a, t, p, h) in EP_AVAILABLE_HOURS: dispatchable[t]}
		OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] )
  # existing intermittent plants
	+ ( sum {(pid, a, t, p, h) in EP_AVAILABLE_HOURS: intermittent[t] and t not in SOLAR_DIST_PV_TECHNOLOGIES} 
		eip_cap_factor[pid, a, t, h] * ep_capacity_mw[pid, a, t] )
  # existing baseload plants
	+ ( sum {(pid, a, t, p, h) in EP_AVAILABLE_HOURS: baseload[t]} 
		OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] * ( 1 - scheduled_outage_rate[t] ) )
	#	HYDRO
  # non-storage hydro dispatch (includes pumped storage watershed electrons)
	+ ( sum {(a, t, p, h) in HYDRO_AVAILABLE_HOURS}
		DispatchHydro_Reserve[a, t, p, h] )
  # pumped hydro storage and dispatch
	+ ( sum {(a, t, p, h) in PUMPED_HYDRO_AVAILABLE_HOURS} (
		Dispatch_Pumped_Hydro_Storage_Reserve[a, t, p, h] - Store_Pumped_Hydro_Reserve[a, t, p, h] ) )
	########################################
	#    TRANSMISSION
  # Imports (have experienced transmission losses)
	+ ( sum {(a2, a) in TRANSMISSION_LINES}
		DispatchTransFromXToY_Reserve[a2, a, h] * transmission_efficiency[a2, a])
  # Exports (have not experienced transmission losses)
	- ( sum {(a, a1) in TRANSMISSION_LINES}
		DispatchTransFromXToY_Reserve[a, a1, h] )
	);


subject to Conservation_Of_Energy_Distributed_Reserve {a in LOAD_AREAS, h in TIMEPOINTS}:
  ConsumeDistributedPower_Reserve[a, h] + RedirectDistributedPower_Reserve[a, h] * (1 + distribution_losses)
  <= 
	  ( sum {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: t in SOLAR_DIST_PV_TECHNOLOGIES}
          ( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
          	* cap_factor[pid, a, t, h] )
	+ ( sum {(pid, a, t, p, h) in EP_AVAILABLE_HOURS: t in SOLAR_DIST_PV_TECHNOLOGIES}
   	      eip_cap_factor[pid, a, t, h] * ep_capacity_mw[pid, a, t] ) 
  ;


################################################################################
# GENERATOR OPERATIONAL CONSTRAINTS

# system can only dispatch as much of each project as is EXPECTED to be available
# i.e., we only dispatch up to gen_availability[t], so the system will work on an expected-value basis
subject to Power_From_Dispatchable_Plants 
	{(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: dispatchable[t]}:
	DispatchGen[pid, a, t, p, h] <=
		( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
			* gen_availability[t];

subject to EP_Operational_Continuity {(pid, a, t, p) in EP_PERIODS: p > first(PERIODS) and not intermittent[t] and not hydro[t]}:
	OperateEPDuringPeriod[pid, a, t, p] <= OperateEPDuringPeriod[pid, a, t, prev(p, PERIODS)];

# existing dispatchable plants can only be used if they are operational this period
subject to EP_Power_From_Dispatchable_Plants { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: dispatchable[t] }:
	ProducePowerEP[pid, a, t, p, h] <= 
		OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] * gen_availability[t];

# existing intermittent plants are kept operational until their end of life, with no option to extend life
subject to EP_Power_From_Intermittent_Plants { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: intermittent[t] }: 
	ProducePowerEP[pid, a, t, p, h] = ep_capacity_mw[pid, a, t] * eip_cap_factor[pid, a, t, h] * gen_availability[t];

# existing baseload plants are operational if OperateEPDuringPeriod is 1.
subject to EP_Power_From_Baseload_Plants { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: baseload[t] }: 
    ProducePowerEP[pid, a, t, p, h] = OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] * gen_availability[t];

# hydro dispatch is done on a load area basis, but it's helpful to have plant level decision variables
# so the load area variables are apportioned to each plant by capacity (this assumes that each plant operates similarly)
# DispatchHydro is derated by gen_availability[t] in the hydro constraints below
subject to EP_Power_From_Hydro_Plants { (pid, a, t, p, h) in EP_AVAILABLE_HOURS: hydro[t] }: 
	ProducePowerEP[pid, a, t, p, h] = DispatchHydro[a, t, p, h] * ( ep_capacity_mw[pid, a, t] / hydro_capacity_mw_in_load_area[a, t] );

########################################
# GENERATOR INSTALLATION CONSTRAINTS           
# there are limits on total installations in certain projects
# for solar, these are in the form of land area
# for bio, these are in MMBtu/hr which is then converted into MW via the heat rate
# (capacity_limit_conversion=(1/heat_rate for proposed_projects)
subject to Maximum_Resource_Competing_Tech {p in PERIODS, (l, a) in LOCATIONS_WITH_COMPETING_TECHNOLOGIES}:
	( sum { (pid, a, t, p) in PROJECT_VINTAGES: competes_for_space[t] and project_location[pid, a, t] = l } 
		( ( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
			* ( if ( fuel[t] = 'Bio_Solid' or fuel[t] = 'Bio_Liquid' or fuel[t] = 'Bio_Gas' )
				then gen_availability[t] else 1 )
		/ capacity_limit_conversion[pid, a, t] ) )
	+ ( sum { (pid, a, t, p) in EP_PERIODS: competes_for_space[t] and ep_location_id[pid, a, t] = l
			and ( fuel[t] = 'Bio_Solid' or fuel[t] = 'Bio_Liquid' or fuel[t] = 'Bio_Gas' ) } 
		( OperateEPDuringPeriod[pid, a, t, p] * ep_capacity_mw[pid, a, t] * gen_availability[t] * ep_heat_rate[pid, a, t] ) )
		 <= capacity_limit_by_location[l, a];

subject to Maximum_Resource_Location_Unspecified { (pid, a, t, p) in PROJECT_VINTAGES: resource_limited[t] and not competes_for_space[t] }:
  ( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] ) <= capacity_limit[pid, a, t] * capacity_limit_conversion[pid, a, t];

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
# TRANSMISSION AND LOCAL T&D CONSTRAINTS

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

# Simple fix to the problem of asymetrical transmission build-out
subject to SymetricalTrans
  {(a1, a2) in TRANSMISSION_LINES_NEW_BUILDS_ALLOWED, p in PERIODS }: InstallTrans[a1, a2, p] = InstallTrans[a2, a1, p];


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
	# transmission out of Baja Mexico
	sum { (a, a1) in TRANSMISSION_LINES, h in TIMEPOINTS, fc in RPS_FUEL_CATEGORY: period[h] = p }
		DispatchTransFromXToY[a, a1, h, fc] * hours_in_sample[h]
	# transmission into Baja Mexico
	- sum { (a1, a) in TRANSMISSION_LINES, h in TIMEPOINTS, fc in RPS_FUEL_CATEGORY: period[h] = p }
		DispatchTransFromXToY[a1, a, h, fc] * transmission_efficiency[a1, a] * hours_in_sample[h]
	<=
	mex_baja_export_limit_mwh[p];

# same on a reserve basis such that mexico doesn't export large amounts of reserve without actually exporting power (via Mexican_Export_Limit)
subject to Mexican_Export_Limit_Reserve
  { a in LOAD_AREAS, p in PERIODS: a = 'MEX_BAJA' }:
	# transmission out of Baja Mexico
	sum { (a, a1) in TRANSMISSION_LINES, h in TIMEPOINTS: period[h] = p }
		DispatchTransFromXToY_Reserve[a, a1, h] * hours_in_sample[h]
	# transmission into Baja Mexico
	- sum { (a1, a) in TRANSMISSION_LINES, h in TIMEPOINTS: period[h] = p }
		DispatchTransFromXToY_Reserve[a1, a, h] * transmission_efficiency[a1, a] * hours_in_sample[h]
	<=
	mex_baja_export_limit_mwh[p] * ( 1 + planning_reserve_margin );


#################################
# Installable (non pumped hydro) Storage constraints

# Energy output from CAES plants is apportioned into two separate decision variables:
# DispatchGen for the power attributable to NG combustion and ReleaseEnergy for the power attributable to stored energy.
# The ratio of NG:Stored is fixed at plant design and this constraint enforces that relationship. 
subject to CAES_Combined_Dispatch { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: t = 'Compressed_Air_Energy_Storage' }:
  	(sum {fc in RPS_FUEL_CATEGORY} ReleaseEnergy[pid, a, t, p, h, fc] ) = 
  	  DispatchGen[pid, a, t, p, h] * caes_storage_to_ng_ratio[t];
 
# Maximum store rate, derated for occasional forced outages
# StoreEnergy represents the load on the grid from storing electrons
subject to Maximum_Store_Rate {(pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t]}:
  	sum {fc in RPS_FUEL_CATEGORY} StoreEnergy[pid, a, t, p, h, fc]
  		<= ( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
  				* max_store_rate[t] * gen_availability[t];

# Maximum dispatch rate, derated for occasional forced outages
# CAES dispatch is apportioned between DispatchGen and ReleaseEnergy for NG and stored energy respectivly
# while other storage projects (currently only Battery_Storage) don't have input energy other than grid electricity
subject to Maximum_Release_Storage_Rate { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t] }:
  	(sum {fc in RPS_FUEL_CATEGORY} ReleaseEnergy[pid, a, t, p, h, fc] ) +
  		( if t = 'Compressed_Air_Energy_Storage' then DispatchGen[pid, a, t, p, h] else 0 )
  		<= ( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] )
  				* gen_availability[t];

  # Energy balance
  # The parameter round_trip_efficiency below expresses the relationship between the amount of electricity from the grid used
  # to charge the storage device and the amount that is dispatched back to the grid.
  # For hybrid technologies like compressed-air energy storage (CAES), the round-trip efficiency will be higher than 1
  # because natural gas is added to run the turbine. For CAES, this parameter is therefore only a "partial energy balance,"
  # i.e. only one form of energy -- electricity -- is included in the balancing.
  # The input of natural gas is handeled in CAES_Combined_Dispatch above
  
  # ReleaseEnergy and StoreEnergy are derated for forced outages in Maximum_Storage_Dispatch_Rate and Maximum_Store_Rate respectivly
subject to Storage_Projects_Energy_Balance {(pid, a, t, p) in PROJECT_VINTAGES, d in DATES, fc in RPS_FUEL_CATEGORY: storage[t] and period_of_date[d] = p}:
  	sum {h in TIMEPOINTS: date[h] = d} ReleaseEnergy[pid, a, t, p, h, fc]
  		<= sum {h in TIMEPOINTS: date[h] = d} StoreEnergy[pid, a, t, p, h, fc] * storage_efficiency[t];

# RESERVE - the same as above on a reserve margin basis
subject to Maximum_Store_Rate_Reserve { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t] }:
  	StoreEnergy_Reserve[pid, a, t, p, h]
  		<= max_store_rate[t] * ( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] );
subject to Maximum_Release_Storage_Rate_Reserve { (pid, a, t, p, h) in PROJECT_VINTAGE_HOURS: storage[t] }:
  	ReleaseEnergy_Reserve[pid, a, t, p, h]
  		<= ( sum { (pid, a, t, install_yr, p) in PROJECT_VINTAGE_INSTALLED_PERIODS } InstallGen[pid, a, t, install_yr] );
# all energy from CAES in the reserve margin is coming from ReleaseEnergy_Reserve, with the use of natural gas included.
subject to Storage_Projects_Energy_Balance_Reserve {(pid, a, t, p) in PROJECT_VINTAGES, d in DATES: storage[t] and period_of_date[d] = p}:
  	sum {h in TIMEPOINTS: date[h] = d} ReleaseEnergy_Reserve[pid, a, t, p, h]
  		<= sum {h in TIMEPOINTS: date[h] = d} StoreEnergy_Reserve[pid, a, t, p, h]
  			* ( if t = 'Compressed_Air_Energy_Storage' then round_trip_efficiency_caes else storage_efficiency[t] );


################################################################################
# HYDRO CONSTRAINTS

# The variable Store_Pumped_Hydro represents the MW of electricity required to pump water uphill (the load on the grid from pumping)
# To represent efficiency losses, the electrons stored by Store_Pumped_Hydro are then derated by the storage_efficiency[t] when dispatched
# so the stock of MW available to be dispatched from pumping hydro projects 
# is anything already in the upstream flow (ProducePowerEP) plus Store_Pumped_Hydro * storage_efficiency[t]

# RPS for Pumped Hydro storage: electrons come in three RPS colors:
# any electron that is from upstream gets labeled blue - i.e. whatever color hydro is... currently this equates to brown
# also, any stored electron (less the storage_efficiency[t]) must retain its color - either brown or green 

# for every hour, the amount of water released can't be more than the turbine capacity
subject to Maximum_Dispatch_Hydro { (a, t, p, h) in HYDRO_AVAILABLE_HOURS }:
 	DispatchHydro[a, t, p, h]
	+ 
	(if t = 'Hydro_Pumped'
		then ( sum{ fc in RPS_FUEL_CATEGORY } Dispatch_Pumped_Hydro_Storage[a, t, p, h, fc] )
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
subject to Average_Hydro_Output { (a, t, p, d) in HYDRO_DATES }:
  sum {h in TIMEPOINTS: date[h]=d} DispatchHydro[a, t, p, h] <= 
# The sum below is equivalent to the daily hydro flow, but only over the study hours considered in each day
  sum {h in TIMEPOINTS: date[h]=d} avg_hydro_output_load_area_agg[a, t, p, d];

# Can't pump more water uphill than the pump capacity (in MW)
# As mentioned above, Store_Pumped_Hydro represents the grid load of storage
# so the storage efficiency is taken into account in dispatch
# TODO: Research how MW pumping capacity translates into water flows - 
# it's unclear whether these pumps can only take their capacity_mw in load,
# or if they can take capacity_mw / storage_efficiency[t] in load thereby storing their capacity_mw uphill.
# We'll take the conservative assumption here that they can only store capacity_mw * storage_efficiency[t]
subject to Maximum_Store_Pumped_Hydro { (a, t, p, h) in PUMPED_HYDRO_AVAILABLE_HOURS }:
  sum {fc in RPS_FUEL_CATEGORY} Store_Pumped_Hydro[a, t, p, h, fc] <= hydro_capacity_mw_in_load_area[a, t] * gen_availability[t] ;

# Conservation of STORED electrons (electrons not from upstream) for pumped hydro
# Pumped hydro has to dispatch all electrons it stored each day for each fuel type such that 
# over the course of a day pumped hydro projects release the necessary amount of water downstream
subject to Conservation_Of_Stored_Pumped_Hydro_Electrons { (a, t, p, d) in PUMPED_HYDRO_DATES, fc in RPS_FUEL_CATEGORY }:
	sum {h in TIMEPOINTS: date[h]=d} Dispatch_Pumped_Hydro_Storage[a, t, p, h, fc] <= 
	sum {h in TIMEPOINTS: date[h]=d} Store_Pumped_Hydro[a, t, p, h, fc] * storage_efficiency[t];


# Hydro Reserve
# This is an independent operational plan for hydro that can ensure average flow rates while maintain a reserve margin.
# This contigency plan is overkill for short-lived events (hours) that require tapping into the reserve margin.
# This contigency plan is needed for long-lasting events (days or weeks) that require maintenance of average stream flow.

# as the amount of reserve available from hydro plants isn't infinite,
# the reserve must be dispatched on similar terms to the actual energy dispatch

# as the reserve margin doesn't have an RPS flavor, these constraints don't include the fuel type

# as with other reserve margin constraints, gen_availability is removed here, because this is built into the reserve margin
subject to Maximum_Dispatch_Hydro_Reserve { (a, t, p, h) in HYDRO_AVAILABLE_HOURS }:
 	DispatchHydro_Reserve[a, t, p, h]
	+ 
	(if t = 'Hydro_Pumped'
		then Dispatch_Pumped_Hydro_Storage_Reserve[a, t, p, h]
		else 0 )
    <= hydro_capacity_mw_in_load_area[a, t];
subject to Minimum_Dispatch_Hydro_Reserve { (a, t, p, h) in NONPUMPED_HYDRO_AVAILABLE_HOURS }:
  DispatchHydro_Reserve[a, t, p, h] >= avg_hydro_output_load_area_agg[a, t, p, date[h]] * min_nonpumped_hydro_dispatch_fraction;
subject to Average_Hydro_Output_Reserve { (a, t, p, d) in HYDRO_DATES }:
  sum {h in TIMEPOINTS: date[h]=d} DispatchHydro_Reserve[a, t, p, h] <= 
  sum {h in TIMEPOINTS: date[h]=d} avg_hydro_output_load_area_agg[a, t, p, d];

# hydro reserve storage constraints
subject to Conservation_Of_Stored_Pumped_Hydro_Electrons_Reserve { (a, t, p, d) in PUMPED_HYDRO_DATES }:
	sum {h in TIMEPOINTS: date[h]=d} Dispatch_Pumped_Hydro_Storage_Reserve[a, t, p, h] <= 
	sum {h in TIMEPOINTS: date[h]=d} Store_Pumped_Hydro_Reserve[a, t, p, h] * storage_efficiency[t];
# Can't pump more water uphill than the pump capacity (in MW)
subject to Maximum_Store_Pumped_Hydro_Reserve { (a, t, p, h) in PUMPED_HYDRO_AVAILABLE_HOURS }:
  Store_Pumped_Hydro_Reserve[a, t, p, h] <= hydro_capacity_mw_in_load_area[a, t];



problem Investment_Cost_Minimization: 
  # Objective function 
	Power_Cost, 

  # Satisfy Load and Power Consumption
    Satisfy_Load,
	Conservation_Of_Energy_NonDistributed, Conservation_Of_Energy_Distributed,
    ConsumeNonDistributedPower, ConsumeDistributedPower, RedirectDistributedPower,
  # Policy Constraints
	Satisfy_RPS, Carbon_Cap,

  # Investment Decisions
	InstallGen, BuildGenOrNot, InstallTrans, 
  # Installation Constraints
	Maximum_Resource_Competing_Tech, Maximum_Resource_Location_Unspecified, Minimum_GenSize, BuildGenOrNot_Constraint, SymetricalTrans, 

  # Dispatch Decisions
	DispatchGen, OperateEPDuringPeriod, ProducePowerEP, ConsumeBioSolid, DispatchTransFromXToY, StoreEnergy, ReleaseEnergy,
	DispatchHydro, Dispatch_Pumped_Hydro_Storage, Store_Pumped_Hydro,
  # Dispatch Constraints
	Power_From_Dispatchable_Plants,
	EP_Operational_Continuity, EP_Power_From_Dispatchable_Plants, EP_Power_From_Intermittent_Plants, EP_Power_From_Baseload_Plants, EP_Power_From_Hydro_Plants,
	Maximum_DispatchTransFromXToY, Maximum_DispatchTransFromXToY_Reserve, 
	Mexican_Export_Limit, Mexican_Export_Limit_Reserve, 
	Maximum_Dispatch_Hydro, Minimum_Dispatch_Hydro, Average_Hydro_Output, 
	Maximum_Store_Pumped_Hydro, Conservation_Of_Stored_Pumped_Hydro_Electrons,
	CAES_Combined_Dispatch, Maximum_Store_Rate, Maximum_Release_Storage_Rate, Storage_Projects_Energy_Balance, 

  # Contigency Planning Variables (to ensure that a dispatch plan exists that can meet reserve margins)
	DispatchTransFromXToY_Reserve, StoreEnergy_Reserve, ReleaseEnergy_Reserve, 
	DispatchHydro_Reserve, Dispatch_Pumped_Hydro_Storage_Reserve, Store_Pumped_Hydro_Reserve, 
  # Contigency Planning constraints
	Satisfy_Load_Reserve, 
	Conservation_Of_Energy_NonDistributed_Reserve, Conservation_Of_Energy_Distributed_Reserve,
    ConsumeNonDistributedPower_Reserve, ConsumeDistributedPower_Reserve, RedirectDistributedPower_Reserve,
  # Dispatch Reserve Constraints
	Maximum_Dispatch_Hydro_Reserve, Average_Hydro_Output_Reserve, Minimum_Dispatch_Hydro_Reserve, 
	Maximum_Store_Pumped_Hydro_Reserve, Conservation_Of_Stored_Pumped_Hydro_Electrons_Reserve,
	Maximum_Store_Rate_Reserve, Maximum_Release_Storage_Rate_Reserve, Storage_Projects_Energy_Balance_Reserve
;

problem Present_Day_Cost_Minimization: 
  # Objective function 
	Power_Cost, 
  # Satisfy Load and Power Consumption
    Satisfy_Load,
	Conservation_Of_Energy_NonDistributed, Conservation_Of_Energy_Distributed,
    ConsumeNonDistributedPower, ConsumeDistributedPower, RedirectDistributedPower,
  # Installation Decisions - only gas combustion turbines for the present day optimization
	{(pid, a, t, p) in PROJECT_VINTAGES: t='Gas_Combustion_Turbine'} InstallGen[pid, a, t, p], 
  # Dispatch Decisions
	DispatchGen, ProducePowerEP, ConsumeBioSolid, DispatchTransFromXToY,
	{(pid, a, t, p) in EP_PERIODS: not intermittent[t] and not hydro[t] and ep_could_be_operating_past_expected_lifetime[pid, a, t, p]} OperateEPDuringPeriod[pid, a, t, p],
	DispatchHydro, Dispatch_Pumped_Hydro_Storage, Store_Pumped_Hydro,
  # Dispatch Constraints
	Power_From_Dispatchable_Plants,
	EP_Power_From_Dispatchable_Plants, EP_Power_From_Intermittent_Plants, EP_Power_From_Baseload_Plants, EP_Power_From_Hydro_Plants,
	Maximum_DispatchTransFromXToY,
	Maximum_Dispatch_Hydro, Average_Hydro_Output, Minimum_Dispatch_Hydro, 
	Maximum_Store_Pumped_Hydro, Conservation_Of_Stored_Pumped_Hydro_Electrons
;


