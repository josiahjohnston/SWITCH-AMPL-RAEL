# Export SWITCH input data from the Switch inputs database into text files that will be read in by AMPL
# This script assumes that the input database has already been built by the script 'Build WECC Cap Factors.sql'

write_to_path='inputs'

db_server="switch-db1.erg.berkeley.edu"
DB_name="switch_inputs_wecc_v2_2"
port=3306

###################################################
# Detect optional command-line arguments
help=0
while [ -n "$1" ]; do
case $1 in
  -u)
    user=$2
    shift 2
  ;;
  -p)
    password=$2
    shift 2
  ;;
  -P)
    port=$2
    shift 2
  ;;
  --port)
    port=$2
    shift 2
  ;;
  -D)
    DB_name=$2
    shift 2
  ;;
  -h)
    db_server=$2
    shift 2
  ;;
  --help)
    help=1
    shift 1
  ;;
  *)
    echo "Unknown option $1"
    help=1
    shift 1
  ;;
esac
done

if [ $help = 1 ]
then
  echo "Usage: $0 [OPTIONS]"
  echo "  --help                   Print this message"
  echo "  -u [DB Username]"
  echo "  -p [DB Password]"
  echo "  -D [DB name]"
  echo "  -P/--port [port number]"
  echo "  -h [DB server]"
  echo "All arguments are optional. "
  exit 0
fi

##########################
# Get the user name and password 
# Note that passing the password to mysql via a command line parameter is considered insecure
#	http://dev.mysql.com/doc/refman/5.0/en/password-security.html
if [ ! -n "$user" ]
then 
	echo "User name for MySQL $DB_name on $db_server? "
	read user
fi
if [ ! -n "$password" ]
then 
	echo "Password for MySQL $DB_name on $db_server? "
	stty_orig=`stty -g`   # Save screen settings
	stty -echo            # To keep the password vaguely secure, don't let it show to the screen
	read password
	stty $stty_orig       # Restore screen settings
fi

connection_string="-h $db_server --port $port -u $user -p$password $DB_name"
test_connection=`mysql $connection_string --column-names=false -e "select count(*) from existing_plants;"`
if [ ! -n "$test_connection" ]
then
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

export REGIONAL_MULTIPLIER_SCENARIO_ID=`mysql $connection_string --column-names=false -e "select regional_cost_multiplier_scenario_id from scenarios where scenario_id=$SCENARIO_ID;"` 
export REGIONAL_FUEL_COST_SCENARIO_ID=`mysql $connection_string --column-names=false -e "select regional_fuel_cost_scenario_id from scenarios where scenario_id=$SCENARIO_ID;"` 
export GEN_PRICE_SCENARIO_ID=`mysql $connection_string --column-names=false -e "select gen_price_scenario_id from scenarios where scenario_id=$SCENARIO_ID;"` 
export SCENARIO_NAME=`mysql $connection_string --column-names=false -e "select scenario_name from scenarios where scenario_id=$SCENARIO_ID;"` 
export DATESAMPLE=`mysql $connection_string --column-names=false -e "select _datesample from scenarios where scenario_id=$SCENARIO_ID;"` 
export TIMESAMPLE=`mysql $connection_string --column-names=false -e "select _timesample from scenarios where scenario_id=$SCENARIO_ID;"` 
export HOURS_IN_SAMPLE=`mysql $connection_string --column-names=false -e "select _hours_in_sample from scenarios where scenario_id=$SCENARIO_ID;"` 
export ENABLE_RPS=`mysql $connection_string --column-names=false -e "select enable_rps from scenarios where scenario_id=$SCENARIO_ID;"` 
export ENABLE_CARBON_CAP=`mysql $connection_string --column-names=false -e "select enable_carbon_cap from scenarios where scenario_id=$SCENARIO_ID;"` 
export STUDY_START_YEAR=`mysql $connection_string --column-names=false -e "select min(period) from study_hours_all where $TIMESAMPLE;"` 
export STUDY_END_YEAR=`mysql $connection_string --column-names=false -e "select max(period) + (max(period)-min(period))/(count(distinct period) - 1 ) from study_hours_all where $TIMESAMPLE;"` 
number_of_years_per_period=`mysql $connection_string --column-names=false -e "select round((max(period)-min(period))/(count(distinct period) - 1 )) from study_hours_all where $TIMESAMPLE;"` 
###########################
# Export data to be read into ampl.

cd  $write_to_path

echo 'Exporting Scenario Information'
echo 'Scenario Information' > scenario_information.txt
mysql $connection_string -e "select * from scenarios where scenario_id = $SCENARIO_ID;" >> scenario_information.txt
echo 'Training Set Information' >> scenario_information.txt
mysql $connection_string -e "select training_sets.* from training_sets join scenarios using (training_set_id) where scenario_id = $SCENARIO_ID;" >> scenario_information.txt

