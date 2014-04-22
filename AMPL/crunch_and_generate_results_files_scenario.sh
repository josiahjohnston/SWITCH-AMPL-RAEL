#!/bin/bash
# import_results_into_postgres.sh
# SYNOPSIS
#		./import_results_into_postgres.sh 
# DESCRIPTION
# 	Pull input data for Switch from databases and other sources, formatting it for AMPL
# This script assumes that the input database has already been built by the script compile_switch_china.sql, DefineScenarios.sql, new_tables_for_db.sql, Setup_Study_Hours.sql, table_edits.sql.
# 
# INPUTS
#  --help                   Print this message
#  -t | --tunnel            Initiate an ssh tunnel to connect to the database. This won't work if ssh prompts you for your password.
#  -u [DB Username]
#  -p [DB Password]
#  -D [DB name]
#  -P/--port [port number]
#  -h [DB server]
#  -np | --no-password      Do not prompt for or use a password to connect to the database
# All arguments are optional.

# This function assumes that the lines at the top of the file that start with a # and a space or tab 
# comprise the help message. It prints the matching lines with the prefix removed and stops at the first blank line.
# Consequently, there needs to be a blank line separating the documentation of this program from this "help" function
#function print_help {
#	last_line=$(( $(egrep '^[ \t]*$' -n -m 1 $0 | sed 's/:.*//') - 1 ))
#	head -n $last_line $0 | sed -e '/^#[ 	]/ !d' -e 's/^#[ 	]//'
#}

# Import SWITCH input data from the results text files into the Switch database

##########################
# Default values
#write_to_path='results'
read SCENARIO_ID < scenario_id.txt
#read TRAINING_SET_ID < training_set_id.txt
db_server="switch-db2.erg.berkeley.edu"
DB_name="switch_china"
port=3306
ssh_tunnel=0


results_graphing_dir="results_for_graphing"
# check if results_for_graphing directory exists and make it if it does not
if [ ! -d $results_graphing_dir ]; then
  echo "Making Results Directory For Output Graphing"
  mkdir $results_graphing_dir
fi 
results_dir="results"
path_dir=$(pwd)

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
		print_help; exit ;;
esac
done

##########################
# Get the user name and password 
default_user=$(whoami)
if [ ! -n "$user" ]
then 
	printf "User name for PostGreSQL $DB_name on $db_server [$default_user]? "
	read user
	if [ -z "$user" ]; then 
	  user="$default_user"
	fi
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
  local_port=5432
  is_port_free $local_port
  while [ $? -eq 0 ]; do
    local_port=$((local_port+1))
    is_port_free $local_port
  done
  ssh -N -p 22 -c 3des $db_server -L $local_port/$db_server/$port &
  ssh_pid=$!
  sleep 1
  connection_string="psql -p $local_port -d $DB_name -U $user -h 127.0.0.1 "
  trap "clean_up;" EXIT INT TERM 
else
  connection_string="psql -U $user -h $db_server -d $DB_name "
fi

test_connection=`$connection_string -t -c "select count(*) from province_info;"`

if [ ! -n "$test_connection" ]
then
	connection_string=`echo "$connection_string" | sed -e "s/ -p[^ ]* / -pXXX /"`
	echo "Could not connect to database with settings: $connection_string"
	exit 0
fi

echo 'Create scenario id table for crunching results'
$connection_string -t -c "DROP TABLE IF EXISTS scenario_id_crunch_results; SELECT $SCENARIO_ID AS results_scenario_id INTO scenario_id_crunch_results;"


####################################################
# Crunch through the data
  echo 'Crunching the data...'
  data_crunch_path=tmp_data_crunch$$.sql
  #echo 'set @scenario_id := '"${SCENARIO_ID};" >> $data_crunch_path
  cat crunch_results_scenario.sql >> $data_crunch_path
  $connection_string < $data_crunch_path
  rm $data_crunch_path

###################################################
# Build pivot-table like views that are easier to read

echo 'Done crunching the data...'
echo 'Outputting Excel friendly summary files'

# Make a temporary file of investment periods
invest_periods_path=tmp_invest_periods$$.txt
$connection_string -A -t -c "select distinct(period) from _gen_summary_tech where scenario_id=$SCENARIO_ID order by period;" > $invest_periods_path
# $connection_string -A -t -c "select distinct(period) from _gen_summary_tech order by period;" > $invest_periods_path


# Average Generation on a TECH basis....
# Build a long query that will make one column for each investment period
select_gen_summary="SELECT distinct g.scenario_id, technology, g.carbon_cost"
while read inv_period; do 
  select_gen_summary=$select_gen_summary", coalesce((select round(avg_power) from $DB_name.china._gen_summary_tech where technology_id = g.technology_id and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id),0) as "\"$inv_period"\""
