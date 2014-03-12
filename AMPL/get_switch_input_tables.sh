#!/bin/bash

function print_help {
  echo $0 # The name of this file. 
  cat <<END_HELP
SYNOPSIS
		./get_switch_input_tables.sh 
DESCRIPTION
	Pull input data for Switch from databases and other sources, formatting it for AMPL
This script assumes that the input database has already been built by the script 'Build WECC Cap Factors.sql'

INPUTS
 --help                   Print this message
 -t | --tunnel            Initiate an ssh tunnel to connect to the database. This won't work if ssh prompts you for your password.
 -u [DB Username]
 -p [DB Password]
 -D [DB name]
 -P/--port [port number]
 -h [DB server]
All arguments are optional.
END_HELP
}


# Export SWITCH input data from the Switch inputs database into text files that will be read in by AMPL
# This script assumes that the input database has already been built by the script 'Build WECC Cap Factors.sql'

write_to_path='inputs'

db_server="switch-db2.erg.berkeley.edu"
DB_name="switch_inputs_wecc_v2_2"
port=3306
ssh_tunnel=1

# Set the umask to give group read & write permissions to all files & directories made by this script.
umask 0002

###################################################
# Detect optional command-line arguments
help=0
while [ -n "$1" ]; do
case $1 in
  -t | --tunnel)
    ssh_tunnel=1; shift 1 ;;
  -u)
    user=$2; shift 2 ;;
  -p)
    password=$2; shift 2 ;;
  -P)
    port=$2; shift 2 ;;
  --port)
    port=$2; shift 2 ;;
  -D)
    DB_name=$2; shift 2 ;;
  -h)
    db_server=$2; shift 2 ;;
  --help)
		print_help; exit ;;
  *)
    echo "Unknown option $1"
		print_help; exit 0 ;;
esac
done

##########################
# Get the user name and password 
# Note that passing the password to mysql via a command line parameter is considered insecure
#	http://dev.mysql.com/doc/refman/5.0/en/password-security.html
default_user=$(whoami)
if [ ! -n "$user" ]
then 
	printf "User name for MySQL $DB_name on $db_server [$default_user]? "
	read user
	if [ -z "$user" ]; then 
	  user="$default_user"
	fi
fi
if [ ! -n "$password" ] 
then 
	printf "Password for MySQL $DB_name on $db_server? "
	stty_orig=`stty -g`   # Save screen settings
	stty -echo            # To keep the password vaguely secure, don't let it show to the screen
	read password
	stty $stty_orig       # Restore screen settings
	echo " "
fi

function clean_up {
  [ $ssh_tunnel -eq 1 ] && kill -9 $ssh_pid # This ensures that the ssh tunnel will be taken down if the program exits abnormally
  unset password
}

function is_port_free {
  target_port=$1
  if [ $(netstat -ant | \
         sed -e '/^tcp/ !d' -e 's/^[^ ]* *[^ ]* *[^ ]* *.*[\.:]\([0-9]*\) .*$/\1/' | \
         sort -g | uniq | \
         grep $target_port | wc -l) -eq 0 ]; then
    return 1
  else
    return 0
  fi
}

#############
# Try starting an ssh tunnel if requested
if [ $ssh_tunnel -eq 1 ]; then 
  echo "Trying to open an ssh tunnel. If it prompts you for your password, this method won't work."
  local_port=3307
  is_port_free $local_port
  while [ $? -eq 0 ]; do
    local_port=$((local_port+1))
    is_port_free $local_port
  done
  ssh -N -p 22 -c 3des "$user"@"$db_server" -L $local_port/127.0.0.1/$port &
  ssh_pid=$!
  sleep 1
  connection_string="-h 127.0.0.1 --port $local_port -u $user -p$password $DB_name"
  trap "clean_up;" EXIT INT TERM 
else
  connection_string="-h $db_server --port $port -u $user -p$password $DB_name"
fi