# The general format for the following files is for the first line to be:
#	ampl.tab [number of key columns] [number of non-key columns]
# col1_name col2_name ...
# [rows of data]

echo 'Copying data from the database to input files...'

echo '	study_hours.tab...'
echo ampl.tab 1 5 > study_hours.tab
mysql $connection_string -e "select study_hour as hour, period, study_date as date, $HOURS_IN_SAMPLE as hours_in_sample, month_of_year, hour_of_day from study_hours_all where $TIMESAMPLE order by 1;" >> study_hours.tab

echo '	load_areas.tab...'
echo ampl.tab 1 7 > load_areas.tab
mysql $connection_string -e "select load_area, area_id as load_area_id, primary_nerc_subregion as balancing_area, economic_multiplier, max_coincident_load_for_local_td, local_td_new_annual_payment_per_mw, local_td_sunk_annual_payment, transmission_sunk_annual_payment from load_area_info;" >> load_areas.tab

echo '	balancing_areas.tab...'
echo ampl.tab 1 4 > balancing_areas.tab
mysql $connection_string -e "select balancing_area, load_only_spinning_reserve_requirement, wind_spinning_reserve_requirement, solar_spinning_reserve_requirement, quickstart_requirement_relative_to_spinning_reserve_requirement from balancing_areas;" >> balancing_areas.tab

echo '	rps_load_area_targets.tab...'
echo ampl.tab 2 1 > rps_load_area_targets.tab
mysql $connection_string -e "select load_area, compliance_year as rps_compliance_year, compliance_fraction as rps_compliance_fraction from rps_load_area_targets where compliance_year >= $STUDY_START_YEAR and compliance_year <= $STUDY_END_YEAR;" >> rps_load_area_targets.tab

echo '	carbon_cap_targets.tab...'
echo ampl.tab 1 1 > carbon_cap_targets.tab
mysql $connection_string -e "select year, carbon_emissions_relative_to_base from carbon_cap_targets where year >= $STUDY_START_YEAR and year <= $STUDY_END_YEAR;" >> carbon_cap_targets.tab

echo '	transmission_lines.tab...'
echo ampl.tab 2 5 > transmission_lines.tab
mysql $connection_string -e "select load_area_start, load_area_end, existing_transfer_capacity_mw, transmission_line_id, transmission_length_km, transmission_efficiency, new_transmission_builds_allowed from transmission_lines order by 1,2;" >> transmission_lines.tab

# TODO: adopt better load forecasts; this assumes a simple 1.0%/year increase - the amount projected for all of WECC from 2010 to 2018 by the EIA AEO 2008
# currently we hit the middle of the period with number_of_years_per_period/2
echo '	system_load.tab...'
echo ampl.tab 2 2 > system_load.tab
mysql $connection_string -e "select load_area, study_hour as hour, power(1.01, period + $number_of_years_per_period/2 - year(datetime_utc))*power as system_load, power(1.01, $present_year - year(datetime_utc))*power as present_day_system_load from system_load l join study_hours_all h on (h.hournum=l.hour) where $TIMESAMPLE order by study_hour, load_area;" >> system_load.tab

echo '	max_system_loads.tab...'
echo ampl.tab 2 1 > max_system_loads.tab
mysql $connection_string -e "select load_area, period, round(power(1.01, period + $number_of_years_per_period/2 - year(datetime_utc))*max_power,2) as max_system_load from (select load_area, (select datetime_utc from _system_load join hours on(hour=hournum) where area_id=sl.area_id order by power desc limit 1) as datetime_utc, max(power) as max_power from system_load sl group by 1) as max_loads join (select $present_year as period UNION select distinct period from study_dates_all where $DATESAMPLE) as periods;" >> max_system_loads.tab

echo '	existing_plants.tab...'
echo ampl.tab 3 11 > existing_plants.tab
mysql $connection_string -e "select project_id, load_area, technology, plant_name, eia_id, capacity_mw, heat_rate, cogen_thermal_demand_mmbtus_per_mwh, if(start_year = 0, 1900, start_year) as start_year, overnight_cost, connect_cost_per_mw, fixed_o_m, variable_o_m, ep_location_id from existing_plants order by 1, 2, 3;" >> existing_plants.tab

echo '	existing_intermittent_plant_cap_factor.tab...'
echo ampl.tab 4 1 > existing_intermittent_plant_cap_factor.tab
mysql $connection_string -e "select project_id, load_area, technology, study_hour as hour, cap_factor from  existing_intermittent_plant_cap_factor c join study_hours_all h on (h.hournum=c.hour) where $TIMESAMPLE order by 1, 2, 3, 4;" >> existing_intermittent_plant_cap_factor.tab

