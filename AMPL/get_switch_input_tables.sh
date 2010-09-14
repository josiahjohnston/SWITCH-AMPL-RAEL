# Export SWITCH input data from the Switch inputs database into text files that will be read in by AMPL
# This script assumes that the input database has already been built by the script 'Build WECC Cap Factors.sql'

export write_to_path='.'

db_server="switch-db1.erg.berkeley.edu"
DB_name="switch_inputs_wecc_v2_2"
port=3306

###################################################
# Detect optional command-line arguments
help=0
TOY=0
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
  --toy)
    TOY=$2
    shift 2
  ;;
  -TOY)
    TOY=$2
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
  echo "  --toy [percentile of projects in each technology above which to include, as ordered by cap factor]"
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
number_of_years_per_period=`mysql $connection_string --column-names=false -e "select (max(period)-min(period))/(count(distinct period) - 1 ) from study_hours_all where $TIMESAMPLE;"` 

###########################
# Export data to be read into ampl.

cd  $write_to_path

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
echo ampl.tab 1 6 > load_areas.tab
mysql $connection_string -e "select load_area, area_id as load_area_id, economic_multiplier, max_coincident_load_for_local_td, local_td_new_annual_payment_per_mw, local_td_sunk_annual_payment, transmission_sunk_annual_payment from load_area_info;" >> load_areas.tab

echo '	rps_load_area_targets.tab...'
echo ampl.tab 2 1 > rps_load_area_targets.tab
mysql $connection_string -e "select load_area, compliance_year as rps_compliance_year, compliance_fraction as rps_compliance_fraction from rps_load_area_targets where compliance_year >= $STUDY_START_YEAR and compliance_year <= $STUDY_END_YEAR;" >> rps_load_area_targets.tab

echo '	transmission_lines.tab...'
echo ampl.tab 2 4 > transmission_lines.tab
mysql $connection_string -e "select load_area_start, load_area_end, existing_transfer_capacity_mw, transmission_line_id, transmission_length_km, transmission_efficiency from transmission_lines where (existing_transfer_capacity_mw > 0 or load_areas_border_each_other like 't');" >> transmission_lines.tab

# TODO: adopt better load forecasts; this assumes a simple 1.0%/year increase - the amount projected for all of WECC from 2010 to 2018 by the EIA AEO 2008
# currently we hit the middle of the period with number_of_years_per_period/2
echo '	system_load.tab...'
echo ampl.tab 2 1 > system_load.tab
mysql $connection_string -e "select load_area, study_hour as hour, power(1.01, period + $number_of_years_per_period/2 - year(datetime_utc))*power as system_load from system_load l join study_hours_all h on (h.hournum=l.hour) where $TIMESAMPLE order by study_hour, load_area;" >> system_load.tab

echo '	existing_plants.tab...'
echo ampl.tab 2 15 > existing_plants.tab
mysql $connection_string -e "select load_area, plant_code, project_id as ep_project_id, peak_mw as size_mw, technology, fuel, heat_rate, start_year, max_age, overnight_cost, fixed_o_m, variable_o_m, forced_outage_rate, scheduled_outage_rate, baseload, cogen, intermittent from existing_plants order by 1, 2;" >> existing_plants.tab

echo '	existing_intermittent_plant_cap_factor.tab...'
echo ampl.tab 3 1 > existing_intermittent_plant_cap_factor.tab
mysql $connection_string -e "select load_area, plant_code, study_hour as hour, cap_factor from  existing_intermittent_plant_cap_factor c join study_hours_all h on (h.hournum=c.hour) where $TIMESAMPLE order by 1,2;" >> existing_intermittent_plant_cap_factor.tab

echo '	hydro.tab...'
echo ampl.tab 3 4 > hydro.tab
mysql $connection_string -e "select load_area, project_id as hydro_project_id, study_date as date, technology, technology_id, capacity_mw, avg_output from hydro_monthly_limits l join study_dates_all d on l.year = year(d.date_utc) and l.month=month(d.date_utc) where $DATESAMPLE order by 1, 2, month, year;" >> hydro.tab