test_connection=`mysql $connection_string --column-names=false -e "select count(*) from existing_plants;"`
if [ ! -n "$test_connection" ] && [ $ssh_tunnel -eq 1 ]; then
        echo "First DB connection attempt failed. This sometimes happens if the ssh tunnel initiation is slow. Waiting 5 seconds, then will try again."
        sleep 5;
        test_connection=`mysql $connection_string --column-names=false -e "select count(*) from existing_plants;"`
fi
  
if [ ! -n "$test_connection" ]; then
	connection_string=`echo "$connection_string" | sed -e "s/ -p[^ ]* / -pXXX /"`
	echo "Could not connect to database with settings: $connection_string"
	exit 0
fi


###########################
# These next variables determine which input data is used

# get the present year that will make present day cost optimization possible
present_year=`date "+%Y"`

INTERMITTENT_PROJECTS_SELECTION="(( avg_cap_factor_percentile_by_intermittent_tech >= 0.75 or cumulative_avg_MW_tech_load_area <= 3 * total_yearly_load_mwh / 8766 or rank_by_tech_in_load_area <= 5 or avg_cap_factor_percentile_by_intermittent_tech is null) and technology <> 'Concentrating_PV')"

read SCENARIO_ID < scenario_id.txt
# Make sure this scenario id is valid.
if [ $(mysql $connection_string --column-names=false -e "select count(*) from scenarios_v3 where scenario_id=$SCENARIO_ID;") -eq 0 ]; then 
	echo "ERROR! This scenario id ($SCENARIO_ID) is not in the database. Exiting."
	exit 0;
fi

export REGIONAL_MULTIPLIER_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select regional_cost_multiplier_scenario_id from scenarios_v3 where scenario_id=$SCENARIO_ID;")
export REGIONAL_FUEL_COST_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select regional_fuel_cost_scenario_id from scenarios_v3 where scenario_id=$SCENARIO_ID;")
export GEN_COSTS_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select gen_costs_scenario_id from scenarios_v3 where scenario_id=$SCENARIO_ID;")
export GEN_INFO_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select gen_info_scenario_id from scenarios_v3 where scenario_id=$SCENARIO_ID;")
export CARBON_CAP_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select carbon_cap_scenario_id from scenarios_v3 where scenario_id=$SCENARIO_ID;")
export SCENARIO_NAME=$(mysql $connection_string --column-names=false -e "select scenario_name from scenarios_v3 where scenario_id=$SCENARIO_ID;")
export TRAINING_SET_ID=$(mysql $connection_string --column-names=false -e "select training_set_id from scenarios_v3 where scenario_id = $SCENARIO_ID;")
export LOAD_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select load_scenario_id from training_sets where training_set_id = $TRAINING_SET_ID;")
export ENABLE_RPS=$(mysql $connection_string --column-names=false -e "select enable_rps from scenarios_v3 where scenario_id=$SCENARIO_ID;")
export ENABLE_CARBON_CAP=$(mysql $connection_string --column-names=false -e "select if(carbon_cap_scenario_id>0,1,0) from scenarios_v3 where scenario_id=$SCENARIO_ID;")
export NEMS_FUEL_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select nems_fuel_scenario_id from scenarios_v3 where scenario_id=$SCENARIO_ID;")
export DR_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select dr_scenario_id from scenarios_v3 where scenario_id=$SCENARIO_ID;")
export EV_SCENARIO_ID=$(mysql $connection_string --column-names=false -e "select ev_scenario_id from scenarios_v3 where scenario_id=$SCENARIO_ID;")
export ENFORCE_CA_DG_MANDATE=$(mysql $connection_string --column-names=false -e "select enforce_ca_dg_mandate from scenarios_v3 where scenario_id=$SCENARIO_ID;")
export LINEARIZE_OPTIMIZATION=$(mysql $connection_string --column-names=false -e "select linearize_optimization from scenarios_v3 where scenario_id=$SCENARIO_ID;")
export STUDY_START_YEAR=$(mysql $connection_string --column-names=false -e "select study_start_year from training_sets where training_set_id=$TRAINING_SET_ID;")
export STUDY_END_YEAR=$(mysql $connection_string --column-names=false -e "select study_start_year + years_per_period*number_of_periods from training_sets where training_set_id=$TRAINING_SET_ID;")
export transmission_capital_cost_per_mw_km=$(mysql $connection_string --column-names=false -e "select transmission_capital_cost_per_mw_km from scenarios_v3 where scenario_id = $SCENARIO_ID;")
number_of_years_per_period=$(mysql $connection_string --column-names=false -e "select years_per_period from training_sets where training_set_id=$TRAINING_SET_ID;")

