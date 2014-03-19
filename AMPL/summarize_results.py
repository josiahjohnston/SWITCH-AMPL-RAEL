#!/usr/bin/env python
# This script summarizes SWITCH investment & operation results, grouping similar technologies 
# according to sets defined in tech_grouping.txt. For example, this can lump the 10 different Bio*
# generation technologies into Biomass. 
import os
import glob
import re
import csv
import copy


# Data structures for storing and/or aggregating info from files. 
tech_to_group = {} # tech_to_group[tech] = 'group'
gen_dat = {} # Indexed by ( period, technology )
gen_dat_template = { 
  'capacity': 0, 'energy_gen': 0, 'capacity_factor': None, 'emissions': 0, # Units: MW, MWhr/yr, %, t-CO2eq/yr
  'cost_capital': 0, 'cost_fixed': 0, 'cost_var': 0, # Units: 2007$/yr all
  'levelized_cost': None, # Levelized cost in 2007$/yr is calculated by total energy generated and/or released
  'total_hourly_up_ramp': 0, 'total_hourly_down_ramp': 0, # Units: MW/yr all
  'storage_energy_capacity': 0, 'energy_stored': 0, 'energy_released': 0, # Units: MWhr, MWhr/yr, MWhr/yr
  'power_percentiles': {} # index N gives values for N-th percentile. 0 and 100 are used to denote min and max
#  ,'vintages': {} # gen_dat[(period,tech)]['vintages']['existing'|installed_year] = remaining_capacity_MW
}
calculate_percentiles = (0, 2, 25, 50, 75, 98, 100)
hourly_output = {} # Indexed by [(period, technology)][timepoint]
hourly_output_template = { 
  'power': 0, 'hours_per_year': None, # Units: MW, count
  'weight': None, 'percentile_rank': None # Units: statistical weight (which sums to 1 across period & tech), the percentile ranking of this hour within period & tech grouping in regards to power output
}
hourly_net_load = {} # Indexed by [period][timepoint]
hourly_net_load_template = { 
  'load': 0, 'net_load': 0, # Units: MW, MW
  'percentile_rank': None # Units: percentile ranking of this hour within period & in regards to net load
}

system_dat = {} # Indexed by period
system_dat_template = {
  'load_served': 0, 'energy_produced': 0, 'peak_demand': 0, 'hours_in_period': 0, # Units: MWhr/yr, MWhr/yr, MW, hours
  'power_cost': None, 'system_cost': None, # Units: 2007$/MWh, 2007$
  'total_hourly_up_ramp': 0, 'total_hourly_down_ramp': 0, 'total_emissions': 0 # Units: MW/yr, MW/yr, t-CO2eq/yr
}
trans_dat={} # Indexed by (period)
trans_dat_template = {
  'rated_cap_MW': 0, 'rated_cap_MWkm': 0, 'derated_cap_MW': 0, 'derated_cap_MWkm': 0, # Units: MW, MW-km, 
  'cost_annual': 0, # Units: 2007$/yr
  'energy_sent': 0, 'energy_received': 0, 'capacity_factor': None, # Units: MWhr/yr, MWhr/yr
  'total_hourly_up_ramp': 0, 'total_hourly_down_ramp': 0, # Units: MW/yr, MW/yr all
  'energy_received_percentiles': {} # index N gives values for N-th percentile. 0 and 100 are used to denote min and max
}
hourly_trans={} # Indexed by [period][timepoint]. Value is power received
flexible_net_power={} # flexible_output[(timepoint, [technology|'Net_Tx'], [project_id|load_area])] = power_MW
flexible_tech = set()
intermittent_tech = set()
timepoints = {} # indexed by timepoint_id
timepoints_template = { 
  'period': None, 'date': None, # Units: year, datestamp
  'hours_per_period': None, 'hours_per_year': None, # Units: weight of timepoint in hours/period and hours/year
  'prior_timepoint': None, # Units: timepoint_id 
  'month_of_year': None, 'hour_of_day': None
}
set_of_timepoints_by_period = {}
dates = {}
generator_info = {} # records from generator_info.tab, indexed by the technology column
trans_path_dat = {} # records from transmisison_lines.tab indexed by (from_area, to_area). 

