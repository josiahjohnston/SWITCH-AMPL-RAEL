# Export SWITCH input data from the Switch_inputs database into text files that will be read in by AMPL
# This script assumes that SetUpStudyHours.sql and 'build cap factors.sql' have both been called
# If you need to call those, copy the following commands into a terminal and wait 20 minutes or so. 
# mysql < 'build cap factors.sql'
# mysql < 'SetUpStudyHours.sql'

export write_to_path='.'

db_server="switch-db1.erg.berkeley.edu"
DB_name="switch_inputs_wecc_v2_1"
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

read SCENARIO_ID < scenario_id.txt

export REGIONAL_MULTIPLIER_SCENARIO_ID=`mysql $connection_string --column-names=false -e "select regional_cost_multiplier_scenario_id from scenarios where scenario_id=$SCENARIO_ID;"` 
export REGIONAL_FUEL_COST_SCENARIO_ID=`mysql $connection_string --column-names=false -e "select regional_fuel_cost_scenario_id from scenarios where scenario_id=$SCENARIO_ID;"` 
export REGIONAL_GEN_PRICE_SCENARIO_ID=`mysql $connection_string --column-names=false -e "select regional_gen_price_scenario_id from scenarios where scenario_id=$SCENARIO_ID;"` 
export SCENARIO_NAME=`mysql $connection_string --column-names=false -e "select scenario_name from scenarios where scenario_id=$SCENARIO_ID;"` 
export DATESAMPLE=`mysql $connection_string --column-names=false -e "select _datesample from scenarios where scenario_id=$SCENARIO_ID;"` 
export TIMESAMPLE=`mysql $connection_string --column-names=false -e "select _timesample from scenarios where scenario_id=$SCENARIO_ID;"` 
export HOURS_IN_SAMPLE=`mysql $connection_string --column-names=false -e "select _hours_in_sample from scenarios where scenario_id=$SCENARIO_ID;"` 
export ENABLE_RPS=`mysql $connection_string --column-names=false -e "select enable_rps from scenarios where scenario_id=$SCENARIO_ID;"` 
export STUDY_START_YEAR=`mysql $connection_string --column-names=false -e "select min(period) from study_hours_all where $TIMESAMPLE;"` 
export STUDY_END_YEAR=`mysql $connection_string --column-names=false -e "select max(period) + (max(period)-min(period))/(count(distinct period) - 1 ) from study_hours_all where $TIMESAMPLE;"` 

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
mysql $connection_string -e "select study_hour as hour, period, study_date as date, $HOURS_IN_SAMPLE as hours_in_sample, month_of_year, hour_of_day from study_hours_all where $TIMESAMPLE order by 1;" >> study_hours.tab

echo '	enable_rps.txt...'
echo $ENABLE_RPS > enable_rps.txt

echo '	load_areas.tab...'
echo ampl.tab 1 4 > load_areas.tab
mysql $connection_string -e "select load_area, area_id as load_area_id, economic_multiplier, rps_compliance_year, rps_compliance_percentage from load_area_info;" >> load_areas.tab

echo '	transmission_lines.tab...'
echo ampl.tab 2 4 > transmission_lines.tab
mysql $connection_string -e "select load_area_start, load_area_end, existing_transfer_capacity_mw, transmission_line_id, transmission_length_km, 0.95 as transmission_efficiency from transmission_lines where (existing_transfer_capacity_mw > 0 or load_areas_border_each_other like 't');" >> transmission_lines.tab

# TODO: adopt better load forecasts; this assumes a simple 1.6%/year increase
echo '	system_load.tab...'
echo ampl.tab 2 1 > system_load.tab
mysql $connection_string -e "select load_area, study_hour as hour, power(1.016, period-year(datetime_utc))*power as system_load from system_load l join study_hours_all h on (h.hournum=l.hour) where $TIMESAMPLE order by study_hour, load_area;" >> system_load.tab