# Find the minimum historical year used for this training set. 
# Scenarios based on 2006 data need to draw from newer tables
# Scenarios based on 2004-05 data need to draw from older tables
min_historical_year=$(mysql $connection_string --column-names=false -e "\
  SELECT historical_year \
  FROM _training_set_timepoints \
    JOIN load_scenario_historic_timepoints USING(timepoint_id) \
    JOIN hours ON(historic_hour=hournum) \
  WHERE training_set_id=$TRAINING_SET_ID \
    AND load_scenario_id = $LOAD_SCENARIO_ID \
  ORDER BY hournum ASC \
  LIMIT 1;")
if [ $min_historical_year -eq 2004 ]; then 
  cap_factor_table="_cap_factor_intermittent_sites"
  proposed_projects_table="_proposed_projects_v2"
  proposed_projects_view="proposed_projects_v2"
elif [ $min_historical_year -eq 2006 ]; then 
  cap_factor_table="_cap_factor_intermittent_sites_v2"
  proposed_projects_table="_proposed_projects_v3"
  proposed_projects_view="proposed_projects_v3"
else
  echo "Unexpected training set timepoints! Min_historical_year is $min_historical_year. Exiting."
  exit 0
fi

###########################
# Export data to be read into ampl.

mkdir -p $write_to_path
cd $write_to_path

echo 'Exporting Scenario Information'
echo 'Scenario Information' > scenario_information.txt
mysql $connection_string -e "select * from scenarios_v3 where scenario_id = $SCENARIO_ID;" >> scenario_information.txt
echo 'Training Set Information' >> scenario_information.txt
mysql $connection_string -e "select * from training_sets where training_set_id=$TRAINING_SET_ID;" >> scenario_information.txt

# The general format for the following files is for the first line to be:
#	ampl.tab [number of key columns] [number of non-key columns]
# col1_name col2_name ...
# [rows of data]

echo 'Copying data from the database to input files...'

echo '	study_hours.tab...'
echo ampl.tab 1 5 > study_hours.tab
mysql $connection_string -e "\
SELECT \
  DATE_FORMAT(datetime_utc,'%Y%m%d%H') AS hour, period, \
  DATE_FORMAT(datetime_utc,'%Y%m%d') AS date, hours_in_sample, \
  MONTH(datetime_utc) AS month_of_year, HOUR(datetime_utc) as hour_of_day \
FROM _training_set_timepoints JOIN study_timepoints  USING (timepoint_id) \
WHERE training_set_id=$TRAINING_SET_ID order by 1;" >> study_hours.tab

echo '	load_areas.tab...'
echo ampl.tab 1 12 > load_areas.tab
mysql $connection_string -e "select load_area, area_id as load_area_id, primary_state, primary_nerc_subregion as balancing_area, rps_compliance_entity, economic_multiplier, max_coincident_load_for_local_td, local_td_new_annual_payment_per_mw, local_td_sunk_annual_payment, transmission_sunk_annual_payment, ccs_distance_km, bio_gas_capacity_limit_mmbtu_per_hour, nems_fuel_region from load_area_info;" >> load_areas.tab

echo '	balancing_areas.tab...'
echo ampl.tab 1 4 > balancing_areas.tab
mysql $connection_string -e "select balancing_area, load_only_spinning_reserve_requirement, wind_spinning_reserve_requirement, solar_spinning_reserve_requirement, quickstart_requirement_relative_to_spinning_reserve_requirement from balancing_areas;" >> balancing_areas.tab

