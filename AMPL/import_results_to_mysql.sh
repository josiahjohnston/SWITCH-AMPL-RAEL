#!/bin/bash


##########################
# Constants
read SCENARIO_ID < scenario_id.txt
DB_name='switch_results_wecc_v2_2'
db_server='switch-db1.erg.berkeley.edu'
port=3306
current_dir=`pwd`
write_over_prior_results="IGNORE"

results_graphing_dir="results_for_graphing"
# check if results_for_graphing directory exists and make it if it does not
if [ ! -d $results_graphing_dir ]; then
	echo "Making Results Directory For Output Graphing"
	mkdir $results_graphing_dir
fi 
results_dir="results"
# check if results_for_graphing directory exists and make it if it does not
if [ ! -d $results_dir ]; then
	echo "Making Results Directory"
	mkdir $results_dir
fi 

###################################################
# Detect optional command-line arguments
FlushPriorResults=0
SkipImport=0
SkipCrunch=0
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
  --FlushPriorResults) 
	FlushPriorResults=1
	shift 1
  ;;
  --SkipImport) 
    SkipImport=1;
    shift 1
  ;;
  --ExportOnly) 
    SkipImport=1;
    SkipCrunch=1
    shift 1
  ;;
  --help)
    help=1
    shift 1
  ;;
  *)
    echo "Unknown option $1"
    shift 1
  ;;
esac
done

if [ $help = 1 ]
then
  echo "Usage: $0 [OPTIONS]"
  echo "  --help                   Print this menu"
  echo "  -u [DB Username]"
  echo "  -p [DB Password]"
  echo "  -D [DB name]"
  echo "  -P/--port [port number]"
  echo "  -h [DB server]"
  echo "  --FlushPriorResults      Delete all prior results for this scenario before importing."
  echo "  --SkipImport             Just crunch the results, don't import any files"
  echo "  --ExportOnly             Only export summaries of the results, don't import or crunch data in the DB"
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
test_connection=`mysql $connection_string --column-names=false -e "show tables;"`
if [ -z "$test_connection" ]
then
  connection_string=`echo "$connection_string" | sed -e "s/ -p[^ ]* / -pXXX /"`
  echo "Could not connect to database with settings: $connection_string"
  exit 0
fi


###################################################
# Clear out the prior instance of this run if requested
# You can do this manually with this SQL command: select clear_scenario_results(SCENARIO_ID);
if [ $FlushPriorResults = 1 ]; then
  rewrite_results="REPLACE"
  echo "Flushing Prior results for scenario ${SCENARIO_ID}"
  mysql $connection_string --column-names=false -e "select clear_scenario_results(${SCENARIO_ID});"
fi

###################################################
# Import all of the results files into the DB
if [ $SkipImport = 0 ]; then
  echo 'Importing results files...'

  ###################################################
  # import a summary of run times for various processes
  # To do: add time for database export, storing results, compiling, etc.
  echo 'Importing run times...'
  printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$results_dir/run_times.txt\" $write_over_prior_results into table run_times ignore 1 lines (scenario_id, carbon_cost, process_type, time_seconds);") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$results_dir/run_times.txt" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
  
  # now import all of the non-runtime results
  for file_base_name in gen_cap trans_cap local_td_cap dispatch transmission_dispatch storage_dispatch system_load existing_trans_cost
  do
   for file_name in `ls $results_dir/${file_base_name}_*txt | grep "[[:digit:]]"` 
   do
	file_path="$current_dir/$file_name"
	echo "    ${file_name}  ->  ${DB_name}._${file_base_name}"
	# Import the file in question into the DB
	case $file_base_name in
	  gen_cap) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _gen_cap ignore 1 lines (scenario_id, carbon_cost, period, project_id, area_id, @junk, technology_id, @junk, @junk, new, baseload, cogen, fuel, capacity, capital_cost, fixed_o_m_cost);") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  trans_cap) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _trans_cap ignore 1 lines (scenario_id,carbon_cost,period,transmission_line_id, start_id,end_id,@junk,@junk,new,trans_mw,fixed_cost);") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  local_td_cap) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _local_td_cap ignore 1 lines (scenario_id, carbon_cost, period, area_id, @junk, new, local_td_mw, fixed_cost);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  dispatch) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _dispatch ignore 1 lines (scenario_id, carbon_cost, period, project_id, area_id, @junk, study_date, study_hour, technology_id, @junk, @junk, new, baseload, cogen, fuel, power, co2_tons, hours_in_sample, heat_rate, fuel_cost, carbon_cost_incurred, variable_o_m_cost);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  transmission_dispatch) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _transmission_dispatch ignore 1 lines (scenario_id, carbon_cost, period, transmission_line_id, receive_id, send_id, @junk, @junk, study_date, study_hour, rps_fuel_category, power_sent, power_received, hours_in_sample);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  storage_dispatch) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _storage_dispatch ignore 1 lines (scenario_id, carbon_cost, period, project_id, area_id, @junk, study_date, study_hour, technology_id, @junk,  storage_efficiency, new, rps_fuel_category, hours_in_sample, power, variable_o_m_cost);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  system_load) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _system_load ignore 1 lines (scenario_id, carbon_cost, period, area_id, @junk, study_date, study_hour, power, hours_in_sample);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  existing_trans_cost) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _existing_trans_cost ignore 1 lines (scenario_id, carbon_cost, period, area_id, @junk, fixed_cost);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	 esac
   done
  done
