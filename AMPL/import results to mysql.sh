#!/bin/bash


##########################
# Constants
read SCENARIO_ID < scenario_id.txt
DB_name='switch_results_wecc_v2'
db_server='switch-db1.erg.berkeley.edu'
current_dir=`pwd`
results_dir="results"
write_over_prior_results="IGNORE"

##########################
# Get the user name and password 
# Note that passing the password to mysql via a command line parameter is considered insecure
#	http://dev.mysql.com/doc/refman/5.0/en/password-security.html
if [ $# -ge 2  ]
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

###################################################
# Clear out the prior instance of this run if requested
# You can do this manually with this SQL command: select clear_scenario_results(SCENARIO_ID);
if [ $# -ge 3 ]
then 
	if [ $3 = "--FlushPriorResults" ]
	then
		rewrite_results="REPLACE";
		echo "Flushing Prior results for scenario ${SCENARIO_ID}";
		mysql -h $db_server -u $user -p$password -e "use $DB_name; select clear_scenario_results(${SCENARIO_ID});"
	fi
fi
if [ $# -ge 1 ]
then
	if [ $1 = "--FlushPriorResults" ]
	then
		rewrite_results="REPLACE";
		echo "Flushing Prior results for scenario ${SCENARIO_ID}";
		mysql -h $db_server -u $user -p$password -e "use $DB_name; select clear_scenario_results(${SCENARIO_ID});"
	fi
fi

###################################################
# Import all the results file into the DB
echo 'Importing results files...'
for file_base_name in gen_cap trans_cap local_td_cap power transmission
do
 for file_name in `ls results/${file_base_name}_*csv | grep "[[:digit:]]"`
 do
  file_path="$current_dir/$file_name"
  # Import the file in question into the DB
  # Almost every output file goes into a table of the same name. The file "power" is the exception, it goes into "dispatch"
  if [ $file_base_name != power ]
  then
    echo "    $file_name  ->  $DB_name.$file_base_name"
    mysql -h $db_server -u $user -p$password -e "use $DB_name; load data local infile \"$file_path\" $write_over_prior_results into table $file_base_name fields terminated by \",\" optionally enclosed by '\"' ignore 1 lines;"
  else
    echo "    $file_name  ->  $DB_name.dispatch"
    mysql -h $db_server -u $user -p$password -e "use $DB_name; load data local infile \"$file_path\" $write_over_prior_results into table dispatch fields terminated by \",\" optionally enclosed by '\"' ignore 1 lines;"
  fi
 done
done

###################################################
# Crunch through the data
echo 'Crunching the data...'
echo "use ${DB_name};" > tmp_data_crunch.sql
echo "set @scenario_id := ${SCENARIO_ID};" >> tmp_data_crunch.sql
cat CrunchResults.sql >> tmp_data_crunch.sql
mysql -h $db_server -u $user -p$password < tmp_data_crunch.sql
rm tmp_data_crunch.sql


###################################################
# Build pivot-table like views that are easier to read

# Make a temporary file of investment periods
echo 'Getting a list of Investment periods...'
mysql -h $db_server -u $user -p$password --column-names=false -e "select distinct(period) from $DB_name.gen_summary order by period;" > tmp_invest_periods.txt

# Generation....
# Build a long query that will make one column for each investment period
select_gen_summary="SELECT distinct g.scenario_id, g.source, g.carbon_cost"
while read inv_period; do 
	select_gen_summary=$select_gen_summary", (select round(avg_power) from $DB_name.gen_summary where source = g.source and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id) as '$inv_period'"
done < tmp_invest_periods.txt
select_gen_summary=$select_gen_summary" FROM $DB_name.gen_summary g;"
mysql -h $db_server -u $user -p$password -e "CREATE OR REPLACE VIEW $DB_name.gen_summary_by_source AS $select_gen_summary"


# Generation capacity...
# Build a long query that will make one column for each investment period
select_gen_cap_summary="SELECT distinct g.scenario_id, g.source, g.carbon_cost"
while read inv_period; do 
	select_gen_cap_summary=$select_gen_cap_summary", (select round(capacity) from $DB_name.gen_cap_summary where source = g.source and period = '$inv_period' and carbon_cost = g.carbon_cost and scenario_id = g.scenario_id) as '$inv_period'"
done < tmp_invest_periods.txt
select_gen_cap_summary=$select_gen_cap_summary" FROM $DB_name.gen_cap_summary g;"
mysql -h $db_server -u $user -p$password -e "CREATE OR REPLACE VIEW $DB_name.gen_cap_summary_by_source AS $select_gen_cap_summary"


# Make a temporary file of generation sources
echo 'Getting a list of generation technologies...'
mysql -h $db_server -u $user -p$password --column-names=false -e "select distinct(source) from $DB_name.gen_hourly_summary WHERE scenario_id = $SCENARIO_ID;" > tmp_sources.txt

# Dispatch summary, 
# Build a long query that will make one column for each generation source
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, (select period FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'period', (select study_date FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'study_date', (select hours_in_sample FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'hours_in_sample', (select month FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'month', (select month_name FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'month_name', (select quarter_of_day FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'quarter_of_day', (select hour_of_day FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour limit 1) as 'hour_of_day'"
while read gen_source; do 
	select_dispatch_summary="$select_dispatch_summary"", (select round(power) FROM $DB_name.gen_hourly_summary where source='$gen_source' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour ) as '$gen_source'"
done < tmp_sources.txt
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name.gen_hourly_summary g order by scenario_id, carbon_cost, period, month, hour_of_day;"
mysql -h $db_server -u $user -p$password -e "CREATE OR REPLACE VIEW $DB_name._gen_hourly_summary_by_source AS $select_dispatch_summary"

# Dispatch by load area and gen source 
# Build a long query that will make one column for each generation source
select_dispatch_summary="SELECT distinct g.scenario_id, g.carbon_cost, g.study_hour, g.load_area, (select period FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'period', (select study_date FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'study_date', (select hours_in_sample FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'hours_in_sample', (select month FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'month', (select month_name FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'month_name', (select quarter_of_day FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'quarter_of_day', (select hour_of_day FROM $DB_name.gen_hourly_summary where scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area limit 1) as 'hour_of_day'"
while read gen_source; do 
	select_dispatch_summary="$select_dispatch_summary"", (select round(power) FROM $DB_name.gen_hourly_summary_la where source='$gen_source' and scenario_id = g.scenario_id and carbon_cost = g.carbon_cost and study_hour = g.study_hour and load_area = g.load_area) as '$gen_source'"
done < tmp_sources.txt
select_dispatch_summary="$select_dispatch_summary"" FROM $DB_name.gen_hourly_summary_la g order by scenario_id, carbon_cost, period, month, hour_of_day;"
mysql -h $db_server -u $user -p$password -e "CREATE OR REPLACE VIEW $DB_name._gen_hourly_summary_la_by_source AS $select_dispatch_summary"


# delete the temporary files
rm tmp_invest_periods.txt
rm tmp_sources.txt



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
echo 'Exporting gen_by_load_area.csv...'
mysql -h $db_server -u $user -p$password --column-names=false -e "select * from $DB_name.gen_by_load_area WHERE scenario_id = $SCENARIO_ID;" > $results_dir/gen_by_load_area.csv
echo 'Exporting trans_cap_new.csv...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.trans_cap where new and period=(SELECT max(period) FROM $DB_name.trans_cap where scenario_id=$SCENARIO_ID) AND scenario_id = $SCENARIO_ID;" > $results_dir/trans_cap_new.tcsv
echo 'Exporting trans_cap_exist.csv...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.trans_cap where not new and period=(SELECT max(period) FROM $DB_name.trans_cap where scenario_id=$SCENARIO_ID) AND scenario_id = $SCENARIO_ID;" > $results_dir/trans_cap_exist.csv