scenario_id = str(int(open("scenario_id.txt").read()))

# Set the umask to give group read & write permissions to all files & directories made by this script.
os.umask(0002)
# Use tab as a delimieter on output files
delimiter="\t"

# Read in group info
path='inputs/tech_grouping.txt'
if os.path.isfile(path):
  f = open(path, 'rb')
  file_dat = csv.DictReader(f, delimiter='\t')
  for row in file_dat:
    tech_to_group[row['technology']] = row['tech_group']
  f.close()
else:
  print "Error! " + path + " not found."


# Read in study timepoint info
path='inputs/study_hours.tab'
if os.path.isfile(path):
  f = open(path, 'rb')
  f.next() # Skip a row
  file_dat = csv.DictReader(f, delimiter='\t')
  for row in file_dat:
    period = int(row['period'])
    date = int(row['date'])
    timepoint = int(row['hour'])
    hours_in_sample = float(row['hours_in_sample'])
    timepoints[timepoint] = { 'period': period, 'date': date, 'hours_per_period': hours_in_sample }
    if date not in dates: dates[date] = []
    dates[date].append( timepoint )
    if period not in system_dat:
      system_dat[period] = 0
      # Initialize variables that will be used for sums
      system_dat[period] = system_dat_template.copy()
    system_dat[period]['hours_in_period'] += hours_in_sample
  f.close()
else:
  print "Error! " + path + " not found."

for period in system_dat:
  system_dat[period]['num_years_per_period'] = round(system_dat[period]['hours_in_period']/8766)
  set_of_timepoints_by_period[period] = set( [tp for tp in timepoints if timepoints[tp]['period'] == period ] )

for timepoint in timepoints: 
  timepoints[timepoint]['hours_per_year'] = timepoints[timepoint]['hours_per_period'] / system_dat[timepoints[timepoint]['period']]['num_years_per_period']
  timepoints[timepoint]['weight'] = timepoints[timepoint]['hours_per_period'] / system_dat[period]['hours_in_period']
  timepoints[timepoint]['month_of_year'] = int(str(timepoint)[5:6])
  timepoints[timepoint]['hour_of_day'] = int(str(timepoint)[8:10])

for date in dates: dates[date].sort()

last_timepoint = max(timepoints.keys())

for timepoint in sorted(timepoints.keys()):
  # timepoints are now sorted by date & hour of day. 
  # If the last timepoint came from the same date, use it for the prior timepoint
  if timepoints[last_timepoint]['date'] == timepoints[timepoint]['date']:
    prior_timepoint = last_timepoint
  # Otherwise, use the last timepoint of the matching date [-1] per our treatement in AMPL
  else:
    prior_timepoint = dates[timepoints[timepoint]['date']][-1]
  timepoints[timepoint]['prior_timepoint'] = prior_timepoint
  timepoints[prior_timepoint]['next_timepoint'] = timepoint
  last_timepoint = timepoint

# Read in load data
path='inputs/max_system_loads.tab'
if os.path.isfile(path):
  f = open(path, 'rb')
  f.next() # Skip a row
  file_dat = csv.DictReader(f, delimiter='\t')
  for row in file_dat:
    period = int(row['period'])
    if period in system_dat: system_dat[period]['peak_demand'] += float(row['max_system_load'])
  f.close()
else:
  print "Error! " + path + " not found."

# Read generator info. Make a list of flexible technologies and intermittent technologies
path='inputs/generator_info.tab'
if os.path.isfile(path):
  f = open(path, 'rb')
  f.next() # Skip a row
  file_dat = csv.DictReader(f, delimiter='\t')
  for row in file_dat:
    tech = row['technology']
    tech_group = tech_to_group[tech]
    if int(row['dispatchable']) == 1 or int(row['storage']) == 1: 
      flexible_tech.add(tech_group)
    if int(row['intermittent']) == 1: 
      intermittent_tech.add(tech_group)
    generator_info[tech] = row.copy()
  f.close()