echo '	rps_compliance_entity_targets.tab...'
echo ampl.tab 3 1 > rps_compliance_entity_targets.tab
mysql $connection_string -e "select rps_compliance_entity, rps_compliance_type, rps_compliance_year, rps_compliance_fraction from rps_compliance_entity_targets_v2 where enable_rps = $ENABLE_RPS AND rps_compliance_year >= $STUDY_START_YEAR and rps_compliance_year <= $STUDY_END_YEAR;" >> rps_compliance_entity_targets.tab

echo '	carbon_cap_targets.tab...'
echo ampl.tab 1 1 > carbon_cap_targets.tab
mysql $connection_string -e "select year, carbon_emissions_relative_to_base from carbon_cap_targets where year >= $STUDY_START_YEAR and year <= $STUDY_END_YEAR and carbon_cap_scenario_id=$CARBON_CAP_SCENARIO_ID;" >> carbon_cap_targets.tab

echo '	transmission_lines.tab...'
echo ampl.tab 2 8 > transmission_lines.tab
mysql $connection_string -e "select load_area_start, load_area_end, existing_transfer_capacity_mw, transmission_line_id, transmission_length_km, transmission_efficiency, new_transmission_builds_allowed, is_dc_line, transmission_derating_factor, terrain_multiplier from transmission_lines order by 1,2;" >> transmission_lines.tab

echo '	system_load.tab...'
echo ampl.tab 2 2 > system_load.tab
mysql $connection_string -e "call prepare_load_exports($TRAINING_SET_ID); select load_area, DATE_FORMAT(datetime_utc,'%Y%m%d%H') as hour, system_load, present_day_system_load from scenario_loads_export WHERE training_set_id=$TRAINING_SET_ID; call clean_load_exports($TRAINING_SET_ID); "  >> system_load.tab

if [ $DR_SCENARIO_ID == 'NULL' ]; then
	echo "No DR scenario specified. Skipping shiftable_res_comm_load.tab."
else 
	echo '	shiftable_res_comm_load.tab...'
	echo ampl.tab 2 2 > shiftable_res_comm_load.tab
	mysql $connection_string -e "call prepare_res_comm_shiftable_load_exports($TRAINING_SET_ID, $SCENARIO_ID); select load_area, DATE_FORMAT(datetime_utc,'%Y%m%d%H') as hour, shiftable_res_comm_load, shifted_res_comm_load_hourly_max from scenario_res_comm_shiftable_loads_export WHERE training_set_id=$TRAINING_SET_ID and scenario_id=$SCENARIO_ID; call clean_res_comm_shiftable_load_exports($TRAINING_SET_ID, $SCENARIO_ID);" >> shiftable_res_comm_load.tab;
fi;

if [ $EV_SCENARIO_ID == 'NULL' ]; then
	echo "No EV scenario specified. Skipping shiftable_ev_load.tab."
else 
	echo '	shiftable_ev_load.tab...'
	echo ampl.tab 2 2 > shiftable_ev_load.tab
	mysql $connection_string -e "call prepare_ev_shiftable_load_exports($TRAINING_SET_ID, $SCENARIO_ID); select load_area, DATE_FORMAT(datetime_utc,'%Y%m%d%H') as hour, shiftable_ev_load, shifted_ev_load_hourly_max from scenario_ev_shiftable_loads_export WHERE training_set_id=$TRAINING_SET_ID and scenario_id=$SCENARIO_ID; call clean_ev_shiftable_load_exports($TRAINING_SET_ID, $SCENARIO_ID);" >> shiftable_ev_load.tab;
fi;

