#!/bin/bash


##########################
# Constants
read SCENARIO_ID < scenario_id.txt
DB_name='switch_results_wecc_v2_2'
db_server='switch-db1.erg.berkeley.edu'
current_dir=`pwd`
results_dir="results"
write_over_prior_results="IGNORE"

###################################################
# Detect optional command-line arguments
FlushPriorResults=0
SkipImport=0
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
  echo "  -h [DB server]"
  echo "  --FlushPriorResults      Delete all prior results for this scenario before importing."
  echo "  --SkipImport             Just crunch the results, don't import any files"
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

###################################################
# Extract a summary of run times for optimizations
echo 'Importing run times...'
runtime_path=runtimes$$.txt
echo "scenario_id,tax,cost_runtime,trans_runtime" > $runtime_path
perl -e'open(LOG,"<switch.log"); my $cost,$trans,$tax; while(my $l=<LOG>) { chomp $l; if($l =~ m/^(\d+) seconds to optimize for cost./ ) { $cost=$1;} elsif($cost && $l =~ m/^(\d+) seconds to optimize for transmission./) {$trans = 1} elsif($trans && $l =~m/Tax=(\d+):/) {$tax=$1; print $ARGV[0].",$cost,$trans,$tax\n"; $cost=$trans=0; } } close(LOG);' $SCENARIO_ID >> $runtime_path
mysql -h $db_server -u $user -p$password -e "use $DB_name; load data local infile \"$runtime_path\" $write_over_prior_results into table run_times fields terminated by \",\" optionally enclosed by '\"' ignore 1 lines;"
rm $runtime_path


###################################################
# Clear out the prior instance of this run if requested
# You can do this manually with this SQL command: select clear_scenario_results(SCENARIO_ID);
if [ $FlushPriorResults = 1 ]; then
  rewrite_results="REPLACE"
  echo "Flushing Prior results for scenario ${SCENARIO_ID}"
  mysql -h $db_server -u $user -p$password --column-names=false -e "select clear_scenario_results(${SCENARIO_ID});" $DB_name
fi