else:
  print "Error! " + path + " not found."

# Read system load
path='inputs/system_load.tab'
if os.path.isfile(path):
  f = open(path, 'rb')
  f.next() # Skip a row
  file_dat = csv.DictReader(f, delimiter='\t')
  for row in file_dat:
    timepoint = int(row['hour'])
    period = timepoints[timepoint]['period']
    if period not in hourly_net_load: 
      hourly_net_load[period] = {}
    if timepoint not in hourly_net_load[period]: 
      hourly_net_load[period][timepoint] = copy.deepcopy(hourly_net_load_template)
    hourly_net_load[period][timepoint]['load'] += float(row['system_load'])    
    system_dat[period]['load_served'] += float(row['system_load']) * timepoints[timepoint]['hours_per_year']
  f.close()
else:
  print "Error! " + path + " not found."

# Read transmission line lengths
path='inputs/transmission_lines.tab'
if os.path.isfile(path):
  f = open(path, 'rb')
  f.next() # Skip a row
  file_dat = csv.DictReader(f, delimiter='\t')
  for row in file_dat:
    trans_path_dat[(row['load_area_start'], row['load_area_end'])] = dict(
      (key, float(row[key])) for key in row.keys() if key not in ('load_area_start', 'load_area_end') 
    )
  f.close()
else:
  print "Error! " + path + " not found."

# Read & summarize generation capacity
path='results/gen_cap_0.txt'
if os.path.isfile(path):
  f = open(path, 'rb')
  file_dat = csv.DictReader(f, delimiter='\t')
  for row in file_dat:
    period = int(row['period'])
    tech = row['technology']
    tech_group = tech_to_group[tech]
    if (period, tech_group) not in gen_dat: 
      gen_dat[(period, tech_group)] = copy.deepcopy(gen_dat_template)
    gen_dat[(period, tech_group)]['capacity'] += float(row['capacity'])
    gen_dat[(period, tech_group)]['storage_energy_capacity'] += float(row['storage_energy_capacity'])
    # Need to divide these period-wide costs by num_years_per_period to get annual costs. This reverses the simplified financial conversion in basic_stats from annual to period-wide costs.
    gen_dat[(period, tech_group)]['cost_capital'] += float(row['capital_cost']) / system_dat[period]['num_years_per_period']
    gen_dat[(period, tech_group)]['cost_fixed'] += float(row['fixed_o_m_cost']) / system_dat[period]['num_years_per_period']
  f.close()
else:
  print "Error! " + path + " not found."

for (period, tech_group) in gen_dat:
  hourly_output[(period, tech_group)] = {}


# Read & summarize transmission capacity
path='results/trans_cap_0.txt'
if os.path.isfile(path):
  f = open(path, 'rb')
  file_dat = csv.DictReader(f, delimiter='\t')
  for row in file_dat:
    period = int(row['period'])
    if period not in trans_dat: 
      trans_dat[period] = copy.deepcopy(trans_dat_template)
      hourly_trans[period] ={}
    # Divide by 2 to correct the modeling issue of representing a bi-directional transmission line
    #  as two uni-directional paths with symetric build-outs that each are assigned the full 
    # ratings and 1/2 of the costs. This is also reasonable summary of existing lines that sometimes have assymetrical ratings. 
    trans_mw = float(row['trans_mw']) / 2
    trans_mwkm = trans_mw * trans_path_dat[(row['start'],row['end'])]['transmission_length_km']
    trans_dat[period]['rated_cap_MW'] += trans_mw
    trans_dat[period]['rated_cap_MWkm'] += trans_mwkm
    trans_dat[period]['derated_cap_MW'] += trans_mw * trans_path_dat[(row['start'],row['end'])]['transmission_derating_factor']
    trans_dat[period]['derated_cap_MWkm'] += trans_mwkm * trans_path_dat[(row['start'],row['end'])]['transmission_derating_factor']
    # Need to divide these period-wide costs by num_years_per_period to get annual costs. This reverses the simplified financial conversion in basic_stats from annual to period-wide costs.
    trans_dat[period]['cost_annual'] += float(row['fixed_cost']) / system_dat[period]['num_years_per_period']
  f.close()