echo '	existing_plants.tab...'
echo ampl.tab 2 15 > existing_plants.tab
mysql $connection_string -e "select load_area, plant_code, project_id as ep_project_id, peak_mw as size_mw, technology, aer_fuel as fuel, heat_rate, start_year, max_age, overnight_cost, fixed_o_m, variable_o_m, forced_outage_rate, scheduled_outage_rate, baseload, cogen, intermittent from existing_plants order by 1, 2;" >> existing_plants.tab

echo '	existing_intermittent_plant_cap_factor.tab...'
echo ampl.tab 3 1 > existing_intermittent_plant_cap_factor.tab
mysql $connection_string -e "select load_area, plant_code, study_hour as hour, cap_factor from  existing_intermittent_plant_cap_factor c join study_hours_all h on (h.hournum=c.hour) where $TIMESAMPLE order by 1,2;" >> existing_intermittent_plant_cap_factor.tab

echo '	hydro.tab...'
echo ampl.tab 3 4 > hydro.tab
mysql $connection_string -e "select load_area, site, study_date as date, project_id as hydro_project_id, avg_flow, min_flow, max_flow from hydro_monthly_limits l join study_dates_all d on l.year = year(d.date_utc) and l.month=month(d.date_utc) where $DATESAMPLE order by 1, 2, month, year;" >> hydro.tab

echo '	proposed_renewable_sites.tab...'
echo ampl.tab 3 2 > proposed_renewable_sites.tab
mysql $connection_string -e "select load_area, generator_type as technology, project_id as site, capacity_mw as max_capacity, connect_cost_per_mw from proposed_renewable_sites;" >> proposed_renewable_sites.tab

echo '	cap_factor.tab...'
echo ampl.tab 5 1 > cap_factor.tab
mysql $connection_string -e "select load_area, generator_type as technology, project_id as site, configuration, study_hour as hour, cap_factor from cap_factor_proposed_renewable_sites c join study_hours_all h on (h.hournum=c.hour) join configurations using(configuration) where $TIMESAMPLE;" >> cap_factor.tab

echo '	generator_info.tab...'
echo ampl.tab 1 23 > generator_info.tab
mysql $connection_string -e "select technology, technology_id, min_build_year, fuel, heat_rate, construction_time_years, year_1_cost_fraction, year_2_cost_fraction, year_3_cost_fraction, year_4_cost_fraction, year_5_cost_fraction, year_6_cost_fraction, max_age_years, forced_outage_rate, scheduled_outage_rate, intermittent, resource_limited, baseload, min_build_capacity, min_dispatch_fraction, min_runtime, min_downtime, max_ramp_rate_mw_per_hour, startup_fuel_mbtu from generator_info;" >> generator_info.tab

echo '	generator_costs_regional.tab...'
echo ampl.tab 2 8 > generator_costs_regional.tab
mysql $connection_string -e "select load_area, technology, project_id as regional_project_id, price_and_dollar_year, overnight_cost, connect_cost_per_mw_generic, fixed_o_m, variable_o_m, overnight_cost_change, nonfuel_startup_cost from generator_costs_regional where scenario_id = $REGIONAL_GEN_PRICE_SCENARIO_ID;" >> generator_costs_regional.tab

echo '	fuel_costs.tab...'
echo ampl.tab 3 1 > fuel_costs.tab
mysql $connection_string -e "select load_area, fuel, year, fuel_price from fuel_prices_regional where scenario_id = $REGIONAL_FUEL_COST_SCENARIO_ID and year >= $STUDY_START_YEAR and year <= $STUDY_END_YEAR" >> fuel_costs.tab

echo '	fuel_info.tab...'
echo ampl.tab 1 2 > fuel_info.tab
mysql $connection_string -e "select fuel, rps_fuel_category, carbon_content from fuel_info;" >> fuel_info.tab

echo '	fuel_qualifies_for_rps.tab...'
echo ampl.tab 2 1 > fuel_qualifies_for_rps.tab
mysql $connection_string -e "select load_area, rps_fuel_category, qualifies from fuel_qualifies_for_rps;" >> fuel_qualifies_for_rps.tab
