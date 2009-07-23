#!/bin/bash


##########################
# Constants
DB_name="trans_test"
export db_server='xserve-rael.erg.berkeley.edu'
#db_server="localhost"
current_dir=`pwd`
results_dir="results"
GIS_results="results/GIS"

##########################
# Get the user name and password 
# Note that passing the password to mysql via a command line parameter is considered insecure
#	http://dev.mysql.com/doc/refman/5.0/en/password-security.html
echo "User name for MySQL on $db_server? "
read user
echo "Password for MySQL on $db_server? "
stty_orig=`stty -g`   # Save screen settings
stty -echo            # To keep the password vaguely secure, don't let it show to the screen
read password
stty $stty_orig       # Restore screen settings

###################################################
# Make sure the database and tables exist. Make them if need be
echo "create database IF NOT EXISTS ${DB_name};" > tmp_table_create.sql
echo "use ${DB_name};" >> tmp_table_create.sql
cat CreateSQLTablesForResults.sql >> tmp_table_create.sql
mysql -h $db_server -u $user -p$password < tmp_table_create.sql
rm tmp_table_create.sql

###################################################
# Import all the results file into the DB
echo 'Importing results files...'
for file_base_name in gen_cap trans_cap local_td_cap power transmission
do
 for file_name in `ls results/${file_base_name}_*csv`
 do
  file_path="$current_dir/$file_name"
  # Import the file in question into the DB
  # Almost every output file goes into a table of the same name. The file "power" is the exception, it goes into "dispatch"
  if [ $file_base_name != power ]
  then
    mysql -h $db_server -u $user -p$password -e "use $DB_name; load data local infile \"$file_path\" into table $file_base_name fields terminated by \",\" optionally enclosed by '\"' ignore 1 lines;"
  else
    mysql -h $db_server -u $user -p$password -e "use $DB_name; load data local infile \"$file_path\" into table dispatch fields terminated by \",\" optionally enclosed by '\"' ignore 1 lines;"
  fi
 done
done

###################################################
# Crunch through the data
echo 'Crunching the data...'
echo "use ${DB_name};" > tmp_data_crunch.sql
cat CrunchResults.sql >> tmp_data_crunch.sql
mysql -h $db_server -u $user -p$password < tmp_data_crunch.sql
rm tmp_data_crunch.sql


###################################################
# Export summary views of the data

# Make a temporary file of investment periods
echo 'Getting a list of Investment periods...'
mysql -h $db_server -u $user -p$password --column-names=false -e "select distinct(period) from $DB_name.gen_summary;" > tmp_invest_periods.txt

# Generation....
# Build a long query that will make one column for each investment period
echo 'Exporting gen_summary.txt...'
select_gen_summary="SELECT distinct(source) as gen_source, carbon_cost as carb_cost, "
while read inv_period; do 
	select_gen_summary=$select_gen_summary" (select avg_power from $DB_name.gen_summary where source = gen_source and period = '$inv_period' and carbon_cost = carb_cost) as '$inv_period', "
done < tmp_invest_periods.txt
select_gen_summary=$select_gen_summary" '' FROM $DB_name.gen_summary;"
mysql -h $db_server -u $user -p$password -e "$select_gen_summary" > $results_dir/gen_summary.txt
# Uncomment the next line to see the mysql query
#echo 'select_gen_summary: '$select_gen_summary
#echo ''
#echo ''

# Generation capacity...
# Build a long query that will make one column for each investment period
echo 'Exporting gen_cap_summary.txt...'
select_gen_cap_summary="SELECT distinct(source) as gen_source, carbon_cost as carb_cost, "
while read inv_period; do 
	select_gen_cap_summary=$select_gen_cap_summary" (select capacity from $DB_name.gen_cap_summary where source = gen_source and period = '$inv_period' and carbon_cost = carb_cost) as '$inv_period', "
done < tmp_invest_periods.txt
select_gen_cap_summary=$select_gen_cap_summary" '' FROM $DB_name.gen_cap_summary;"
mysql -h $db_server -u $user -p$password -e "$select_gen_cap_summary" > $results_dir/gen_cap_summary.txt
# Uncomment the next line to see the mysql query
#echo 'select_gen_cap_summary: '$select_gen_cap_summary
#echo ''
#echo ''

# Make a temporary file of generation sources
echo 'Getting a list of generation technologies...'
mysql -h $db_server -u $user -p$password --column-names=false -e "select distinct(source) from $DB_name.gen_hourly_summary;" > tmp_sources.txt

echo 'Exporting dispatch_summary2.txt...'
# Dispatch summary, each column 
# Build a long query that will make one column for each investment period
select_dispatch_summary="select * from (SELECT distinct carbon_cost, period, study_date,study_hour,hours_in_sample,month,month_name,quarter_of_day,hour_of_day FROM $DB_name.gen_hourly_summary) t"
while read gen_source; do 
	select_dispatch_summary="$select_dispatch_summary"" join (select carbon_cost, study_hour, power as '$gen_source' FROM $DB_name.gen_hourly_summary where source='$gen_source') \`$gen_source\` using (carbon_cost, study_hour)"
done < tmp_sources.txt
select_dispatch_summary="$select_dispatch_summary"" order by carbon_cost, period, month, hour_of_day;"
mysql -h $db_server -u $user -p$password -e "$select_dispatch_summary" > $results_dir/dispatch_summary2.txt
# Uncomment the next line to see the mysql query
#echo 'select_dispatch_summary: '"$select_dispatch_summary"
#echo ''
#echo ''




###################################################
# Export simple summary views of the data
echo 'Exporting dispatch_summary.txt...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.gen_hourly_summary;" > $results_dir/dispatch_summary.txt
echo 'Exporting gen_source_share_by_carbon_cost.csv...'
mysql -h $db_server -u $user -p$password --column-names=false -e "select * from $DB_name.gen_source_share_by_carbon_cost ;" > $results_dir/gen_source_share_by_carbon_cost.csv
echo 'Exporting gen_source_capacity_by_carbon_cost.csv...'
mysql -h $db_server -u $user -p$password --column-names=false -e "select * from $DB_name.gen_source_capacity_by_carbon_cost ;" > $results_dir/gen_source_capacity_by_carbon_cost.csv
echo 'Exporting co2_cc.txt...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.co2_cc;" > $results_dir/co2_cc.txt
echo 'Exporting power_cost_cc.txt...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.power_cost where period=2022;" > $results_dir/power_cost_cc.txt
if [ ! -d $GIS_results ]
then
  mkdir $GIS_results
fi
echo 'Exporting load_area_centers.txt...'
mysql -h $db_server -u $user -p$password -e "select * from wecc.load_area;" > $GIS_results/load_area_centers.txt
echo 'Exporting gen_by_load_area.csv...'
mysql -h $db_server -u $user -p$password --column-names=false -e "select * from $DB_name.gen_by_load_area;" > $GIS_results/gen_by_load_area.csv
echo 'Exporting trans_cap_new.txt...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.trans_cap where new and period=2022;" > $GIS_results/trans_cap_new.txt
echo 'Exporting trans_cap_exist.txt...'
mysql -h $db_server -u $user -p$password -e "select * from $DB_name.trans_cap where not new and period=2022;" > $GIS_results/trans_cap_exist.txt


# delete the temporary file
rm tmp_invest_periods.txt
rm tmp_sources.txt