else:
  print "Error! " + path + " not found."

# Read power cost summary
path='results/cost_summary.txt'
if os.path.isfile(path):
  f = open(path, 'rb')
  file_dat = csv.DictReader(f, delimiter='\t')
  for row in file_dat:
    system_dat[int(row['period'])]['power_cost'] = float(row['Power_Cost_Per_Period'])
    system_dat[int(row['period'])]['system_cost'] = system_dat[int(row['period'])]['power_cost'] * system_dat[int(row['period'])]['load_served']
#    system_dat[int(row['period'])]['system_cost'] = float(row['Total_Cost_Per_Period'])
  f.close()
else:
  print "Error! " + path + " not found."


# Read & summarize power production
path='results/generator_and_storage_dispatch_0.txt'
if os.path.isfile(path):
  f = open(path, 'rb')
  file_dat = csv.DictReader(f, delimiter='\t')
  for row in file_dat:
    period = int(row['period'])
    tech = row['technology']
    tech_group = tech_to_group[tech]
    fuel = row['fuel']
    power = float(row['power'])
    tp = int(row['hour'])
    cost_var = float(row['fuel_cost']) + float(row['carbon_cost_hourly']) + float(row['variable_o_m']) \
      + float(row['spinning_fuel_cost']) + float(row['spinning_carbon_cost_incurred']) \
      + float(row['deep_cycling_fuel_cost']) + float(row['deep_cycling_carbon_cost']) \
      + float(row['startup_fuel_cost']) + float(row['startup_nonfuel_cost']) + float(row['startup_carbon_cost'])
    if (period, tech_group) not in gen_dat: continue
    hours_per_year = timepoints[tp]['hours_per_year']
    if tp not in hourly_output[(period, tech_group)]: 
      hourly_output[(period, tech_group)][tp] = copy.deepcopy(hourly_output_template)
      hourly_output[(period, tech_group)][tp]['hours_per_year'] = hours_per_year
      hourly_output[(period, tech_group)][tp]['weight'] = timepoints[tp]['weight']
    hourly_output[(period, tech_group)][tp]['power'] += power
    if fuel == 'Storage': 
      if power > 0:
        gen_dat[(period, tech_group)]['energy_released'] += power * hours_per_year
      elif power < 0:
        gen_dat[(period, tech_group)]['energy_stored'] += -1 * power * hours_per_year
    else:
      gen_dat[(period, tech_group)]['energy_gen'] += power * hours_per_year
    gen_dat[(period, tech_group)]['emissions'] += hours_per_year * \
      (float(row['co2_tons']) + float(row['spinning_co2_tons']) + float(row['deep_cycling_co2_tons']) + float(row['startup_co2_tons']))
    gen_dat[(period, tech_group)]['cost_var'] += hours_per_year * cost_var
    system_dat[period]['energy_produced'] += power * hours_per_year
    system_dat[period]['total_emissions'] += gen_dat[(period, tech_group)]['emissions']
    if tech_group in flexible_tech:
      # There may be multiple records for this project & timepoint because the storage 
      # portion of dispatch is stored in separate records from the non-storage portion
      # of dispatch for pumped hydro and CAES. In those edge cases, the net generation 
      # of the plant is their sum, grouped by project_id, technology and timepoint.
      project_id = row['project_id']
      timepoint = int(row['hour'])
      if (timepoint, tech_group, project_id) not in flexible_net_power:
        flexible_net_power[(timepoint, tech_group, project_id)] = 0
      flexible_net_power[(timepoint, tech_group, project_id)] += power * hours_per_year
  f.close()
