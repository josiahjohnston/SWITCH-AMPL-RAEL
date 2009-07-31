# Export SWITCH input data from the Switch_inputs database into text files that will be read in by AMPL
# This script assumes that SetUpStudyHours.sql and 'build cap factors.sql' have both been called
# If you need to call those, copy the following commands into a terminal and wait 20 minutes or so. 
# mysql < 'build cap factors.sql'
# mysql < 'SetUpStudyHours.sql'

export write_to_path='.'

db_server="xserve-rael.erg.berkeley.edu"

echo "User name for MySQL on $db_server? "
read user
echo "Password for MySQL on $db_server? "
stty_orig=`stty -g`   # Save screen settings
stty -echo            # To keep the password vaguely secure, don't let it show to the screen
read password
stty $stty_orig       # Restore screen settings

###########################
# These next variables select which data is used

export REGIONAL_MULTIPLIER_SCENARIO_ID=1
export REGIONAL_FUEL_COST_SCENARIO_ID=1
export REGIONAL_GEN_RESTRICT_SCENARIO_ID=1

# Change these next two if you want to subsample sites or technologies. 
# Their values get shoved into a "where" clause. 
# Search for these variables in the code below to see specifics.
export SITESAMPLE=1
export TECHSAMPLE=1

# This is a multipler on the maximum capacity that can be installed at a solar or wind site: everything in the "cap_factor_all" table. 
export SCALEUP=1
# Periods (each represents 8 years)
export PERIODS="2014,2022"

# Set NO_PEAKS to 1                       if you want to INCLUDE the peak days
# Set NO_PEAKS to "hours_in_sample > 100" if you want to EXCLUDE the peak days
export NO_PEAKS="hours_in_sample > 100"

# Months
export NUM_MONTHS_BETWEEN_SAMPLES=12
# The value of START_MONTH should be between 0 and one less than the value of NUM_HOURS_BETWEEN_SAMPLES. 
# 0 means sampling starts in Jan, 1 means Feb, 2 -> March, 3 -> April
export START_MONTH=3 # April

# Hours
export NUM_HOURS_BETWEEN_SAMPLES=24
# The value of START_HOUR should be between 0 and one less than the value of NUM_HOURS_BETWEEN_SAMPLES. 
# 0 means sampling starts at 12am, 1 means 1am, ... 15 means 3pm, etc
export START_HOUR=15

# SUBSET_ID refers to the set of hours that were either selected randomly or chosen to be representative (based on median load)
# SUBSET_ID 1 draws representative loads from hours in 2004, based on the Western expansion dataset (CA, OR, WA)
export SUBSET_ID=1
# Change the scenario name
export SCENARIO="default_results_"$SUBSET_ID


###########################
# Export data to be read into ampl.
# The remaining commands are used in the terminal (at a bash shell prompt, not in mysql)

cd  $write_to_path

# Toy version of the model (Ultra-micro)
# 1 hour per day
# 1 day per month  
# 1 month per year
# 2 study periods (the ampl code expects at least two study periods to calculate the parameter years_per_period)

# Don't change the next two line unless you are very confident. Normally, you'd change the var
export DATESAMPLE="period in ($PERIODS) and mod(month_of_year, $NUM_MONTHS_BETWEEN_SAMPLES) = $START_MONTH and subset_id=$SUBSET_ID and $NO_PEAKS"
export TIMESAMPLE=$DATESAMPLE" and mod(hour_of_day, $NUM_HOURS_BETWEEN_SAMPLES) = $START_HOUR"
# The hours in the sample have extra weights because each hour represents 24 hours day (from NUM_HOURS_BETWEEN_SAMPLES), each month represents 12 months (from NUM_MONTHS_BETWEEN_SAMPLES), and each investment period is 8 years (from PERIODS)
# In a non-peak sample, you also need to subtract the hours used for peak load (don't double-count)
# PEAK: Each timepoint from a peak-load sample represents this many hours:
#	1 hour sampled represents: [ 24 hours / day ] * [ 1 day / month ] * [12 months / year] * [8 years / period] = 2034
# NON-PEAK: Each timepoint from a non-peak-load sample represents this many hours (assuming peak load is considered, each month has about 29 days):
#	1 hour sampled represents: [ 24 hours / day ] * [ 29 days / month ] * [12 months / year] * [8 years / period] = 58986
# NON-PEAK: If peak loads are not included, then each timepoint from a non-peak-load sample represents this many hours (assuming each month has about 30 days):
#	1 hour sampled represents: [ 24 hours / day ] * [ 30 days / month ] * [12 months / year] * [8 years / period] = 61020
export HOURS_IN_SAMPLE="if( hours_in_sample < 100, 2034, 58986 )"
# Period is 2x as long
# 1 month is sampled per year, so scale by 12x
# 1 hours is sampled per day, so scale by 24x
#export HOURS_IN_SAMPLE="hours_in_sample*2*12*24"


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

echo $SCENARIO > scenario_name.txt

echo '	cap_factor.tab...'
echo ampl.tab 5 1 > cap_factor.tab
mysql -h $db_server -u $user -p$password -e "select replace(load_area, ' ', '_') as load_zone, technology, site, orientation, study_hour as hour, cap_factor from wecc.cap_factor_all c join wecc.study_hours_all h on (h.hournum=c.hour) where $SITESAMPLE and $TECHSAMPLE and $TIMESAMPLE;" >> cap_factor.tab

echo '	max_capacity.tab...'
echo ampl.tab 4 1 > max_capacity.tab
mysql -h $db_server -u $user -p$password -e "select replace(load_area, ' ', '_') as load_zone, technology, site, orientation, max_capacity*$SCALEUP as max_capacity from wecc.max_capacity_all where $SITESAMPLE and $TECHSAMPLE;" >> max_capacity.tab

echo '	connect_cost.tab...'
echo ampl.tab 4 2 > connect_cost.tab
mysql -h $db_server -u $user -p$password -e "select replace(load_area, ' ', '_') as load_zone, technology, site, orientation, connect_length_km, connect_cost_per_MW from wecc.connect_cost_all where $SITESAMPLE and $TECHSAMPLE;" >> connect_cost.tab

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
mysql -h $db_server -u $user -p$password -e "select load_area as load_zone, technology, price_year, overnight_cost, connect_cost_per_MW_generic, fixed_o_m, variable_o_m, overnight_cost_change, fixed_o_m_change, variable_o_m_change from wecc.regional_generator_costs_human;" >> regional_generator_costs.tab

echo '	rps_fuel_category.tab...'
echo ampl.tab 1 1 > rps_fuel_category.tab
mysql -h $db_server -u $user -p$password -e "select fuel, rps_fuel_category from wecc.rps_fuel_category;" >> rps_fuel_category.tab

echo '	qualifies_for_rps.tab...'
echo ampl.tab 2 1 > qualifies_for_rps.tab
mysql -h $db_server -u $user -p$password -e "select load_area as load_zone, rps_fuel_category, qualifies from wecc.qualifies_for_rps;" >> qualifies_for_rps.tab

echo '	rps_requirement.tab...'
echo ampl.tab 1 3 > rps_requirement.tab
mysql -h $db_server -u $user -p$password -e "select load_area as load_zone, rps_goal, rps_compliance_year, load_zone_rps_policy from wecc.rps_requirement;" >> rps_requirement.tab 