echo '	hydro_monthly_limits.tab...'
echo ampl.tab 4 1 > hydro_monthly_limits.tab
mysql $connection_string -e "select project_id, load_area, technology, study_date as date, avg_output from hydro_monthly_limits l join study_dates_all d on l.year = year(d.date_utc) and l.month=month(d.date_utc) where $DATESAMPLE order by 1, 2, 3, 4;" >> hydro_monthly_limits.tab

echo '	proposed_projects.tab...'
echo ampl.tab 3 11 > proposed_projects.tab
mysql $connection_string -e "select project_id, proposed_projects.load_area, technology, if(location_id is NULL, 0, location_id) as location_id, if(ep_project_replacement_id is NULL, 0, ep_project_replacement_id) as ep_project_replacement_id, if(capacity_limit is NULL, 0, capacity_limit) as capacity_limit, capacity_limit_conversion, heat_rate, connect_cost_per_mw, price_and_dollar_year, round(overnight_cost*overnight_adjuster) as overnight_cost, fixed_o_m, variable_o_m, overnight_cost_change from proposed_projects join load_area_info using (area_id) join generator_price_adjuster using (technology_id) where generator_price_adjuster.gen_price_scenario_id=$GEN_PRICE_SCENARIO_ID and $INTERMITTENT_PROJECTS_SELECTION;" >> proposed_projects.tab

echo '	generator_info.tab...'
echo ampl.tab 1 27 > generator_info.tab
mysql $connection_string -e "select technology, technology_id, min_build_year, fuel,  construction_time_years, year_1_cost_fraction, year_2_cost_fraction, year_3_cost_fraction, year_4_cost_fraction, year_5_cost_fraction, year_6_cost_fraction, max_age_years, forced_outage_rate, scheduled_outage_rate, can_build_new, ccs, intermittent, resource_limited, baseload, dispatchable, cogen, min_build_capacity, competes_for_space, storage, storage_efficiency, max_store_rate, max_spinning_reserve_fraction_of_capacity, heat_rate_penalty_spinning_reserve from generator_info;" >> generator_info.tab

echo '	fuel_costs.tab...'
echo ampl.tab 3 1 > fuel_costs.tab
mysql $connection_string -e "select load_area, fuel, year, fuel_price from fuel_prices_regional where scenario_id = $REGIONAL_FUEL_COST_SCENARIO_ID and year <= $STUDY_END_YEAR" >> fuel_costs.tab

echo '	biomass_supply_curve_slope.tab...'
echo ampl.tab 2 1 > biomass_supply_curve_slope.tab
mysql $connection_string -e "select load_area, breakpoint_id, price_dollars_per_mbtu from biomass_solid_supply_curve order by load_area, breakpoint_id" >> biomass_supply_curve_slope.tab

echo '	biomass_supply_curve_breakpoint.tab...'
echo ampl.tab 2 1 > biomass_supply_curve_breakpoint.tab
mysql $connection_string -e "select load_area, breakpoint_id, breakpoint_mbtus_per_year from biomass_solid_supply_curve where breakpoint_mbtus_per_year is not null order by load_area, breakpoint_id" >> biomass_supply_curve_breakpoint.tab

echo '	fuel_info.tab...'
echo ampl.tab 1 3 > fuel_info.tab
mysql $connection_string -e "select fuel, rps_fuel_category, biofuel, carbon_content from fuel_info;" >> fuel_info.tab

echo '	fuel_qualifies_for_rps.tab...'
echo ampl.tab 2 1 > fuel_qualifies_for_rps.tab
mysql $connection_string -e "select load_area, rps_fuel_category, qualifies from fuel_qualifies_for_rps;" >> fuel_qualifies_for_rps.tab


echo '	misc_params.dat...'
echo "param scenario_id           := $SCENARIO_ID;" >  misc_params.dat
echo "param enable_rps            := $ENABLE_RPS;"  >> misc_params.dat
echo "param enable_carbon_cap     := $ENABLE_CARBON_CAP;"  >> misc_params.dat
echo "param num_years_per_period  := $number_of_years_per_period;"  >> misc_params.dat
echo "param present_year  := $present_year;"  >> misc_params.dat

echo '	cap_factor.tab...'
echo ampl.tab 4 1 > cap_factor.tab
mysql $connection_string -e "select project_id, proposed_projects.load_area, proposed_projects.technology, study_hour as hour, cap_factor from _cap_factor_intermittent_sites c join study_hours_all h on (h.hournum=c.hour) join proposed_projects using (project_id) join load_area_info using (area_id) where $INTERMITTENT_PROJECTS_SELECTION and $TIMESAMPLE;" >> cap_factor.tab

cd ..