else:
  print "Error! " + path + " not found."

# Summarize distribution of hourly_output by identifying select percentiles
# This is complicated because different timepoints have different weights. 
for (period, tech_group) in hourly_output.keys(): 
  # Timepoints with power output of 0 are skipped in the dispatch file to save disk space/memory
  # requirements, so populate missing entries with 0's
  for tp in set_of_timepoints_by_period[period]:
    if tp not in hourly_output[(period, tech_group)]: 
      hourly_output[(period, tech_group)][tp] = copy.deepcopy(hourly_output_template)
      hourly_output[(period, tech_group)][tp]['hours_per_year'] = timepoints[tp]['hours_per_year']
      hourly_output[(period, tech_group)][tp]['weight'] = timepoints[tp]['weight']
      hourly_output[(period, tech_group)][tp]['power'] = 0
  # Initialize percentile calculation variables
  cumulative_percentile=0
  percentile_iter = iter(calculate_percentiles)
  looking_for_percentile = percentile_iter.next()
  # Run through a sorted list, and assign percentiles to each element. Each record has an associated
  # weight, which add to 1 within a group. Starting from the small, add the weights and assign the
  # cumulative weight as the percentile. When the updated cumulative percentile passes the target 
  # we're looking for, copy the last record's value as the given percentile for summary stats. 
  for tp in sorted(hourly_output[(period, tech_group)].keys(), key=lambda tp: hourly_output[(period, tech_group)][tp]['power']): 
    hourly_output[(period, tech_group)][tp]['percentile_rank'] = cumulative_percentile
    cumulative_percentile += hourly_output[(period, tech_group)][tp]['weight']
    if ( cumulative_percentile >= looking_for_percentile/100.0 ):
      gen_dat[(period, tech_group)]['power_percentiles'][looking_for_percentile] = hourly_output[(period, tech_group)][tp]['power']
      try:
        looking_for_percentile = percentile_iter.next()
      except StopIteration:
        break
  # The 100th percentile (aka the max value) may not be reached due to rounding error. Copy the largest value in that event. 
  if looking_for_percentile not in gen_dat[(period, tech_group)]['power_percentiles']:
    gen_dat[(period, tech_group)]['power_percentiles'][looking_for_percentile] = hourly_output[(period, tech_group)][tp]['power']    

# Transmission dispatch: read & summarize
path='results/transmission_dispatch_0.txt'
if os.path.isfile(path):
  f = open(path, 'rb')
  file_dat = csv.DictReader(f, delimiter='\t')
  for row in file_dat:
    period = int(row['period'])
    timepoint = int(row['hour'])
    load_area_send = row['load_area_from']
    load_area_receive = row['load_area_receive']
    hours_per_year = timepoints[timepoint]['hours_per_year']
    for load_area in [load_area_send, load_area_receive]:
      if (timepoint,'Net_Tx',load_area) not in flexible_net_power: 
        flexible_net_power[(timepoint,'Net_Tx',load_area)] = 0
    flexible_net_power[(timepoint,'Net_Tx',load_area_send)] -= float(row['power_sent'])
    flexible_net_power[(timepoint,'Net_Tx',load_area_receive)] += float(row['power_received'])
    trans_dat[period]['energy_sent'] += float(row['power_sent']) * hours_per_year
    trans_dat[period]['energy_received'] += float(row['power_received']) * hours_per_year
    if timepoint not in hourly_trans[period]: hourly_trans[period][timepoint] = 0
    hourly_trans[period][timepoint] += float(row['power_received'])
  f.close()
else:
  print "Error! " + path + " not found."

