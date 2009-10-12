# Export SWITCH input data from the Switch_inputs database into text files that will be read in by AMPL
# This script assumes that SetUpStudyHours.sql and 'build cap factors.sql' have both been called
# If you need to call those, copy the following commands into a terminal and wait 20 minutes or so. 
# mysql < 'build cap factors.sql'
# mysql < 'SetUpStudyHours.sql'

export write_to_path='.'

db_server="xserve-rael.erg.berkeley.edu"
db_name="switch_inputs_wecc_v2"

if [ $# = 2 ]
then 
	user=$1
	password=$2
else
	echo "User name for MySQL on $db_server? "
	read user
	echo "Password for MySQL on $db_server? "
	stty_orig=`stty -g`   # Save screen settings
	stty -echo            # To keep the password vaguely secure, don't let it show to the screen
	read password
	stty $stty_orig       # Restore screen settings
fi

###########################
# These next variables determine which input data is used

read SCENARIO_ID < scenario_id.txt

export REGIONAL_MULTIPLIER_SCENARIO_ID=`mysql -h $db_server -u $user -p$password --column-names=false -e "select regional_cost_multiplier_scenario_id from wecc.scenarios where scenario_id=$SCENARIO_ID;"` 
export REGIONAL_FUEL_COST_SCENARIO_ID=`mysql -h $db_server -u $user -p$password --column-names=false -e "select regional_fuel_cost_scenario_id from wecc.scenarios where scenario_id=$SCENARIO_ID;"` 
export REGIONAL_GEN_PRICE_SCENARIO_ID=`mysql -h $db_server -u $user -p$password --column-names=false -e "select regional_gen_price_scenario_id from wecc.scenarios where scenario_id=$SCENARIO_ID;"` 
export SCENARIO_NAME=`mysql -h $db_server -u $user -p$password --column-names=false -e "select scenario_name from wecc.scenarios where scenario_id=$SCENARIO_ID;"` 
export DATESAMPLE=`mysql -h $db_server -u $user -p$password --column-names=false -e "select _datesample from wecc.scenarios where scenario_id=$SCENARIO_ID;"` 
export TIMESAMPLE=`mysql -h $db_server -u $user -p$password --column-names=false -e "select _timesample from wecc.scenarios where scenario_id=$SCENARIO_ID;"` 
export HOURS_IN_SAMPLE=`mysql -h $db_server -u $user -p$password --column-names=false -e "select _hours_in_sample from wecc.scenarios where scenario_id=$SCENARIO_ID;"` 
export ENABLE_RPS=`mysql -h $db_server -u $user -p$password --column-names=false -e "select enable_rps from wecc.scenarios where scenario_id=$SCENARIO_ID;"` 


###########################
# Export data to be read into ampl.

cd  $write_to_path

# note: the CAISO load aggregation/calculation areas are called 
# load_zone in the ampl model
# but load_area in the mysql solar database
# this is confusing, but necessary to avoid messing up the older solar model,
# which used local load zones (called load_zone in mysql)

# The general format for the following files is for the first line to be:
#	ampl.tab [number of key columns] [number of non-key columns]
# col1_name col2_name ...
# [rows of data]

echo 'Copying data from the database to input files...'

echo '	study_hours.tab...'
echo ampl.tab 1 5 > study_hours.tab
mysql -h $db_server -u $user -p$password -e "select study_hour as hour, period, study_date as date, $HOURS_IN_SAMPLE as hours_in_sample, month_of_year, hour_of_day from $db_name.study_hours_all where $TIMESAMPLE order by 1;" >> study_hours.tab

echo '	enable_rps.txt...'
echo $ENABLE_RPS > enable_rps.txt

echo '	load_areas.tab...'
echo ampl.tab 1 3 > load_areas.tab
mysql -h $db_server -u $user -p$password -e "select load_area, economic_multiplier, rps_compliance_year, rps_compliance_percentage from $db_name.load_area_info;" >> load_areas.tab

echo '	transmission_lines.tab...'
echo ampl.tab 2 4 > transmission_lines.tab
mysql -h $db_server -u $user -p$password -e "select load_area_start, load_area_end, existing_transfer_capacity_mw, transmission_line_id, transmission_length_km, 0.95 as transmission_efficiency from $db_name.transmission_lines where (existing_transfer_capacity_mw > 0 or load_areas_border_each_other like 't' or transmission_length_km < 300);" >> transmission_lines.tab

# TODO: adopt better load forecasts; this assumes a simple 1.6%/year increase
echo '	system_load.tab...'
echo ampl.tab 2 1 > system_load.tab
mysql -h $db_server -u $user -p$password -e "select load_area, study_hour as hour, power(1.016, period-(2004+datediff(datetime_utc, '2004-01-01')/365))*power as system_load from $db_name.system_load l join $db_name.study_hours_all h on (h.hournum=l.hour) where $TIMESAMPLE order by study_hour, load_area;" >> system_load.tab

echo '	existing_plants.tab...'
echo ampl.tab 2 14 > existing_plants.tab
mysql -h $db_server -u $user -p$password -e "select load_area, plant_code, peak_mw as size_mw, technology, aer_fuel as fuel, heat_rate, start_year, max_age, overnight_cost, fixed_o_m, variable_o_m, forced_outage_rate, scheduled_outage_rate, baseload, cogen, intermittent from $db_name.existing_plants order by 1, 2;" >> existing_plants.tab

echo '	existing_intermittent_plant_cap_factor.tab...'
echo ampl.tab 3 1 > existing_intermittent_plant_cap_factor.tab
echo "load_area	plant_code	hour	cap_factor" >> existing_intermittent_plant_cap_factor.tab

echo '	hydro.tab...'
echo ampl.tab 3 3 > hydro.tab
mysql -h $db_server -u $user -p$password -e "select load_area, site, study_date as date, avg_flow, min_flow, max_flow from $db_name.hydro_monthly_limits l join $db_name.study_dates_all d on l.year = year(d.date_utc) and l.month=month(d.date_utc) where $DATESAMPLE order by 1, 2, month, year;" >> hydro.tab

echo '	proposed_renewable_sites.tab...'
echo ampl.tab 3 2 > proposed_renewable_sites.tab
mysql -h $db_server -u $user -p$password -e "select load_area, generator_type as technology, site_id as site, capacity_mw as max_capacity, connect_cost_per_mw from $db_name.proposed_renewable_sites;" >> proposed_renewable_sites.tab

echo '	cap_factor.tab...'
echo ampl.tab 5 1 > cap_factor.tab
mysql -h $db_server -u $user -p$password -e "select load_area, generator_type as technology, site, configuration, study_hour as hour, cap_factor from $db_name.cap_factor_proposed_renewable_sites c join $db_name.study_hours_all h on (h.hournum=c.hour) where $TIMESAMPLE;" >> cap_factor.tab

echo '	generator_info.tab...'
echo ampl.tab 1 11 > generator_info.tab
mysql -h $db_server -u $user -p$password -e "select technology, min_build_year, fuel, heat_rate, construction_time_years, max_age_years, forced_outage_rate, scheduled_outage_rate, intermittent, resource_limited, baseload, min_build_capacity from $db_name.generator_info;" >> generator_info.tab

echo '	regional_generator_costs.tab...'
echo ampl.tab 2 8 > regional_generator_costs.tab
mysql -h $db_server -u $user -p$password -e "select load_area, technology, price_year, overnight_cost, connect_cost_per_mw_generic, fixed_o_m, variable_o_m, overnight_cost_change, fixed_o_m_change, variable_o_m_change from $db_name.regional_generator_costs_view where scenario_id = $REGIONAL_GEN_PRICE_SCENARIO_ID;" >> regional_generator_costs.tab

echo '	fuel_costs.tab...'
echo ampl.tab 3 1 > fuel_costs.tab
mysql -h $db_server -u $user -p$password -e "select load_area, fuel, year, fuel_price from $db_name.regional_fuel_prices_view where scenario_id = $REGIONAL_FUEL_COST_SCENARIO_ID" >> fuel_costs.tab

echo '	fuel_info.tab...'
echo ampl.tab 1 2 > fuel_info.tab
mysql -h $db_server -u $user -p$password -e "select fuel, rps_fuel_category, carbon_content from $db_name.fuel_info;" >> fuel_info.tab

echo '	fuel_qualifies_for_rps.tab...'
echo ampl.tab 2 1 > fuel_qualifies_for_rps.tab
mysql -h $db_server -u $user -p$password -e "select load_area, rps_fuel_category, qualifies from $db_name.fuel_qualifies_for_rps;" >> fuel_qualifies_for_rps.tab