###################################################
# Import all of the results files into the DB
if [ $SkipImport = 0 ]; then
  echo 'Importing results files...'
  for file_base_name in gen_cap trans_cap local_td_cap dispatch transmission system_load
  do
   for file_name in `ls results/${file_base_name}_*txt | grep "[[:digit:]]"`
   do
	file_path="$current_dir/$file_name"
	echo "    ${file_name}  ->  ${DB_name}._${file_base_name}"
	# Import the file in question into the DB
	case $file_base_name in
	  gen_cap) printf "%20s seconds to import %s rows\n" `(time -p mysql -h $db_server -u $user -p$password -e "load data local infile \"$file_path\" $write_over_prior_results into table _gen_cap (scenario_id, carbon_cost, period, project_id, area_id, @junk, technology_id, @junk, @junk, new, baseload, cogen, fuel, capacity, fixed_cost);" $DB_name) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  trans_cap) printf "%20s seconds to import %s rows\n" `(time -p mysql -h $db_server -u $user -p$password -e "load data local infile \"$file_path\" $write_over_prior_results into table _trans_cap (scenario_id,carbon_cost,period,start_id,end_id,@junk,@junk,tid,new,trans_mw,fixed_cost);" $DB_name) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  local_td_cap) printf "%20s seconds to import %s rows\n" `(time -p mysql -h $db_server -u $user -p$password -e "load data local infile \"$file_path\" $write_over_prior_results into table _local_td_cap (scenario_id, carbon_cost, period, area_id, @junk, local_td_mw, fixed_cost);" $DB_name) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  dispatch) printf "%20s seconds to import %s rows\n" `(time -p mysql -h $db_server -u $user -p$password -e "load data local infile \"$file_path\" $write_over_prior_results into table _dispatch (scenario_id, carbon_cost, period, project_id, area_id, @junk, study_date, study_hour, technology_id, @junk, @junk, new, baseload, cogen, fuel, power, co2_tons, hours_in_sample, heat_rate, fuel_cost_tot, carbon_cost_tot, variable_o_m_tot);" $DB_name) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  transmission) printf "%20s seconds to import %s rows\n" `(time -p mysql -h $db_server -u $user -p$password -e "load data local infile \"$file_path\" $write_over_prior_results into table _transmission (scenario_id, carbon_cost, period, receive_id, send_id, @junk, @junk, study_date, study_hour, rps_fuel_category, power_sent, power_received, hours_in_sample);" $DB_name) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	  system_load) printf "%20s seconds to import %s rows\n" `(time -p mysql -h $db_server -u $user -p$password -e "load data local infile \"$file_path\" $write_over_prior_results into table _system_load (scenario_id, carbon_cost, period, area_id, @junk, study_date, study_hour, power, hours_in_sample);" $DB_name) 2>&1 | grep -e '^real' | sed -e 's/real //'` `wc -l "$file_path" | sed -e 's/^[^0-9]*\([0-9]*\) .*$/\1/g'`
		;;
	 esac
   done
  done
else
  echo 'Skipping Import.'
fi


###################################################
# Crunch through the data
echo 'Crunching the data...'
data_crunch_path=tmp_data_crunch$$.sql
echo "set @scenario_id := ${SCENARIO_ID};" >> $data_crunch_path
cat CrunchResults.sql >> $data_crunch_path
mysql -h $db_server -u $user -p$password $DB_name < $data_crunch_path
rm $data_crunch_path


###################################################
# Build pivot-table like views that are easier to read

# Make a temporary file of investment periods
echo 'Getting a list of Investment periods...'
invest_periods_path=tmp_invest_periods$$.txt
mysql -h $db_server -u $user -p$password --column-names=false -e "select distinct(period) from gen_summary where scenario_id=$SCENARIO_ID order by period;" $DB_name > $invest_periods_path

# Generation....
# Build a long query that will make one column for each investment period
select_gen_summary="SELECT distinct g.scenario_id, g.source, g.carbon_cost"
while read inv_period; do 
	select_gen_summary=$select_gen_summary", (select round(avg_power) from $DB_name.gen_summary where source = g.source and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id) as '$inv_period'"
done < $invest_periods_path
select_gen_summary=$select_gen_summary" FROM $DB_name.gen_summary g;"
mysql -h $db_server -u $user -p$password -e "CREATE OR REPLACE VIEW $DB_name.gen_summary_by_source AS $select_gen_summary"


# Generation capacity...
# Build a long query that will make one column for each investment period
select_gen_cap_summary="SELECT distinct g.scenario_id, g.source, g.carbon_cost"
while read inv_period; do 
	select_gen_cap_summary=$select_gen_cap_summary", (select round(capacity) from $DB_name.gen_cap_summary where source = g.source and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id) as '$inv_period'"
done < $invest_periods_path
select_gen_cap_summary=$select_gen_cap_summary" FROM $DB_name.gen_cap_summary g;"
mysql -h $db_server -u $user -p$password -e "CREATE OR REPLACE VIEW $DB_name.gen_cap_summary_by_source AS $select_gen_cap_summary"


# Make a temporary file of generation sources
echo 'Getting a list of generation technologies...'
sources_path=tmp_sources$$.txt
mysql -h $db_server -u $user -p$password --column-names=false -e "select distinct(source) from $DB_name.gen_hourly_summary WHERE scenario_id = $SCENARIO_ID;" > $sources_path

# Dispatch summary, 
# Build a long query that will make one column for each generation source
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, (select period FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'period', (select study_date FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'study_date', (select hours_in_sample FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'hours_in_sample', (select month FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'month', (select month_name FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'month_name', (select quarter_of_day FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'quarter_of_day', (select hour_of_day FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'hour_of_day'"
while read gen_source; do 
	select_dispatch_summary="$select_dispatch_summary"", (select round(power) FROM $DB_name.gen_hourly_summary where source='$gen_source' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour ) as '$gen_source'"
done < $sources_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name.gen_hourly_summary g order by scenario_id, carbon_cost, period, month, hour_of_day;"
mysql -h $db_server -u $user -p$password -e "CREATE OR REPLACE VIEW $DB_name._gen_hourly_summary_by_source AS $select_dispatch_summary"

# Dispatch by load area and gen source 
# Build a long query that will make one column for each generation source
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, g.load_area, (select period FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'period', (select study_date FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'study_date', (select hours_in_sample FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'hours_in_sample', (select month FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'month', (select month_name FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'month_name', (select quarter_of_day FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'quarter_of_day', (select hour_of_day FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'hour_of_day'"
while read gen_source; do 
	select_dispatch_summary="$select_dispatch_summary"", (select round(power) FROM $DB_name.gen_hourly_summary_la where source='$gen_source' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area) as '$gen_source'"
done < $sources_path
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name.gen_hourly_summary_la g order by scenario_id, carbon_cost, period, month, hour_of_day;"
mysql -h $db_server -u $user -p$password -e "CREATE OR REPLACE VIEW $DB_name._gen_hourly_summary_la_by_source AS $select_dispatch_summary"


# delete the temporary files
rm $invest_periods_path
rm $sources_path



###################################################
# Export summaries of the results
echo 'Exporting gen_summary.txt...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.gen_summary_by_source WHERE scenario_id = $SCENARIO_ID" > $results_dir/gen_summary.txt
echo 'Exporting gen_cap_summary.txt...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.gen_cap_summary_by_source WHERE scenario_id = $SCENARIO_ID" > $results_dir/gen_cap_summary.txt
echo 'Exporting dispatch_summary.csv...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.gen_hourly_summary WHERE scenario_id = $SCENARIO_ID;" > $results_dir/dispatch_summary.csv
echo 'Exporting dispatch_summary2.txt...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name._gen_hourly_summary_by_source WHERE scenario_id = $SCENARIO_ID" > $results_dir/dispatch_summary2.txt
echo 'Exporting co2_cc.csv...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.co2_cc WHERE scenario_id = $SCENARIO_ID;" > $results_dir/co2_cc.csv
echo 'Exporting power_cost_cc.csv...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.power_cost where period=(SELECT max(period) FROM $DB_name.power_cost where scenario_id=$SCENARIO_ID) AND scenario_id = $SCENARIO_ID;" > $results_dir/power_cost_cc.csv
echo 'Exporting trans_cap_new.csv...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.trans_cap where new and period=(SELECT max(period) FROM $DB_name.trans_cap where scenario_id=$SCENARIO_ID) AND scenario_id = $SCENARIO_ID;" > $results_dir/trans_cap_new.tcsv
echo 'Exporting trans_cap_exist.csv...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.trans_cap where not new and period=(SELECT max(period) FROM $DB_name.trans_cap where scenario_id=$SCENARIO_ID) AND scenario_id = $SCENARIO_ID;" > $results_dir/trans_cap_exist.csv