# Summarize distribution of trans_dat energy_received by identifying select percentiles
# This is complicated because different timepoints have different weights. 
for (period) in trans_dat.keys(): 
  # Records for timepoints with no transmitted power are skipped in the dispatch file to save 
  # disk space/memory, so I need to populate missing entries with 0's
  for tp in set_of_timepoints_by_period[period]:
    if tp not in hourly_trans[period]: 
      hourly_trans[period][tp] = 0
  # Initialize percentile calculation variables
  cumulative_percentile=0
  percentile_iter = iter(calculate_percentiles)
  looking_for_percentile = percentile_iter.next()
  # Run through a sorted list, and assign percentiles to each element. Each record has an associated
  # weight, which add to 1 within a group. Starting from the small, add the weights and assign the
  # cumulative weight as the percentile. When the updated cumulative percentile passes the target 
  # we're looking for, copy the last record's value as the given percentile for summary stats. 
  for tp in sorted(hourly_trans[period].keys(), key=lambda tp: hourly_trans[period][tp]): 
    cumulative_percentile += timepoints[tp]['weight']
    if ( cumulative_percentile >= looking_for_percentile/100.0 ):
      trans_dat[period]['energy_received_percentiles'][looking_for_percentile] = hourly_trans[period][tp]
      try:
        looking_for_percentile = percentile_iter.next()
      except StopIteration:
        break
  # The 100th percentile (aka the max value) may not be reached due to rounding error. Copy the largest value in that event. 
  if looking_for_percentile not in trans_dat[period]['energy_received_percentiles']:
    trans_dat[period]['energy_received_percentiles'][looking_for_percentile] = hourly_trans[period][tp]

# Calculate overall ramping performed by each source
for (timepoint, tech_group, project_id) in flexible_net_power.keys():
  prior_timepoint = timepoints[timepoint]['prior_timepoint']
  next_timepoint = timepoints[timepoint]['next_timepoint']
  period = timepoints[timepoint]['period']
  if (prior_timepoint, tech_group, project_id) in flexible_net_power:
    ramp = flexible_net_power[(timepoint, tech_group, project_id)] - flexible_net_power[(prior_timepoint, tech_group, project_id)]
  else:
    # Missing records are assumed to have 0 values (This reduces file size significantly)
    ramp = flexible_net_power[(timepoint, tech_group, project_id)] - 0
  if ramp > 0:
    system_dat[period]['total_hourly_up_ramp'] += ramp
    if tech_group == 'Net_Tx': trans_dat[period]['total_hourly_up_ramp'] += ramp
    else: 
      gen_dat[(period, tech_group)]['total_hourly_up_ramp'] += ramp
  else:
    system_dat[period]['total_hourly_down_ramp'] += -1*ramp
    if tech_group == 'Net_Tx': trans_dat[period]['total_hourly_down_ramp'] += -1*ramp
    else: gen_dat[(period, tech_group)]['total_hourly_down_ramp'] += -1*ramp
  # If the record for the next timepoint is missing, then the unit down-ramped from the current value to 0. Update sums to reflect this
  if (next_timepoint, tech_group, project_id) not in flexible_net_power:
    ramp = 0 - flexible_net_power[(timepoint, tech_group, project_id)]
    system_dat[period]['total_hourly_down_ramp'] += -1*ramp
    if tech_group == 'Net_Tx': trans_dat[period]['total_hourly_down_ramp'] += -1*ramp
    else: gen_dat[(period, tech_group)]['total_hourly_down_ramp'] += -1*ramp

# Summarize transmission
for period in trans_dat:
  trans_dat[period]['capacity_factor'] = trans_dat[period]['energy_sent'] / (trans_dat[period]['rated_cap_MW'] * 8766)