done < $invest_periods_path
select_gen_summary=$select_gen_summary" FROM $DB_name.china._gen_summary_tech g join $DB_name.china.generator_tech_fuel using(technology_id);"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_summary_tech_by_period AS $select_gen_summary"

# Average Generation on a FUEL basis....
# Build a long query that will make one column for each investment period
select_gen_summary="SELECT distinct g.scenario_id, g.fuel, g.carbon_cost"
while read inv_period; do 
  select_gen_summary=$select_gen_summary", coalesce((select round(avg_power) from $DB_name.china._gen_summary_fuel where fuel = g.fuel and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id),0) as "\"$inv_period"\""
done < $invest_periods_path
select_gen_summary=$select_gen_summary" FROM $DB_name.china._gen_summary_fuel g;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_summary_fuel_by_period AS $select_gen_summary"


# Generation capacity on a TECH basis..
# Build a long query that will make one column for each investment period
select_gen_cap_summary="SELECT distinct g.scenario_id, technology, g.carbon_cost"
while read inv_period; do 
  select_gen_cap_summary=$select_gen_cap_summary", coalesce((select round(capacity) from $DB_name.china._gen_cap_summary_tech where technology_id = g.technology_id and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id),0) as "\"$inv_period"\""
done < $invest_periods_path
select_gen_cap_summary=$select_gen_cap_summary" FROM $DB_name.china._gen_cap_summary_tech g join $DB_name.china.generator_tech_fuel using(technology_id);"
$connection_string -A -t -c "CREATE OR REPLACE VIEW gen_cap_summary_tech_by_period AS $select_gen_cap_summary"

# Generation capacity on a FUEL basis..
# Build a long query that will make one column for each investment period
select_gen_cap_summary="SELECT distinct g.scenario_id, g.fuel, g.carbon_cost"
while read inv_period; do 
  select_gen_cap_summary=$select_gen_cap_summary", coalesce((select round(capacity) from $DB_name.china._gen_cap_summary_fuel where fuel = g.fuel and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id),0) as "\"$inv_period"\""
done < $invest_periods_path
select_gen_cap_summary=$select_gen_cap_summary" FROM $DB_name.china._gen_cap_summary_fuel g;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_cap_summary_fuel_by_period AS $select_gen_cap_summary"


# TECHNOLOGIES --------

# Make a temporary file of generation technologies
echo 'Getting a list of generation technologies and making technology-specific pivot tables...'
tech_path=tmp_tech$$.txt
#tech_path=tmp_tech18104.txt
#$connection_string -A -t -c "select technology_id, technology from china.generator_tech_fuel where technology_id in (select distinct technology_id from china._gen_summary_tech WHERE scenario_id = $SCENARIO_ID) order by fuel;" > $tech_path
$connection_string -A -t -c "select technology_id, technology from generator_tech_fuel where technology_id in (select distinct technology_id from china._gen_summary_tech) order by fuel;" > $tech_path
#Correct the pipes that later are problematic, replace with space
sed -i '' -e 's/|/ /g' $tech_path


# The code below builds long queries that will make one column for each generation technology

#echo 'gen_cap_summary_by_tech'
# gen_cap_summary_by_tech
select_gen_cap_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period"
while read technology_id technology; do 
  select_gen_cap_summary=$select_gen_cap_summary", coalesce((select round(capacity) FROM $DB_name.china._gen_cap_summary_tech where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period), 0) as $technology"
done < $tech_path
select_gen_cap_summary=$select_gen_cap_summary" FROM $DB_name.china._gen_cap_summary_tech g order by scenario_id, carbon_cost, period;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_cap_summary_by_tech AS $select_gen_cap_summary"

#echo 'gen_cap_summary_by_tech_la'
# gen_cap_summary_by_tech_la
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period, g.province"
while read technology_id technology; do 
  select_dispatch_summary=$select_dispatch_summary", coalesce((select round(capacity) FROM $DB_name.china._gen_cap_summary_tech_la where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period and province = g.province),0) as $technology"
done < $tech_path
select_dispatch_summary=$select_dispatch_summary" FROM $DB_name.china._gen_cap_summary_tech_la g order by scenario_id, carbon_cost, period, province;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_cap_summary_by_tech_la AS $select_dispatch_summary"

#echo 'gen_summary_by_tech'
# gen_summary_by_tech
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period"
while read technology_id technology; do 
  select_dispatch_summary=$select_dispatch_summary", coalesce((select round(avg_power) FROM $DB_name.china._gen_summary_tech where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period),0) as $technology"