else
  echo 'Skipping Import.'
fi

###################################################
# Crunch through the data
if [ $SkipCrunch = 0 ]; then
  echo 'Crunching the data...'
  data_crunch_path=tmp_data_crunch$$.sql
  echo "set @scenario_id := ${SCENARIO_ID};" >> $data_crunch_path
  cat crunch_results.sql >> $data_crunch_path
  mysql $connection_string < $data_crunch_path
  rm $data_crunch_path
else
  echo 'Skipping data crunching.'
fi

###################################################
# Build pivot-table like views that are easier to read

echo 'Done crunching the data...'
echo 'Outputting Excel friendly summary files'

# Make a temporary file of investment periods
invest_periods_path=tmp_invest_periods$$.txt
mysql $connection_string --column-names=false -e "select distinct(period) from gen_summary_tech where scenario_id=$SCENARIO_ID order by period;" > $invest_periods_path



# Average Generation on a TECH basis....
# Build a long query that will make one column for each investment period
select_gen_summary="SELECT distinct g.scenario_id, technology, g.carbon_cost"
while read inv_period; do 
	select_gen_summary=$select_gen_summary", IFNULL((select round(avg_power) from $DB_name._gen_summary_tech where technology_id = g.technology_id and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id),0) as '$inv_period'"
done < $invest_periods_path
select_gen_summary=$select_gen_summary" FROM $DB_name._gen_summary_tech g join $DB_name.technologies using(technology_id);"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_summary_tech_by_period AS $select_gen_summary"

# Average Generation on a FUEL basis....
# Build a long query that will make one column for each investment period
select_gen_summary="SELECT distinct g.scenario_id, g.fuel, g.carbon_cost"
while read inv_period; do 
	select_gen_summary=$select_gen_summary", IFNULL((select round(avg_power) from $DB_name.gen_summary_fuel where fuel = g.fuel and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id),0) as '$inv_period'"
done < $invest_periods_path
select_gen_summary=$select_gen_summary" FROM $DB_name.gen_summary_fuel g;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_summary_fuel_by_period AS $select_gen_summary"


# Generation capacity on a TECH basis..
# Build a long query that will make one column for each investment period
select_gen_cap_summary="SELECT distinct g.scenario_id, technology, g.carbon_cost"
while read inv_period; do 
	select_gen_cap_summary=$select_gen_cap_summary", IFNULL((select round(capacity) from $DB_name._gen_cap_summary_tech where technology_id = g.technology_id and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id),0) as '$inv_period'"
done < $invest_periods_path
select_gen_cap_summary=$select_gen_cap_summary" FROM $DB_name._gen_cap_summary_tech g join $DB_name.technologies using(technology_id);"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_cap_summary_tech_by_period AS $select_gen_cap_summary"

# Generation capacity on a FUEL basis..
# Build a long query that will make one column for each investment period
select_gen_cap_summary="SELECT distinct g.scenario_id, g.fuel, g.carbon_cost"
while read inv_period; do 
	select_gen_cap_summary=$select_gen_cap_summary", IFNULL((select round(capacity) from $DB_name.gen_cap_summary_fuel where fuel = g.fuel and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id),0) as '$inv_period'"