# Summarize generation
for (period, tech_group) in gen_dat:
  # Add energy released so storage projects will have a more reasonable cap factor; the caveat is 
  # that we aren't including charging in this calculation. This calculation works for non-storage
  # gen because they have 0 for energy_released. Sometimes legacy generators have 0 capacity if 
  # they were retired early for emissions purposes & fixed cost savings. 
  if gen_dat[(period, tech_group)]['capacity'] == 0:
    gen_dat[(period, tech_group)]['capacity_factor'] = 0
  else:
    gen_dat[(period, tech_group)]['capacity_factor'] = \
      ( gen_dat[(period, tech_group)]['energy_gen'] + gen_dat[(period, tech_group)]['energy_released'] ) \
      / ( gen_dat[(period, tech_group)]['capacity'] * 8760 )
  # Same reasoning & caveats for levelized_costs
  if ( gen_dat[(period, tech_group)]['energy_gen'] + gen_dat[(period, tech_group)]['energy_released'] ) == 0:
    gen_dat[(period, tech_group)]['levelized_cost'] = 0
  else:
    gen_dat[(period, tech_group)]['levelized_cost'] = \
      ( gen_dat[(period, tech_group)]['cost_capital'] + gen_dat[(period, tech_group)]['cost_fixed'] + gen_dat[(period, tech_group)]['cost_var'] ) \
      / ( gen_dat[(period, tech_group)]['energy_gen'] + gen_dat[(period, tech_group)]['energy_released'] )


# Print summaries about generators
summary_output = open("results/gen_summary.txt","w")
non_percentile_columns = [i for i in sorted(gen_dat_template.keys()) if i != 'power_percentiles' ] #&& i != 'vintages']
percentile_columns = ['percentile_' + str(p) for p in calculate_percentiles]
summary_output.write(delimiter.join(['scenario_id', 'period', 'technology'] + non_percentile_columns + percentile_columns) + "\n")
for (period, tech_group) in sorted(gen_dat.keys()): 
  summary_output.write(delimiter.join( 
    [scenario_id, str(period), '"'+tech_group+'"'] + \
    [str(gen_dat[(period, tech_group)][key]) for key in non_percentile_columns] + \
    [str(gen_dat[(period, tech_group)]['power_percentiles'][p]) for p in calculate_percentiles]) + "\n")
summary_output.close()

# Print generation percentile summaries in normalized form
summary_output = open("results/gen_percentiles.txt","w")
summary_output.write(delimiter.join(['scenario_id', 'period', 'technology', 'percentile_num', 'percentile_value']) + "\n")
for (period, tech_group) in sorted(gen_dat.keys()): 
  for p in calculate_percentiles: 
    summary_output.write(delimiter.join( 
      [scenario_id, str(period), '"'+tech_group+'"', str(p), str(gen_dat[(period, tech_group)]['power_percentiles'][p])]) + "\n")
summary_output.close()


# Print hourly summaries about power production
summary_output = open("results/gen_hourly_summary.txt","w")
summary_output.write(delimiter.join(['scenario_id', 'period', 'technology', 'timepoint'] + hourly_output_template.keys()) + "\n")
for (period, tech_group) in sorted(hourly_output.keys()): 
  for timepoint in sorted(hourly_output[(period, tech_group)].keys()): 
    summary_output.write(delimiter.join( 
      [scenario_id, str(period), '"'+tech_group+'"', str(timepoint)] + [str(hourly_output[(period, tech_group)][timepoint][key]) for key in hourly_output_template.keys()]) + "\n")
summary_output.close()


# Print system summary
summary_output = open("results/sys_summary.txt","w")
summary_output.write(delimiter.join(['scenario_id', 'period'] + system_dat_template.keys()) + "\n")
for period in sorted(system_dat.keys()): 
  summary_output.write(delimiter.join( 
    [scenario_id, str(period)] + [str(system_dat[period][key]) for key in system_dat_template.keys()]) + "\n")
summary_output.close()

# Print transmission summary
summary_output = open("results/trans_summary.txt","w")
non_percentile_columns = [i for i in sorted(trans_dat_template.keys()) if i != 'energy_received_percentiles']
percentile_columns = ['percentile_' + str(p) for p in calculate_percentiles]
summary_output.write(delimiter.join(['scenario_id', 'period'] + non_percentile_columns + percentile_columns) + "\n")
for period in sorted(trans_dat.keys()): 
  summary_output.write(delimiter.join( 
    [scenario_id, str(period)] + [str(trans_dat[(period)][key]) for key in non_percentile_columns] + [str(trans_dat[period]['energy_received_percentiles'][p]) for p in calculate_percentiles]) + "\n")