echo '	max_system_loads.tab...'
echo ampl.tab 2 1 > max_system_loads.tab
mysql $connection_string -e "\
SELECT load_area, YEAR(now()) as period, max(power) as max_system_load \
  FROM _load_projections \
    JOIN training_sets USING(load_scenario_id) \
    JOIN load_area_info    USING(area_id) \
  WHERE training_set_id=$TRAINING_SET_ID AND future_year = YEAR(now())  \
  GROUP BY 1,2 \
UNION \
SELECT load_area, period_start as period, max(power) as max_system_load \
  FROM training_sets \
    JOIN _load_projections     USING(load_scenario_id)  \
    JOIN load_area_info        USING(area_id) \
    JOIN training_set_periods USING(training_set_id)  \
  WHERE training_set_id=$TRAINING_SET_ID  \
    AND future_year >= period_start \
    AND future_year <= FLOOR( period_start + years_per_period / 2) \
  GROUP BY 1,2; " >> max_system_loads.tab

echo '	existing_plants.tab...'
echo ampl.tab 3 11 > existing_plants.tab
mysql $connection_string -e "select project_id, load_area, technology, plant_name, eia_id, capacity_mw, heat_rate, cogen_thermal_demand_mmbtus_per_mwh, if(start_year = 0, 1900, start_year) as start_year, forced_retirement_year, overnight_cost, connect_cost_per_mw, fixed_o_m, variable_o_m from existing_plants_v2 order by 1, 2, 3;" >> existing_plants.tab

echo '	existing_intermittent_plant_cap_factor.tab...'
echo ampl.tab 4 1 > existing_intermittent_plant_cap_factor.tab
mysql $connection_string -e "\
SELECT project_id, load_area, technology, DATE_FORMAT(datetime_utc,'%Y%m%d%H') as hour, cap_factor \
FROM _training_set_timepoints \
  JOIN study_timepoints USING(timepoint_id) \
  JOIN load_scenario_historic_timepoints USING(timepoint_id) \
  JOIN existing_intermittent_plant_cap_factor ON(historic_hour=hour) \
WHERE training_set_id=$TRAINING_SET_ID AND load_scenario_id=$LOAD_SCENARIO_ID;\
" >> existing_intermittent_plant_cap_factor.tab

echo '	hydro_monthly_limits.tab...'
echo ampl.tab 4 1 > hydro_monthly_limits.tab
mysql $connection_string -e "\
CREATE TEMPORARY TABLE study_dates_export\
  SELECT DISTINCT month_of_year AS month, DATE_FORMAT(study_timepoints.datetime_utc,'%Y%m%d') AS study_date\
  FROM _training_set_timepoints \
    JOIN study_timepoints  USING (timepoint_id)\
  WHERE training_set_id=$TRAINING_SET_ID \
  ORDER BY 1,2;\
SELECT project_id, load_area, technology, study_date as date, ROUND(avg_capacity_factor_hydro,4) AS avg_capacity_factor_hydro\
  FROM hydro_monthly_limits_v2 \
    JOIN study_dates_export USING(month);" >> hydro_monthly_limits.tab

echo '	proposed_projects.tab...'
echo ampl.tab 3 8 > proposed_projects.tab
mysql $connection_string -e "select project_id, $proposed_projects_view.load_area, technology, if(location_id is NULL, 0, location_id) as location_id, if(ep_project_replacement_id is NULL, 0, ep_project_replacement_id) as ep_project_replacement_id, if(capacity_limit is NULL, 0, capacity_limit) as capacity_limit, if(capacity_limit_conversion is NULL, 0, capacity_limit_conversion) as capacity_limit_conversion, heat_rate, cogen_thermal_demand, connect_cost_per_mw, if(avg_cap_factor_intermittent is NULL, 0, avg_cap_factor_intermittent) as average_capacity_factor_intermittent from $proposed_projects_view join load_area_info using (area_id) where technology_id in (SELECT technology_id FROM generator_info_v2 where gen_info_scenario_id=$GEN_INFO_SCENARIO_ID) AND $INTERMITTENT_PROJECTS_SELECTION;" >> proposed_projects.tab