done < $invest_periods_path
select_gen_cap_summary=$select_gen_cap_summary" FROM $DB_name.gen_cap_summary_fuel g;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_cap_summary_fuel_by_period AS $select_gen_cap_summary"


# TECHNOLOGIES --------

# Make a temporary file of generation technologies
echo 'Getting a list of generation technologies and making technology-specific pivot tables...'
tech_path=tmp_tech$$.txt
mysql $connection_string --column-names=false -e "select technology_id, technology from technologies where technology_id in (select distinct technology_id from _gen_summary_tech WHERE scenario_id = $SCENARIO_ID) order by fuel;" > $tech_path

# The code below builds long queries that will make one column for each generation technology

# gen_cap_summary_by_tech
select_gen_cap_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period"
while read technology_id technology; do 
	select_gen_cap_summary="$select_gen_cap_summary"", IFNULL((select round(capacity) FROM $DB_name._gen_cap_summary_tech where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period),0) as '$technology'"
done < $tech_path
select_gen_cap_summary="$select_gen_cap_summary"" FROM $DB_name._gen_cap_summary_tech g order by scenario_id, carbon_cost, period;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_cap_summary_by_tech AS $select_gen_cap_summary"

# gen_cap_summary_by_tech_la
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period, load_area"
while read technology_id technology; do 
	select_dispatch_summary="$select_dispatch_summary"", IFNULL((select round(capacity) FROM $DB_name._gen_cap_summary_tech_la where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period and area_id = g.area_id),0) as '$technology'"
done < $tech_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name._gen_cap_summary_tech_la g join load_areas using (area_id) order by scenario_id, carbon_cost, period, load_area;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_cap_summary_by_tech_la AS $select_dispatch_summary"



# gen_summary_by_tech
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period"
while read technology_id technology; do 
	select_dispatch_summary="$select_dispatch_summary"", IFNULL((select round(avg_power) FROM $DB_name._gen_summary_tech where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period),0) as '$technology'"
done < $tech_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name._gen_summary_tech g order by scenario_id, carbon_cost, period;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_summary_by_tech AS $select_dispatch_summary"

# gen_summary_by_tech_la
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period, load_area"
while read technology_id technology; do 
	select_dispatch_summary="$select_dispatch_summary"", IFNULL((select round(avg_power) FROM $DB_name._gen_summary_tech_la where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period and area_id = g.area_id),0) as '$technology'"
done < $tech_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name._gen_summary_tech_la g join load_areas using (area_id) order by scenario_id, carbon_cost, period, load_area;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_summary_by_tech_la AS $select_dispatch_summary"