summary_output.close()

# Print ramping summary
summary_output = open("results/ramp_summary.txt","w")
summary_output.write(delimiter.join(['scenario_id', 'period', 'source', "total_hourly_up_ramp", "total_hourly_down_ramp", "up_ramp_%", "down_ramp_%"] ) + "\n")
for (period, tech_group) in sorted([ (period,tech_group) for (period,tech_group) in gen_dat.keys() if tech_group in flexible_tech ]): 
  summary_output.write(delimiter.join( [
    scenario_id, str(period), '"'+tech_group+'"', 
    str(gen_dat[(period, tech_group)]['total_hourly_up_ramp']),
    str(gen_dat[(period, tech_group)]['total_hourly_down_ramp']),
    str(gen_dat[(period, tech_group)]['total_hourly_up_ramp'] / system_dat[period]['total_hourly_up_ramp']),
    str(gen_dat[(period, tech_group)]['total_hourly_down_ramp'] / system_dat[period]['total_hourly_down_ramp'])
  ]) + "\n")
for period in sorted(trans_dat.keys()): 
  summary_output.write(delimiter.join( [
    scenario_id, str(period), '"Net_Tx"', 
    str(trans_dat[(period)]['total_hourly_up_ramp']),
    str(trans_dat[(period)]['total_hourly_down_ramp']),
    str(trans_dat[(period)]['total_hourly_up_ramp'] / system_dat[period]['total_hourly_up_ramp']),
    str(trans_dat[(period)]['total_hourly_down_ramp'] / system_dat[period]['total_hourly_down_ramp'])
  ]) + "\n")
summary_output.close()



# Apply intermittent power output to net load
for period in hourly_net_load:
  for timepoint in hourly_net_load[period]: 
    hourly_net_load[period][timepoint]['net_load'] = hourly_net_load[period][timepoint]['load']
    for tech_group in intermittent_tech: 
      hourly_net_load[period][timepoint][tech_group] = 0
      if (period, tech_group) in hourly_output:
        if timepoint in hourly_output[(period, tech_group)]:
          hourly_net_load[period][timepoint][tech_group] = hourly_output[(period, tech_group)][timepoint]['power']
      hourly_net_load[period][timepoint]['net_load'] -= hourly_net_load[period][timepoint][tech_group]

# Calculate percentile rankings for net load values. See hourly_output calculations above for weight-based implementation notes 
for period in hourly_net_load.keys(): 
  cumulative_percentile=0
  for timepoint in sorted(hourly_net_load[period].keys(), key=lambda tp: hourly_net_load[period][tp]['net_load']): 
    hourly_net_load[period][timepoint]['percentile_rank'] = cumulative_percentile
    cumulative_percentile += timepoints[tp]['weight']

# Print hourly summaries about net load
summary_output = open("results/net_load_hourly_summary.txt","w")
summary_output.write(delimiter.join(['scenario_id', 'period', 'timepoint'] + \
  hourly_net_load_template.keys() + \
  ['"' + tech_group + '"' for tech_group in intermittent_tech] + \
  ['weight', 'month_of_year', 'hour_of_day'] ) + "\n")
for period in sorted(hourly_net_load.keys()): 
  for timepoint in sorted(hourly_net_load[period].keys()): 
    summary_output.write(delimiter.join( 
      [scenario_id, str(period), str(timepoint)] + \
      [str(hourly_net_load[period][timepoint][key]) for key in hourly_net_load_template.keys()] + \
      [str(hourly_net_load[period][timepoint][tech_group]) for tech_group in intermittent_tech] + \
      [str(timepoints[timepoint]['weight']), str(timepoints[timepoint]['month_of_year']), str(timepoints[timepoint]['hour_of_day']) ] \
    ) + "\n")
summary_output.close()