done < $tech_path
select_dispatch_summary=$select_dispatch_summary" FROM $DB_name.china._gen_summary_tech g order by scenario_id, carbon_cost, period;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_summary_by_tech AS $select_dispatch_summary"

#echo 'gen_summary_by_tech_la'
# gen_summary_by_tech_la
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period, g.province"
while read technology_id technology; do 
  select_dispatch_summary=$select_dispatch_summary", coalesce((select round(avg_power) FROM $DB_name.china._gen_summary_tech_la where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period and province = g.province),0) as $technology"
done < $tech_path
select_dispatch_summary=$select_dispatch_summary" FROM $DB_name.china._gen_summary_tech_la g order by scenario_id, carbon_cost, period, province;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_summary_by_tech_la AS $select_dispatch_summary"

#echo 'gen_hourly_summary_by_tech'
# gen_hourly_summary_by_tech
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, (select period FROM $DB_name.china._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as period, (select study_date FROM $DB_name.china._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as study_date, (select hours_in_sample FROM $DB_name.china._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as hours_in_sample, (select study_month FROM $DB_name.china._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as study_month, (select hour_of_day FROM $DB_name.china._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as hour_of_day"
while read technology_id technology; do 
  select_dispatch_summary=$select_dispatch_summary", coalesce((select round(system_power) FROM $DB_name.china._gen_hourly_summary_tech where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour ),0) as $technology"
done < $tech_path
select_dispatch_summary=$select_dispatch_summary", system_load FROM $DB_name.china._gen_hourly_summary_tech g join china.system_load_summary_hourly using (scenario_id, carbon_cost, study_hour) order by scenario_id, carbon_cost, period, study_month, study_date, hour_of_day;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_hourly_summary_by_tech AS $select_dispatch_summary"

#echo 'gen_hourly_summary_la_by_tech'
# gen_hourly_summary_la_by_tech
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, g.province, (select period FROM $DB_name.china._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and province = g.province limit 1) as period, (select study_date FROM $DB_name.china._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and province = g.province limit 1) as study_date, (select hours_in_sample FROM $DB_name.china._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and province = g.province limit 1) as hours_in_sample, (select study_month FROM $DB_name.china._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and province = g.province limit 1) as study_month, (select hour_of_day FROM $DB_name.china._gen_hourly_summary_tech where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and province = g.province limit 1) as hour_of_day"
while read technology_id technology; do 
  select_dispatch_summary=$select_dispatch_summary", coalesce((select round(system_power) FROM $DB_name.china._gen_hourly_summary_tech_la where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and province = g.province),0) as $technology"
done < $tech_path
select_dispatch_summary=$select_dispatch_summary", _system_load.system_power FROM $DB_name.china._gen_hourly_summary_tech_la g join china._system_load using (scenario_id, carbon_cost, study_hour, province) order by scenario_id, carbon_cost, period, study_month, study_date, hour_of_day;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_hourly_summary_la_by_tech AS $select_dispatch_summary"




# FUELS - do the same as above but on a fuel basis
# Make a temporary file of fuels
echo 'Getting a list of fuels and making fuel-specific pivot tables...'
fuel_path=tmp_fuel$$.txt
#$connection_string -A -t -c "select distinct on (fuel) fuel from $DB_name.china._gen_summary_fuel WHERE scenario_id=$SCENARIO_ID order by fuel;" > $fuel_path
$connection_string -A -t -c "select distinct on (fuel) fuel from $DB_name.china._gen_summary_fuel order by fuel;" > $fuel_path

# The code below builds long queries that will make one column for each fuel

# gen_cap_summary_by_fuel
select_gen_cap_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period"
while read fuel; do 
  select_gen_cap_summary=$select_gen_cap_summary", coalesce((select round(capacity) FROM $DB_name.china._gen_cap_summary_fuel where fuel='$fuel' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period),0) as $fuel"
done < $fuel_path
select_gen_cap_summary=$select_gen_cap_summary" FROM $DB_name.china._gen_cap_summary_fuel g order by scenario_id, carbon_cost, period;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_cap_summary_by_fuel AS $select_gen_cap_summary"

# gen_cap_summary_by_fuel_la
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period, g.province"
while read fuel; do 
  select_dispatch_summary=$select_dispatch_summary", coalesce((select round(capacity) FROM $DB_name.china._gen_cap_summary_fuel_la where fuel='$fuel' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period and province = g.province),0) as $fuel"
done < $fuel_path
select_dispatch_summary=$select_dispatch_summary" FROM $DB_name.china._gen_cap_summary_fuel_la g order by scenario_id, carbon_cost, period, province;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_cap_summary_by_fuel_la AS $select_dispatch_summary"


# gen_summary_by_fuel 
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period"
while read fuel; do 
  select_dispatch_summary=$select_dispatch_summary", coalesce((select round(avg_power) FROM $DB_name.china._gen_summary_fuel where fuel='$fuel' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period),0) as $fuel"
done < $fuel_path
select_dispatch_summary=$select_dispatch_summary" FROM $DB_name.china._gen_summary_fuel g order by scenario_id, carbon_cost, period;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_summary_by_fuel AS $select_dispatch_summary"


# gen_summary_by_fuel_la
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.period, g.province"
while read fuel; do 
  select_dispatch_summary=$select_dispatch_summary", coalesce((select round(avg_power) FROM $DB_name.china._gen_summary_fuel_la where fuel='$fuel' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and period = g.period and province = g.province),0) as $fuel"
done < $fuel_path
select_dispatch_summary=$select_dispatch_summary" FROM $DB_name.china._gen_summary_fuel_la g order by scenario_id, carbon_cost, period, province;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_summary_by_fuel_la AS $select_dispatch_summary"


# gen_hourly_summary_by_fuel, 
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, (select period FROM $DB_name.china._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as period, (select study_date FROM $DB_name.china._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as study_date, (select hours_in_sample FROM $DB_name.china._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as hours_in_sample, (select study_month FROM $DB_name.china._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as study_month, (select hour_of_day FROM $DB_name.china._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as hour_of_day"
while read fuel; do 
  select_dispatch_summary=$select_dispatch_summary", coalesce((select round(system_power) FROM $DB_name.china._gen_hourly_summary_fuel where fuel='$fuel' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour ),0) as $fuel"
done < $fuel_path
select_dispatch_summary=$select_dispatch_summary", system_load FROM $DB_name.china._gen_hourly_summary_fuel g join china.system_load_summary_hourly using (scenario_id, carbon_cost, study_hour) order by scenario_id, carbon_cost, period, study_month, study_date, hour_of_day;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_hourly_summary_by_fuel AS $select_dispatch_summary"

# gen_hourly_summary_la_by_fuel
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, g.province, (select period FROM $DB_name.china._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and province = g.province limit 1) as period, (select study_date FROM $DB_name.china._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and province = g.province limit 1) as study_date, (select hours_in_sample FROM $DB_name.china._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and province = g.province limit 1) as hours_in_sample, (select study_month FROM $DB_name.china._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and province = g.province limit 1) as study_month, (select hour_of_day FROM $DB_name.china._gen_hourly_summary_fuel where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and province = g.province limit 1) as hour_of_day"
while read fuel; do 
  select_dispatch_summary=$select_dispatch_summary", coalesce((select round(system_power) FROM $DB_name.china._gen_hourly_summary_fuel_la where fuel='$fuel' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and province = g.province),0) as $fuel"
done < $fuel_path
select_dispatch_summary=$select_dispatch_summary", _system_load.system_power FROM $DB_name.china._gen_hourly_summary_fuel_la g join _system_load using (scenario_id, carbon_cost, study_hour, province) order by scenario_id, carbon_cost, period, study_month, study_date, hour_of_day;"
$connection_string -A -t -c "CREATE OR REPLACE VIEW china.gen_hourly_summary_la_by_fuel AS $select_dispatch_summary"


# delete the temporary files
rm $invest_periods_path
rm $tech_path
rm $fuel_path

###################################################
# Export summaries of the results
echo 'Exporting gen_summary_by_tech.txt...'
$connection_string -A -c "select * from china.gen_summary_by_tech;" > $results_graphing_dir/gen_summary_by_tech.txt

echo 'Exporting gen_summary_by_tech_la.txt...'
$connection_string -A -c "select * from china.gen_summary_by_tech_la;" > $results_graphing_dir/gen_summary_by_tech_la.txt

echo 'Exporting gen_summary_by_fuel.txt...'
$connection_string -A -c "select * from china.gen_summary_by_fuel;" > $results_graphing_dir/gen_summary_by_fuel.txt

echo 'Exporting gen_summary_by_fuel_la.txt...'
$connection_string -A -c "select * from china.gen_summary_by_fuel_la;" > $results_graphing_dir/gen_summary_by_fuel_la.txt

echo 'Exporting gen_summary_tech_by_period.txt...'
$connection_string -A -c "select * from china.gen_summary_tech_by_period;" > $results_graphing_dir/gen_summary_tech_by_period.txt

echo 'Exporting gen_summary_fuel_by_period.txt...'
$connection_string -A -c "select * from china.gen_summary_fuel_by_period;" > $results_graphing_dir/gen_summary_fuel_by_period.txt

echo 'Exporting gen_cap_summary_by_tech.txt...'
$connection_string -A -c "select * from china.gen_cap_summary_by_tech;" > $results_graphing_dir/gen_cap_summary_by_tech.txt

echo 'Exporting gen_cap_summary_by_fuel.txt...'
$connection_string -A -c "select * from china.gen_cap_summary_by_fuel;" > $results_graphing_dir/gen_cap_summary_by_fuel.txt

echo 'Exporting gen_cap_summary_by_fuel_la.txt...'
$connection_string -A -c "select * from china.gen_cap_summary_by_fuel_la;" > $results_graphing_dir/gen_cap_summary_by_fuel_la.txt

echo 'Exporting gen_cap_summary_by_tech_la.txt...'
$connection_string -A -c "select * from china.gen_cap_summary_by_tech_la;" > $results_graphing_dir/gen_cap_summary_by_tech_la.txt

echo 'Exporting gen_cap_summary_tech_by_period.txt...'
$connection_string -A -c "select * from china.gen_cap_summary_tech_by_period;" > $results_graphing_dir/gen_cap_summary_tech_by_period.txt

echo 'Exporting gen_cap_summary_fuel_by_period.txt...'
$connection_string -A -c "select * from china.gen_cap_summary_fuel_by_period;" > $results_graphing_dir/gen_cap_summary_fuel_by_period.txt

echo 'Exporting co2_cc.txt...'
$connection_string -A -c "select * from china.co2_cc;" > $results_graphing_dir/co2_cc.txt

echo 'Exporting power_cost_cc.txt...'
$connection_string -A -c "select * from china.power_cost;" > $results_graphing_dir/power_cost_cc.txt

echo 'Exporting system_load_summary.txt...'
$connection_string -A -c "select * from china.system_load_summary;" > $results_graphing_dir/system_load_summary.txt

echo 'Exporting system_load_summary_hourly.txt...'
$connection_string -A -c "select * from china.system_load_summary_hourly;" > $results_graphing_dir/system_load_summary_hourly.txt

## This one doesn't seem to exist, check for trans_cap_summary in prior queries
echo 'Exporting trans_dispatch_summary.txt...'
$connection_string -A -c "select * from china._trans_summary;" > $results_graphing_dir/trans_dispatch_summary.txt

echo 'Exporting trans_cap_summary.txt...'
$connection_string -A -c "select * from china._trans_cap_summary;" > $results_graphing_dir/trans_cap_summary.txt

echo 'Exporting trans_cap_la_summary.txt...'
$connection_string -A -c "select * from china._trans_cap_la_summary;" > $results_graphing_dir/trans_cap_la_summary.txt

echo 'Exporting transmission_directed_hourly.txt...'
$connection_string -A -c "select * from china._transmission_directed_hourly;" > $results_graphing_dir/transmission_directed_hourly.txt

echo 'Exporting transmission_avg_directed.txt...'
$connection_string -A -c "select * from china._transmission_avg_directed;" > $results_graphing_dir/transmission_avg_directed.txt

echo 'Exporting dispatch_summary_hourly_fuel.txt...'
$connection_string -A -c "select * from china.gen_hourly_summary_by_fuel;" > $results_graphing_dir/dispatch_summary_hourly_fuel.txt

echo 'Exporting dispatch_summary_hourly_tech.txt...'
$connection_string -A -c "select * from china.gen_hourly_summary_by_tech;" > $results_graphing_dir/dispatch_summary_hourly_tech.txt

#these take too long at the moment
#echo 'Exporting dispatch_hourly_summary_la_by_tech.txt...'
#$connection_string -A -c "select * from china.gen_hourly_summary_la_by_tech;" > $results_graphing_dir/dispatch_hourly_summary_la_by_tech.txt
#
#echo 'Exporting dispatch_hourly_summary_la_by_fuel.txt...'
#$connection_string -A -c "select * from china.gen_hourly_summary_la_by_fuel;" > $results_graphing_dir/dispatch_hourly_summary_la_by_fuel.txt

echo 'Set the table back to good for import results'
$connection_string -A -c "ALTER TABLE _transmission_dispatch DROP COLUMN study_month, DROP COLUMN hour_of_day;" 
$connection_string -A -c "ALTER TABLE _system_load DROP COLUMN study_month, DROP COLUMN hour_of_day;"