# gen_hourly_summary_by_tech
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, (select period FROM $DB_name._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'period', (select study_date FROM $DB_name._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'study_date', (select hours_in_sample FROM $DB_name._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'hours_in_sample', (select month FROM $DB_name._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'month', (select hour_of_day FROM $DB_name._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'hour_of_day'"
while read technology_id technology; do 
	select_dispatch_summary="$select_dispatch_summary"", IFNULL((select round(power) FROM $DB_name._gen_hourly_summary_tech where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour ),0) as '$technology'"
done < $tech_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name._gen_hourly_summary_tech g order by scenario_id, carbon_cost, period, month, study_date, hour_of_day;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_hourly_summary_by_tech AS $select_dispatch_summary"

# gen_hourly_summary_la_by_tech
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, g.area_id, load_area, (select period FROM $DB_name._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'period', (select study_date FROM $DB_name._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'study_date', (select hours_in_sample FROM $DB_name._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'hours_in_sample', (select month FROM $DB_name._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'month', (select hour_of_day FROM $DB_name._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'hour_of_day'"
while read technology_id technology; do 
	select_dispatch_summary="$select_dispatch_summary"", IFNULL((select round(power) FROM $DB_name._gen_hourly_summary_tech_la where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id),0) as '$technology'"
done < $tech_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name._gen_hourly_summary_tech_la g join $DB_name.load_areas using(area_id) order by scenario_id, carbon_cost, period, month, study_date, hour_of_day;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_hourly_summary_la_by_tech AS $select_dispatch_summary"




# FUELS - do the same as above but on a fuel basis
# Make a temporary file of fuels
echo 'Getting a list of fuels and making fuel-specific pivot tables...'
fuel_path=tmp_fuel$$.txt
mysql $connection_string --column-names=false -e "select distinct(fuel) from $DB_name.gen_summary_fuel WHERE scenario_id=$SCENARIO_ID order by fuel;" > $fuel_path

# The code below builds long queries that will make one column for each fuel

# gen_cap_summary_by_fuel
select_gen_cap_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period"
while read fuel; do 
	select_gen_cap_summary="$select_gen_cap_summary"", IFNULL((select round(capacity) FROM $DB_name.gen_cap_summary_fuel where fuel='$fuel' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period),0) as '$fuel'"
done < $fuel_path
select_gen_cap_summary="$select_gen_cap_summary"" FROM $DB_name.gen_cap_summary_fuel g order by scenario_id, carbon_cost, period;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_cap_summary_by_fuel AS $select_gen_cap_summary"

# gen_cap_summary_by_fuel_la
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period, g.load_area"
while read fuel; do 
	select_dispatch_summary="$select_dispatch_summary"", IFNULL((select round(capacity) FROM $DB_name.gen_cap_summary_fuel_la where fuel='$fuel' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period and load_area = g.load_area),0) as '$fuel'"
done < $fuel_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name.gen_cap_summary_fuel_la g order by scenario_id, carbon_cost, period, load_area;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_cap_summary_by_fuel_la AS $select_dispatch_summary"


# gen_summary_by_fuel 
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period"
while read fuel; do 
	select_dispatch_summary="$select_dispatch_summary"", IFNULL((select round(avg_power) FROM $DB_name.gen_summary_fuel where fuel='$fuel' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period),0) as '$fuel'"
done < $fuel_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name.gen_summary_fuel g order by scenario_id, carbon_cost, period;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_summary_by_fuel AS $select_dispatch_summary"


# gen_summary_by_fuel_la
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period, g.load_area"
while read fuel; do 
	select_dispatch_summary="$select_dispatch_summary"", IFNULL((select round(avg_power) FROM $DB_name.gen_summary_fuel_la where fuel='$fuel' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period and load_area = g.load_area),0) as '$fuel'"
done < $fuel_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name.gen_summary_fuel_la g order by scenario_id, carbon_cost, period, load_area;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_summary_by_fuel_la AS $select_dispatch_summary"


# gen_hourly_summary_by_fuel, 
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, (select period FROM $DB_name._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'period', (select study_date FROM $DB_name._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'study_date', (select hours_in_sample FROM $DB_name._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'hours_in_sample', (select month FROM $DB_name._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'month', (select hour_of_day FROM $DB_name._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'hour_of_day'"
while read fuel; do 
	select_dispatch_summary="$select_dispatch_summary"", IFNULL((select round(power) FROM $DB_name._gen_hourly_summary_fuel where fuel='$fuel' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour ),0) as '$fuel'"
done < $fuel_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name._gen_hourly_summary_fuel g order by scenario_id, carbon_cost, period, month, study_date, hour_of_day;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_hourly_summary_by_fuel AS $select_dispatch_summary"

# gen_hourly_summary_la_by_fuel
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, g.area_id, load_area, (select period FROM $DB_name._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'period', (select study_date FROM $DB_name._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'study_date', (select hours_in_sample FROM $DB_name._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'hours_in_sample', (select month FROM $DB_name._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'month', (select hour_of_day FROM $DB_name._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'hour_of_day'"
while read fuel; do 
	select_dispatch_summary="$select_dispatch_summary"", IFNULL((select round(power) FROM $DB_name._gen_hourly_summary_fuel_la where fuel='$fuel' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id),0) as '$fuel'"
done < $fuel_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name._gen_hourly_summary_fuel_la g join $DB_name.load_areas using(area_id) order by scenario_id, carbon_cost, period, month, study_date, hour_of_day;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_hourly_summary_la_by_fuel AS $select_dispatch_summary"


# delete the temporary files
rm $invest_periods_path
rm $tech_path
rm $fuel_path


###################################################
# Export summaries of the results
echo 'Exporting gen_summary_by_tech.txt...'
mysql $connection_string -e "select * from gen_summary_by_tech WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/gen_summary_by_tech.txt

echo 'Exporting gen_summary_by_tech_la.txt...'
mysql $connection_string -e "select * from gen_summary_by_tech_la WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/gen_summary_by_tech_la.txt

echo 'Exporting gen_summary_by_fuel.txt...'
mysql $connection_string -e "select * from gen_summary_by_fuel WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/gen_summary_by_fuel.txt

echo 'Exporting gen_summary_by_fuel_la.txt...'
mysql $connection_string -e "select * from gen_summary_by_fuel_la WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/gen_summary_by_fuel_la.txt

echo 'Exporting gen_summary_tech_by_period.txt...'
mysql $connection_string -e "select * from gen_summary_tech_by_period WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/gen_summary_tech_by_period.txt

echo 'Exporting gen_summary_fuel_by_period.txt...'
mysql $connection_string -e "select * from gen_summary_fuel_by_period WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/gen_summary_fuel_by_period.txt

echo 'Exporting gen_cap_summary_by_tech.txt...'
mysql $connection_string -e "select * from gen_cap_summary_by_tech WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/gen_cap_summary_by_tech.txt

echo 'Exporting gen_cap_summary_by_fuel.txt...'
mysql $connection_string -e "select * from gen_cap_summary_by_fuel WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/gen_cap_summary_by_fuel.txt

echo 'Exporting gen_cap_summary_by_fuel_la.txt...'
mysql $connection_string -e "select * from gen_cap_summary_by_fuel_la WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/gen_cap_summary_by_fuel_la.txt

echo 'Exporting gen_cap_summary_by_tech_la.txt...'
mysql $connection_string -e "select * from gen_cap_summary_by_tech_la WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/gen_cap_summary_by_tech_la.txt

echo 'Exporting gen_cap_summary_tech_by_period.txt...'
mysql $connection_string -e "select * from gen_cap_summary_tech_by_period WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/gen_cap_summary_tech_by_period.txt

echo 'Exporting gen_cap_summary_fuel_by_period.txt...'
mysql $connection_string -e "select * from gen_cap_summary_fuel_by_period WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/gen_cap_summary_fuel_by_period.txt

echo 'Exporting dispatch_summary_hourly_tech.txt...'
mysql $connection_string -e "select * from gen_hourly_summary_by_tech WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/dispatch_summary_hourly_tech.txt

echo 'Exporting dispatch_hourly_summary_la_by_tech.txt...'
mysql $connection_string -e "select * from gen_hourly_summary_la_by_tech WHERE scenario_id = $SCENARIO_ID order by carbon_cost, period, month, study_date, hour_of_day;" > $results_graphing_dir/dispatch_hourly_summary_la_by_tech.txt

echo 'Exporting dispatch_summary_hourly_fuel.txt...'
mysql $connection_string -e "select * from gen_hourly_summary_by_fuel WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/dispatch_summary_hourly_fuel.txt

echo 'Exporting dispatch_hourly_summary_la_by_fuel.txt...'
mysql $connection_string -e "select * from gen_hourly_summary_la_by_fuel WHERE scenario_id = $SCENARIO_ID order by carbon_cost, period, month, study_date, hour_of_day;" > $results_graphing_dir/dispatch_hourly_summary_la_by_fuel.txt

echo 'Exporting co2_cc.txt...'
mysql $connection_string -e "select * from co2_cc WHERE scenario_id = $SCENARIO_ID;" > $results_graphing_dir/co2_cc.txt

echo 'Exporting power_cost_cc.txt...'
mysql $connection_string -e "select * from power_cost where scenario_id = $SCENARIO_ID;" > $results_graphing_dir/power_cost_cc.txt

echo 'Exporting system_load_summary.txt...'
mysql $connection_string -e "select * from system_load_summary where scenario_id = $SCENARIO_ID;" > $results_graphing_dir/system_load_summary.txt

echo 'Exporting trans_cap_summary.txt...'
mysql $connection_string -e "select * from trans_cap_summary where scenario_id = $SCENARIO_ID;" > $results_graphing_dir/trans_cap_summary.txt

echo 'Exporting transmission_directed_hourly.txt...'
mysql $connection_string -e "select * from transmission_directed_hourly where scenario_id = $SCENARIO_ID;" > $results_graphing_dir/transmission_directed_hourly.txt

echo 'Exporting transmission_avg_directed.txt...'
mysql $connection_string -e "select * from transmission_avg_directed where scenario_id = $SCENARIO_ID;" > $results_graphing_dir/transmission_avg_directed.txt


## TODO:
# consumption???
