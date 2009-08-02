# Export SWITCH input data from the Switch_inputs database into text files that will be read in by AMPL
# This script assumes that SetUpStudyHours.sql and 'build cap factors.sql' have both been called
# If you need to call those, copy the following commands into a terminal and wait 20 minutes or so. 
# mysql < 'build cap factors.sql'
# mysql < 'SetUpStudyHours.sql'

export write_to_path='.'

db_server="xserve-rael.erg.berkeley.edu"

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
mysql -h $db_server -u $user -p$password -e "select study_hour as hour, period, study_date as date, $HOURS_IN_SAMPLE as hours_in_sample, month_of_year, hour_of_day from wecc.study_hours_all where $TIMESAMPLE order by 1;" >> study_hours.tab

echo '	enable_rps.txt...'
echo $ENABLE_RPS > enable_rps.txt


echo '	load_zones.tab...'
echo ampl.tab 1 2 > load_zones.tab
mysql -h $db_server -u $user -p$password -e "select replace(load_area, ' ', '_') as load_zone, x_utm as load_zone_x, y_utm as load_zone_y from wecc.load_area;" >> load_zones.tab

echo '	existing_plants.tab...'
echo ampl.tab 2 12 > existing_plants.tab
mysql -h $db_server -u $user -p$password -e "select replace(load_area, ' ', '_') as load_zone, plant_code, peak_mw as size_mw, fuel, heat_rate, invsyear as start_year, max_age, overnight_cost, fixed_o_m, variable_o_m, forced_outage_rate, scheduled_outage_rate, baseload, cogen from wecc.existing_plants_agg order by 1, 2;" >> existing_plants.tab

echo '	trans_lines.tab...'
echo ampl.tab 2 4 > trans_lines.tab
mysql -h $db_server -u $user -p$password -e "select replace(load_area_start, ' ', '_') as load_zone_start, replace(load_area_end, ' ', '_') as load_zone_end, existing_transmission, tid, length_km as transmission_length_km, transmission_efficiency from wecc.directed_trans_lines where (existing_transmission > 0 or geoms_intersect = 1);" >> trans_lines.tab

# TODO: adopt better load forecasts; this assumes a simple 1.6%/year increase
echo '	system_load.tab...'
echo ampl.tab 2 1 > system_load.tab
mysql -h $db_server -u $user -p$password -e "select replace(load_area, ' ', '_') as load_zone, study_hour as hour, power(1.016, period-(2004+datediff(datetime_utc, '2004-01-01')/365))*power as system_load from wecc.system_load l join wecc.study_hours_all h on (h.hournum=l.hour) where $TIMESAMPLE order by study_hour, load_zone;" >> system_load.tab

echo '	hydro.tab...'
echo ampl.tab 3 3 > hydro.tab
mysql -h $db_server -u $user -p$password -e "select distinct replace(load_area, ' ', '_') as load_zone, site, study_date as date, avg_flow, min_flow, max_flow from wecc.hydro_monthly_limits l join wecc.study_dates_all d on l.year = year(d.date_utc) and l.month=month(d.date_utc) where $DATESAMPLE order by 1, 2, month, year;" >> hydro.tab

echo '	cap_factor.tab...'
echo ampl.tab 5 1 > cap_factor.tab
mysql -h $db_server -u $user -p$password -e "select replace(load_area, ' ', '_') as load_zone, technology, site, orientation, study_hour as hour, cap_factor from wecc.cap_factor_all c join wecc.study_hours_all h on (h.hournum=c.hour) where $TIMESAMPLE;" >> cap_factor.tab

echo '	max_capacity.tab...'
echo ampl.tab 4 1 > max_capacity.tab
mysql -h $db_server -u $user -p$password -e "select replace(load_area, ' ', '_') as load_zone, technology, site, orientation, max_capacity from wecc.max_capacity_all;" >> max_capacity.tab

echo '	connect_cost.tab...'
echo ampl.tab 4 2 > connect_cost.tab
mysql -h $db_server -u $user -p$password -e "select replace(load_area, ' ', '_') as load_zone, technology, site, orientation, connect_length_km, connect_cost_per_MW from wecc.connect_cost_all;" >> connect_cost.tab

echo '	generator_info.tab...'
echo ampl.tab 1 11 > generator_info.tab
mysql -h $db_server -u $user -p$password -e "select * from wecc.generator_info;" >> generator_info.tab

echo '	regional_economic_multiplier.tab...'
echo ampl.tab 1 1 > regional_economic_multiplier.tab
mysql -h $db_server -u $user -p$password -e "select load_area as load_zone, regional_economic_multiplier from wecc.regional_economic_multiplier_human where scenario_id = $REGIONAL_MULTIPLIER_SCENARIO_ID;" >> regional_economic_multiplier.tab

echo '	regional_fuel_costs.tab...'
echo ampl.tab 3 1 > regional_fuel_costs.tab
mysql -h $db_server -u $user -p$password -e "select load_area as load_zone, fuel, year, fuel_price from wecc.regional_fuel_prices_human where scenario_id = $REGIONAL_FUEL_COST_SCENARIO_ID" >> regional_fuel_costs.tab

echo '	regional_generator_costs.tab...'
echo ampl.tab 2 8 > regional_generator_costs.tab
mysql -h $db_server -u $user -p$password -e "select load_area as load_zone, technology, price_year, overnight_cost, connect_cost_per_MW_generic, fixed_o_m, variable_o_m, overnight_cost_change, fixed_o_m_change, variable_o_m_change from wecc.regional_generator_costs_human where scenario_id = $REGIONAL_GEN_PRICE_SCENARIO_ID;" >> regional_generator_costs.tab

echo '	rps_fuel_category.tab...'
echo ampl.tab 1 1 > rps_fuel_category.tab
mysql -h $db_server -u $user -p$password -e "select fuel, rps_fuel_category from wecc.rps_fuel_category;" >> rps_fuel_category.tab

echo '	qualifies_for_rps.tab...'
echo ampl.tab 2 1 > qualifies_for_rps.tab
mysql -h $db_server -u $user -p$password -e "select load_area as load_zone, rps_fuel_category, qualifies from wecc.qualifies_for_rps;" >> qualifies_for_rps.tab

echo '	rps_requirement.tab...'
echo ampl.tab 1 3 > rps_requirement.tab
mysql -h $db_server -u $user -p$password -e "select load_area as load_zone, rps_goal, rps_compliance_year, load_zone_rps_policy from wecc.rps_requirement;" >> rps_requirement.tab 
