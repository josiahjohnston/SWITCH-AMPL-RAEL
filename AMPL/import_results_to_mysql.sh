#!/bin/bash


##########################
# Constants
read SCENARIO_ID < scenario_id.txt
DB_name='switch_results_wecc_v2_2'
db_server='switch-db1.erg.berkeley.edu'
port=3306
current_dir=`pwd`
results_dir="results"
write_over_prior_results="IGNORE"

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
Ê Ê port=$2
Ê Ê shift 2
Ê ;;
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
  echo " Ê-P/--port [port number]"
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
# Extract a summary of run times for optimizations
echo 'Importing run times...'
runtime_path=runtimes$$.txt
echo "scenario_id,tax,cost_runtime,trans_runtime" > $runtime_path
perl -e'open(LOG,"<switch.log"); my $cost,$trans,$tax; while(my $l=<LOG>) { chomp $l; if($l =~ m/^(\d+) seconds to optimize for cost./ ) { $cost=$1;} elsif($cost && $l =~ m/^(\d+) seconds to optimize for transmission./) {$trans = 1} elsif($trans && $l =~m/Tax=(\d+):/) {$tax=$1; print $ARGV[0].",$cost,$trans,$tax\n"; $cost=$trans=0; } } close(LOG);' $SCENARIO_ID >> $runtime_path
mysql $connection_string -e "load data local infile \"$runtime_path\" $write_over_prior_results into table run_times fields terminated by \",\" optionally enclosed by '\"' ignore 1 lines;"
rm $runtime_path


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
  for file_base_name in gen_cap trans_cap local_td_cap dispatch transmission system_load
  do
   for file_name in `ls results/${file_base_name}_*txt | grep "[[:digit:]]" | grep -v summary` 
   do
	file_path="$current_dir/$file_name"
	echo "    ${file_name}  ->  ${DB_name}._${file_base_name}"
	# Import the file in question into the DB
	case $file_base_name in
	  gen_cap) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _gen_cap (scenario_id, carbon_cost, period, project_id, area_id, @junk, technology_id, @junk, @junk, new, baseload, cogen, fuel, capacity, fixed_cost);") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  trans_cap) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _trans_cap (scenario_id,carbon_cost,period,start_id,end_id,@junk,@junk,tid,new,trans_mw,fixed_cost);") 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  local_td_cap) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _local_td_cap (scenario_id, carbon_cost, period, area_id, @junk, local_td_mw, fixed_cost);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  dispatch) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _dispatch (scenario_id, carbon_cost, period, project_id, area_id, @junk, study_date, study_hour, technology_id, @junk, @junk, new, baseload, cogen, fuel, power, co2_tons, hours_in_sample, heat_rate, fuel_cost, carbon_cost_incurred, variable_o_m_cost);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  transmission) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _transmission_dispatch (scenario_id, carbon_cost, period, receive_id, send_id, @junk, @junk, study_date, study_hour, rps_fuel_category, power_sent, power_received, hours_in_sample);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  system_load) printf "%20s seconds to import %s rows\n" `(time -p mysql $connection_string -e "load data local infile \"$file_path\" $write_over_prior_results into table _system_load (scenario_id, carbon_cost, period, area_id, @junk, study_date, study_hour, power, hours_in_sample);" ) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
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
  cat CrunchResults.sql >> $data_crunch_path
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
mysql $connection_string --column-names=false -e "select distinct(period) from gen_summary where scenario_id=$SCENARIO_ID order by period;" > $invest_periods_path

# Generation....
# Build a long query that will make one column for each investment period
select_gen_summary="SELECT distinct g.scenario_id, technology, g.technology_id, g.carbon_cost"
while read inv_period; do 
	select_gen_summary=$select_gen_summary", (select round(avg_power) from $DB_name._gen_summary where technology_id = g.technology_id and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id) as '$inv_period'"
done < $invest_periods_path
select_gen_summary=$select_gen_summary" FROM $DB_name._gen_summary g join $DB_name.technologies using(technology_id);"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_summary_by_tech AS $select_gen_summary"


# Generation capacity...
# Build a long query that will make one column for each investment period
select_gen_cap_summary="SELECT distinct g.scenario_id, technology, g.technology_id, g.carbon_cost"
while read inv_period; do 
	select_gen_cap_summary=$select_gen_cap_summary", (select round(capacity) from $DB_name._gen_cap_summary where technology_id = g.technology_id and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id) as '$inv_period'"
done < $invest_periods_path
select_gen_cap_summary=$select_gen_cap_summary" FROM $DB_name._gen_cap_summary g join $DB_name.technologies using(technology_id);"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_cap_summary_by_period AS $select_gen_cap_summary"


# Make a temporary file of generation technologies
echo 'Getting a list of generation technologies...'
tech_path=tmp_tech$$.txt
mysql $connection_string --column-names=false -e "select technology_id, technology from technologies where technology_id in (select distinct technology_id from _gen_cap WHERE scenario_id = $SCENARIO_ID);" > $tech_path

# Dispatch summary, 
# Build a long query that will make one column for each generation technology
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, (select period FROM $DB_name._gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'period', (select study_date FROM $DB_name._gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'study_date', (select hours_in_sample FROM $DB_name._gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'hours_in_sample', (select month FROM $DB_name._gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'month', (select hour_of_day FROM $DB_name._gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'hour_of_day'"
while read technology_id technology; do 
	select_dispatch_summary="$select_dispatch_summary"", (select round(power) FROM $DB_name._gen_hourly_summary where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour ) as '$technology'"
done < $tech_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name._gen_hourly_summary g order by scenario_id, carbon_cost, period, month, hour_of_day;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_hourly_summary_by_tech AS $select_dispatch_summary"

# Dispatch by load area and generation technology 
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, g.area_id, load_area, (select period FROM $DB_name._gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'period', (select study_date FROM $DB_name._gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'study_date', (select hours_in_sample FROM $DB_name._gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'hours_in_sample', (select month FROM $DB_name._gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'month', (select hour_of_day FROM $DB_name._gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id limit 1) as 'hour_of_day'"
while read technology_id technology; do 
	select_dispatch_summary="$select_dispatch_summary"", (select round(power) FROM $DB_name._gen_hourly_summary_la where technology_id='$technology_id' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and area_id = g.area_id) as '$technology'"
done < $tech_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name._gen_hourly_summary_la g join $DB_name.load_areas using(area_id) order by scenario_id, carbon_cost, period, month, hour_of_day;"
mysql $connection_string -e "CREATE OR REPLACE VIEW gen_hourly_summary_la_by_tech AS $select_dispatch_summary"


# delete the temporary files
rm $invest_periods_path
rm $tech_path



###################################################
# Export summaries of the results
echo 'Exporting gen_summary.txt...'
mysql $connection_string -e "select * from gen_summary_by_tech WHERE scenario_id = $SCENARIO_ID;" > $results_dir/gen_summary.txt
echo 'Exporting gen_cap_summary.txt...'
mysql $connection_string -e "select * from gen_cap_summary_by_period WHERE scenario_id = $SCENARIO_ID;" > $results_dir/gen_cap_summary.txt
echo 'Exporting dispatch_summary_hourly.csv...'
mysql $connection_string -e "select * from gen_hourly_summary WHERE scenario_id = $SCENARIO_ID;" > $results_dir/dispatch_summary_hourly.csv
echo 'Exporting dispatch_hourly_summary_by_tech.txt...'
mysql $connection_string -e "select * from gen_hourly_summary_by_tech WHERE scenario_id = $SCENARIO_ID order by carbon_cost, period, month, study_date, hour_of_day;" > $results_dir/dispatch_hourly_summary_by_tech.txt
echo 'Exporting co2_cc.csv...'
mysql $connection_string -e "select * from co2_cc WHERE scenario_id = $SCENARIO_ID;" > $results_dir/co2_cc.csv
echo 'Exporting power_cost_cc.csv...'
mysql $connection_string -e "select * from power_cost where scenario_id = $SCENARIO_ID;" > $results_dir/power_cost_cc.csv
echo 'Exporting system_load_summary.csv...'
mysql $connection_string -e "select * from system_load_summary where scenario_id = $SCENARIO_ID;" > $results_dir/system_load_summary.csv
echo 'Exporting trans_cap_new.csv...'
mysql $connection_string -e "select * from trans_cap where new and period=(SELECT max(period) FROM trans_cap where scenario_id=$SCENARIO_ID) AND scenario_id = $SCENARIO_ID;" > $results_dir/trans_cap_new.tcsv
echo 'Exporting trans_cap_exist.csv...'
mysql $connection_string -e "select * from trans_cap where not new and period=(SELECT max(period) FROM trans_cap where scenario_id=$SCENARIO_ID) AND scenario_id = $SCENARIO_ID;" > $results_dir/trans_cap_exist.csv

##########################
# Useful queries that aren't Quite ready for prime time.

# SELECT carbon_cost, period, load_area, fuel, sum(capacity) as capacity FROM gen_cap_summary_la join technologies using (technology) where scenario_id = 122 group by 1,2,3,4

# SELECT scenario_id, carbon_cost, period, study_date, study_hour, hours_in_sample, month, hour_of_day, fuel, sum(power) FROM _gen_hourly_summary join technologies using (technology_id)  where scenario_id = $SCENARIO_ID group by 1,2,3,4,5,6,7,8,9;

# SELECT scenario_id, carbon_cost, period, load_area, fuel, round( sum( power * hours_in_sample ) / ( 8760 * @period_length ) ) as Average_Generation_MW FROM _gen_hourly_summary_la join technologies using (technology_id) join load_areas using (area_id) where scenario_id = 122 group by 2,3,4,5

# select net_transmission.*, transmission_line_id from (SELECT carbon_cost, period, load_area_receive as load_area_start, load_area_from as load_area_end, round( sum( hours_in_sample * ( ( power_sent + power_received ) / 2 ) ) / (8760 * @period_length) ) as average_transmission FROM transmission_dispatch where scenario_id = 122 group by 1,2,3,4) as net_transmission join switch_inputs_wecc_v2_2.transmission_lines using (load_area_start, load_area_end)