echo '	generator_info.tab...'
echo ampl.tab 1 32 > generator_info.tab
mysql $connection_string -e "select technology, technology_id, min_online_year, fuel, construction_time_years, year_1_cost_fraction, year_2_cost_fraction, year_3_cost_fraction, year_4_cost_fraction, year_5_cost_fraction, year_6_cost_fraction, max_age_years, forced_outage_rate, scheduled_outage_rate, can_build_new, ccs, intermittent, resource_limited, baseload, flexible_baseload, dispatchable, cogen, min_build_capacity, competes_for_space, storage, storage_efficiency, max_store_rate, max_spinning_reserve_fraction_of_capacity, heat_rate_penalty_spinning_reserve, minimum_loading, deep_cycling_penalty, startup_mmbtu_per_mw, startup_cost_dollars_per_mw from generator_info_v2 where gen_info_scenario_id=$GEN_INFO_SCENARIO_ID;" >> generator_info.tab

echo '	generator_costs.tab...'
echo ampl.tab 2 4 > generator_costs.tab
mysql $connection_string -e "select technology, period_start as period, overnight_cost, storage_energy_capacity_cost_per_mwh, fixed_o_m, var_o_m as variable_o_m_by_year \
from generator_costs_yearly \
join generator_info_v2 g using (technology), \
training_set_periods \
join training_sets using(training_set_id) \
where year = FLOOR( period_start + years_per_period / 2) - g.construction_time_years \
and period_start >= g.construction_time_years + $present_year \
and	period_start >= g.min_online_year \
and gen_costs_scenario_id=$GEN_COSTS_SCENARIO_ID \
and gen_info_scenario_id=$GEN_INFO_SCENARIO_ID \
and training_set_id=$TRAINING_SET_ID \
UNION \
select technology, $present_year as period, overnight_cost, storage_energy_capacity_cost_per_mwh, fixed_o_m, var_o_m as variable_o_m_by_year from generator_costs_yearly \
where year = $present_year \
and gen_costs_scenario_id=$GEN_COSTS_SCENARIO_ID \
order by technology, period;" >> generator_costs.tab

echo '	fuel_costs.tab...'
echo ampl.tab 3 1 > fuel_costs.tab
mysql $connection_string -e "select load_area, fuel, year, fuel_price from fuel_prices where scenario_id = $REGIONAL_FUEL_COST_SCENARIO_ID and year <= $STUDY_END_YEAR order by load_area, fuel, year;" >> fuel_costs.tab


echo '	ng_supply_curve.tab...'
echo ampl.tab 2 2 > ng_supply_curve.tab
mysql $connection_string -e "\
select period_start as period, breakpoint_id, consumption_breakpoint as ng_consumption_breakpoint, price_surplus_adjusted as ng_price_surplus_adjusted \
from natural_gas_supply_curve, training_set_periods \
join training_sets using(training_set_id) \
where simulation_year=FLOOR( period_start + years_per_period / 2) \
and nems_scenario = (select nems_fuel_scenario from nems_fuel_scenarios where nems_fuel_scenario_id = $NEMS_FUEL_SCENARIO_ID) \
and training_set_id=$TRAINING_SET_ID \
UNION \
select $present_year, breakpoint_id, consumption_breakpoint as ng_consumption_breakpoint_raw, price_surplus_adjusted as ng_price_surplus_adjusted \
from natural_gas_supply_curve, training_set_periods \
where simulation_year=$present_year \
and nems_scenario = (select nems_fuel_scenario from nems_fuel_scenarios where nems_fuel_scenario_id = $NEMS_FUEL_SCENARIO_ID) \
and training_set_id=$TRAINING_SET_ID \
order by period, breakpoint_id;" >> ng_supply_curve.tab