echo '	proposed_projects.tab...'
echo ampl.tab 3 10 > proposed_projects.tab
mysql $connection_string -e "select project_id, proposed_projects.load_area, technology, if(location_id is NULL, 0, location_id) as location_id, if(capacity_limit is NULL, 0, capacity_limit) as capacity_limit, capacity_limit_conversion, connect_cost_per_mw, price_and_dollar_year, overnight_cost, fixed_o_m, variable_o_m, overnight_cost_change, nonfuel_startup_cost from proposed_projects join load_area_info using (area_id) where ( avg_cap_factor_percentile_by_intermittent_tech >= 0.75 or cumulative_avg_MW_tech_load_area <= 5 * total_yearly_load_mwh / 8766 or rank_by_tech_in_load_area <= 10 or avg_cap_factor_percentile_by_intermittent_tech is null or technology = 'Wind');" >> proposed_projects.tab

echo '	competing_locations.tab...'
echo ampl.tab 1 > competing_locations.tab
mysql $connection_string -e "select distinct location_id from _proposed_projects p where (select count(*) from proposed_projects p2 where p.location_id = p2.location_id)>1 and location_id!=0 and technology_id in (SELECT technology_id FROM generator_info g where technology in ('Central_PV','CSP_Trough_No_Storage','CSP_Trough_6h_Storage'));" >> competing_locations.tab
# If there aren't any competing locations, mysql won't print the column header, which in turn causes an error in AMPL. The following if statement will ensure the column header is present in the file as per AMPL's expectations.
if [ `cat competing_locations.tab | wc -l | sed 's/ //g'` -eq 1 ]; then
  echo location_id >> competing_locations.tab
fi

echo '	cap_factor.tab...'
echo ampl.tab 4 1 > cap_factor.tab
mysql $connection_string -e "select project_id, proposed_projects.load_area, proposed_projects.technology, study_hour as hour, cap_factor from _cap_factor_intermittent_sites c join study_hours_all h on (h.hournum=c.hour) join proposed_projects using (project_id) join load_area_info using (area_id) where ( avg_cap_factor_percentile_by_intermittent_tech >= 0.75 or cumulative_avg_MW_tech_load_area <= 5 * total_yearly_load_mwh / 8766 or rank_by_tech_in_load_area <= 10  or technology = 'Wind') and $TIMESAMPLE;" >> cap_factor.tab

echo '	generator_info.tab...'
echo ampl.tab 1 24 > generator_info.tab
mysql $connection_string -e "select technology, technology_id, min_build_year, fuel, heat_rate, construction_time_years, year_1_cost_fraction, year_2_cost_fraction, year_3_cost_fraction, year_4_cost_fraction, year_5_cost_fraction, year_6_cost_fraction, max_age_years, forced_outage_rate, scheduled_outage_rate, intermittent, resource_limited, baseload, min_build_capacity, min_dispatch_fraction, min_runtime, min_downtime, max_ramp_rate_mw_per_hour, startup_fuel_mbtu, storage from generator_info;" >> generator_info.tab

echo '	fuel_costs.tab...'
echo ampl.tab 3 1 > fuel_costs.tab
mysql $connection_string -e "select load_area, fuel, year, fuel_price from fuel_prices_regional where scenario_id = $REGIONAL_FUEL_COST_SCENARIO_ID and year >= $STUDY_START_YEAR and year <= $STUDY_END_YEAR" >> fuel_costs.tab

echo '	fuel_info.tab...'
echo ampl.tab 1 2 > fuel_info.tab
mysql $connection_string -e "select fuel, rps_fuel_category, carbon_content from fuel_info;" >> fuel_info.tab

echo '	fuel_qualifies_for_rps.tab...'
echo ampl.tab 2 1 > fuel_qualifies_for_rps.tab
mysql $connection_string -e "select load_area, rps_fuel_category, qualifies from fuel_qualifies_for_rps;" >> fuel_qualifies_for_rps.tab