echo '	ng_regional_price_adders.tab...'
echo ampl.tab 2 1 > ng_regional_price_adders.tab
mysql $connection_string -e "\
select nems_region, period_start as period, regional_price_adder as ng_regional_price_adder \
from 	natural_gas_regional_price_adders, training_set_periods \
join training_sets using(training_set_id) \
where	simulation_year = FLOOR( period_start + years_per_period / 2) \
and		nems_scenario = (select nems_fuel_scenario from nems_fuel_scenarios where nems_fuel_scenario_id = $NEMS_FUEL_SCENARIO_ID) \
and training_set_id=$TRAINING_SET_ID \
UNION \
select nems_region, $present_year, regional_price_adder as ng_regional_price_adder \
from 	natural_gas_regional_price_adders, training_set_periods \
where	simulation_year = $present_year \
and		nems_scenario = (select nems_fuel_scenario from nems_fuel_scenarios where nems_fuel_scenario_id = $NEMS_FUEL_SCENARIO_ID) \
and training_set_id=$TRAINING_SET_ID \
order by nems_region, period ;" >> ng_regional_price_adders.tab


echo '	biomass_supply_curve.tab...'
echo ampl.tab 3 2 > biomass_supply_curve.tab
mysql $connection_string -e "\
SELECT load_area, period_start as period, breakpoint_id, COALESCE(breakpoint_mmbtu_per_year, 0) as breakpoint_mmbtu_per_year, price_dollars_per_mmbtu_surplus_adjusted \
FROM biomass_solid_supply_curve, training_set_periods \
join training_sets using(training_set_id) \
WHERE year=FLOOR( period_start + years_per_period / 2) \
  AND training_set_id=$TRAINING_SET_ID \
UNION \
SELECT load_area, $present_year, breakpoint_id, COALESCE(breakpoint_mmbtu_per_year, 0) as breakpoint_mmbtu_per_year, price_dollars_per_mmbtu_surplus_adjusted \
FROM biomass_solid_supply_curve, training_set_periods \
WHERE year=$present_year AND training_set_id=$TRAINING_SET_ID \
order by load_area, period, breakpoint_id ;" >> biomass_supply_curve.tab


echo '	fuel_info.tab...'
echo ampl.tab 1 4 > fuel_info.tab
mysql $connection_string -e "select fuel, rps_fuel_category, biofuel, carbon_content, carbon_sequestered from fuel_info_v2;" >> fuel_info.tab

# switch.mod and load.run want enable_rps to be be a binary flag determining whether rps constraints will be written out
# but the meaning of enable_rps in mysql was changed to mean rps_scenario_id
# any value greater than zero indicates that we want rps constraints enabled
if [ "$ENABLE_RPS" -gt 0 ]; then
	ENABLE_RPS=1
fi

echo '	misc_params.dat...'
echo "param scenario_id           := $SCENARIO_ID;" >  misc_params.dat
echo "param enable_rps            := $ENABLE_RPS;"  >> misc_params.dat
echo "param enable_carbon_cap     := $ENABLE_CARBON_CAP;"  >> misc_params.dat
echo "param enforce_ca_dg_mandate := $ENFORCE_CA_DG_MANDATE;"  >> misc_params.dat
echo "param transmission_capital_cost_per_mw_km := $transmission_capital_cost_per_mw_km;"  >> misc_params.dat
echo "param num_years_per_period  := $number_of_years_per_period;"  >> misc_params.dat
echo "param present_year  := $present_year;"  >> misc_params.dat

echo '	misc_options.run...'
echo "option relax_integrality  $LINEARIZE_OPTIMIZATION;"  > misc_options.run

echo '	cap_factor.tab...'
echo ampl.tab 4 1 > cap_factor.tab
mysql $connection_string -e "\
select project_id, load_area, technology, DATE_FORMAT(datetime_utc,'%Y%m%d%H') as hour, cap_factor  \
  FROM _training_set_timepoints \
    JOIN study_timepoints USING(timepoint_id)\
    JOIN load_scenario_historic_timepoints USING(timepoint_id)\
    JOIN $cap_factor_table ON(historic_hour=hour)\
    JOIN $proposed_projects_table USING(project_id)\
    JOIN load_area_info USING(area_id)\
  WHERE training_set_id=$TRAINING_SET_ID \
    AND load_scenario_id=$LOAD_SCENARIO_ID \
    AND $INTERMITTENT_PROJECTS_SELECTION;" >> cap_factor.tab

cd ..
