#!/usr/bin/env python
import os
import glob
import re
import csv

capacity_shortfalls = []
periods = set()
emissions = {}                         # indexed by carbon cost, period, and emission type (direct or from sources of heat rate penalty)
emission_targets = {}                  # indexed by period
ng_consumption = {}                    # indexed by carbon cost & period
ng_consumption_projections = {}
biomass_consumption = {}               # indexed by carbon cost, period & load area
biomass_consumption_projections = {}
biomass_consumption_indexes = []
ng_consumption_indexes = []

scenario_id = str(int(open("scenario_id.txt").read()))

# Set the umask to give group read & write permissions to all files & directories made by this script.
os.umask(0002)

# Determine the number of years per period
f = open("common_inputs/misc_params.dat", 'rb')
dat = csv.reader(f, delimiter=' ', skipinitialspace=True)
for row in dat:
  if row[1] == "num_years_per_period":
    num_years_per_period = int(re.sub(r';', r'', row[3]))
    break
f.close()

# Make a list of periods from one of the primary optimization's input files
f = open("../inputs/study_hours.tab", 'rb')
f.next()
dat = csv.DictReader(f, delimiter='\t')
for row in dat:
  periods.add(int(row['period']))
f.close()

# Determine the emission goals from the carbon cap annual targets
emissions_1990 = 284800000 # I'm too lazy to write code to pull this value from the depths of switch.mod
for p in periods:
  emission_targets[p] = 0
f = open("common_inputs/carbon_cap_targets.tab", 'rb')
f.next()
dat = csv.DictReader(f, delimiter='\t')
for row in dat:
  year = int(row['year'])
  relative_goal = float(row['carbon_emissions_relative_to_base'])
  for period in periods:
    if year >= period and year < period + num_years_per_period: 
      emission_targets[period] += relative_goal*emissions_1990
f.close()


# Retrieve data from test_set_XXX/results/ directories
for test_dir in glob.glob('test_set_*'):
  test_set_id = test_dir.replace('test_set_','')

  # Find infeasibilities & capacity shortfalls
  for extra_peaker_path in glob.glob(test_dir + '/results/dispatch_extra_peakers_*'):
    carbon_cost = re.sub(r'^.*/dispatch_extra_peakers_(\d+).txt', r'\1', extra_peaker_path)
    load_infeasible_path = extra_peaker_path.replace('dispatch_extra_peakers','load_infeasibilities')
    balancing_infeasible_path = extra_peaker_path.replace('dispatch_extra_peakers','balancing_infeasibilities')

    # Make a unique list of infeasible timepoints referenced in the two infeasibility files 
    infeasible_timepoints = {}
    for path in [load_infeasible_path, balancing_infeasible_path]: 
      if os.path.isfile(path):
        f = open(path, 'rb')
        dat = csv.DictReader(f, delimiter='\t')
        for row in dat:
          infeasible_timepoints[row['hour']] = int(row['period'])
        f.close()
    
    # Summarize capacity shortfall by period
    cap_shortfall_by_period = {}
    if os.path.isfile(extra_peaker_path):
      f = open(extra_peaker_path, 'rb')
      dat = csv.DictReader(f, delimiter='\t')
      for row in dat:
        period = int(row['period'])
        if period not in cap_shortfall_by_period:
          cap_shortfall_by_period[period] = float(row['additional_capacity'])
        else: 
          cap_shortfall_by_period[period] += float(row['additional_capacity'])
      f.close()

    # Determine the cumulative capacity shortfalls from the incremental capacity additions that were needed
    cumulative_cap_shortfall = {}
    if len(cap_shortfall_by_period) > 0:
      # Initialize cumulative cap shortfall the earliest period with a shortfall and every subsequent period
      for period in filter(lambda p: p >= min(cap_shortfall_by_period.keys()), periods):
        cumulative_cap_shortfall[period] = 0
      # Propogate the incremental capacity shortfalls to the initialized cumulative variable
      for period_of_shortfall in cap_shortfall_by_period:
        for subsequent_period in filter(lambda p: p >= period_of_shortfall, periods):
          cumulative_cap_shortfall[subsequent_period] += cap_shortfall_by_period[period_of_shortfall]

    # Cross the infeasible timepoints with the capacity shortfalls to produce the summary records
    for period in cumulative_cap_shortfall:
      for tp in filter(lambda timepoint: infeasible_timepoints[timepoint] == period, infeasible_timepoints.keys()): 
        capacity_shortfalls.append( 
          {"period": str(period), "timepoint": tp, "carbon_cost": carbon_cost, 
           "test_set_id": test_set_id, 
           "cap_shortfall_mw": cumulative_cap_shortfall[period]})
      if len(filter(lambda timepoint: infeasible_timepoints[timepoint] == period, infeasible_timepoints.keys())) == 0: 
        capacity_shortfalls.append( 
          {"period": str(period), "timepoint": "?", "carbon_cost": carbon_cost, 
           "test_set_id": test_set_id, 
           "cap_shortfall_mw": cumulative_cap_shortfall[period]})
  
  # Retrieve emissions for this test set
  for dispatch_sums_path in glob.glob(test_dir + '/results/dispatch_sums_*'):
    carbon_cost = re.sub(r'^.*/dispatch_sums_(\d+).txt', r'\1', dispatch_sums_path)
    if carbon_cost not in emissions:
      emissions[carbon_cost] = {}
    f = open(dispatch_sums_path, 'rb')
    dat = csv.DictReader(f, delimiter='\t')
    for row in dat:
      period = int(row['period'])
      hours_in_sample = float(row['hours_in_sample'])
      co2_tons = float(row['co2_tons'])
      spinning_co2_tons = float(row['spinning_co2_tons'])
      deep_cycling_co2_tons = float(row['deep_cycling_co2_tons'])
      startup_co2_tons = float(row['startup_co2_tons'])
      if period not in emissions[carbon_cost]:
        emissions[carbon_cost][period] = {'co2_tons': 0, 'spinning_co2_tons': 0, 'deep_cycling_co2_tons': 0, 'startup_co2_tons': 0}
      emissions[carbon_cost][period]['co2_tons'] += co2_tons*hours_in_sample
      emissions[carbon_cost][period]['spinning_co2_tons'] += spinning_co2_tons*hours_in_sample
      emissions[carbon_cost][period]['deep_cycling_co2_tons'] += deep_cycling_co2_tons*hours_in_sample
      emissions[carbon_cost][period]['startup_co2_tons'] += startup_co2_tons*hours_in_sample

  # Retrieve biomass consumption for this test set
  for biomass_consumed_path in glob.glob(test_dir + '/results/biomass_consumed_*'):
    carbon_cost = re.sub(r'^.*/biomass_consumed_(\d+).txt', r'\1', biomass_consumed_path)
    if carbon_cost not in biomass_consumption:
      biomass_consumption[carbon_cost] = {}
    f = open(biomass_consumed_path, 'rb')
    dat = csv.DictReader(f, delimiter='\t')
    for row in dat:
      period = int(row['period'])
      load_area = row['load_area']
      consumption = float(row['biosolid_consumed_mmbtu'])
      if period not in biomass_consumption[carbon_cost]:
        biomass_consumption[carbon_cost][period] = {}
      if load_area not in biomass_consumption[carbon_cost][period]:
        biomass_consumption[carbon_cost][period][load_area] = consumption
        biomass_consumption_indexes.append( [ carbon_cost, period, load_area ] )
      else:
        biomass_consumption[carbon_cost][period][load_area] += consumption
    f.close()

  # Retrieve natural gas consumption for this test set
  for ng_consumed_path in glob.glob(test_dir + '/results/ng_consumed_*'):
    carbon_cost = re.sub(r'^.*/ng_consumed_(\d+).txt', r'\1', ng_consumed_path)
    if carbon_cost not in ng_consumption:
      ng_consumption[carbon_cost] = {}
    f = open(ng_consumed_path, 'rb')
    dat = csv.DictReader(f, delimiter='\t')
    for row in dat:
      period = int(row['period'])
      consumption = float(row['ng_consumed_mmbtu'])
      if period not in ng_consumption[carbon_cost]:
        ng_consumption[carbon_cost][period] = consumption
        ng_consumption_indexes.append( [ carbon_cost, period ] )
      else:
        ng_consumption[carbon_cost][period] += consumption
    f.close()


# Determine the projected consumption levels for biomass
for biomass_projections_path in glob.glob('common_inputs/biomass_consumption_and_prices_by_period_*'):
  carbon_cost = re.sub(r'^.*/biomass_consumption_and_prices_by_period_(\d+).tab', r'\1', biomass_projections_path)
  if carbon_cost not in biomass_consumption_projections:
    biomass_consumption_projections[carbon_cost] = {}
  f = open(biomass_projections_path, 'rb')
  # The .tab files have an extra header line at the top for ampl, and I need to move the "cursor"
  # in the file object to the second line before I call the DictReader parser.
  ampl_header = f.next()
  dat = csv.DictReader(f, delimiter='\t')
  for row in dat:
    period = int(row['period'])
    load_area = row['load_area']
    breakpoint_id = int(row['breakpoint_id'])
    projected_consumption = float(row['breakpoint_mmbtu_per_year'])
    if breakpoint_id != 1: continue
    if period not in biomass_consumption_projections[carbon_cost]:
      biomass_consumption_projections[carbon_cost][period] = {}
    biomass_consumption_projections[carbon_cost][period][load_area] = projected_consumption
  f.close()

# Determine the projected consumption levels for natural gas
for ng_projections_path in glob.glob('common_inputs/ng_consumption_and_prices_by_period_*'):
  carbon_cost = re.sub(r'^.*/ng_consumption_and_prices_by_period_(\d+).tab', r'\1', ng_projections_path)
  if carbon_cost not in ng_consumption_projections:
    ng_consumption_projections[carbon_cost] = {}
  f = open(ng_projections_path, 'rb')
  # The .tab files have an extra header line at the top for ampl, and I need to move the "cursor"
  # in the file object to the second line before I call the DictReader parser.
  ampl_header = f.next()
  dat = csv.DictReader(f, delimiter='\t')
  for row in dat:
    period = int(row['period'])
    breakpoint_id = int(row['breakpoint_id'])
    projected_consumption = float(row['ng_consumption_breakpoint'])
    if breakpoint_id != 1: continue
    ng_consumption_projections[carbon_cost][period] = projected_consumption
  f.close()

# Print the summary output files, all as tab delimited text files. 
delimiter="\t"

# Summarize biomass consumption levels
# sort records by amount of overconsumption
biomass_consumption_indexes.sort(reverse=True, 
  key=lambda x: 
    biomass_consumption[x[0]][x[1]][x[2]] - biomass_consumption_projections[x[0]][x[1]][x[2]])
summary_output = open("biomass_consumption_summary.txt","w")
summary_output.write(delimiter.join( [
    "scenario_id", "carbon_cost", "period", 
    "load_area", "consumption", "projected_consumption", "percent_over" 
  ]) + "\n")
for carbon_cost, period, load_area in biomass_consumption_indexes: 
  summary_output.write(delimiter.join( [
    scenario_id, carbon_cost, str(period), load_area, 
    str(biomass_consumption[carbon_cost][period][load_area]),
    str(biomass_consumption_projections[carbon_cost][period][load_area]),
    str((biomass_consumption[carbon_cost][period][load_area] - biomass_consumption_projections[carbon_cost][period][load_area]) / biomass_consumption_projections[carbon_cost][period][load_area]) 
  ]) + "\n")
summary_output.close()


# Summarize natural gas consumption levels
# sort records by amount of overconsumption
ng_consumption_indexes.sort(reverse=True, 
  key=lambda x: 
    ng_consumption[x[0]][x[1]] - ng_consumption_projections[x[0]][x[1]])
summary_output = open("ng_consumption_summary.txt","w")
summary_output.write(delimiter.join( [
    "scenario_id", "carbon_cost", "period", 
    "consumption", "projected_consumption", "percent_over" 
  ]) + "\n")
for carbon_cost, period in ng_consumption_indexes: 
  summary_output.write(delimiter.join( [
    scenario_id, carbon_cost, str(period), 
    str(ng_consumption[carbon_cost][period]),
    str(ng_consumption_projections[carbon_cost][period]),
    str((ng_consumption[carbon_cost][period] - ng_consumption_projections[carbon_cost][period]) / ng_consumption_projections[carbon_cost][period])
  ]) + "\n")
summary_output.close()


# Summarize emission levels
summary_output = open("emissions_summary.txt","w")
summary_output.write(delimiter.join( [
    "scenario_id", "carbon_cost", "period", 
    "co2_tons", "spinning_co2_tons", "deep_cycling_co2_tons", "startup_co2_tons", "total_co2_tons", "target_co2_tons", "fraction_over_target", "emissions_frac_of_1990", "target_frac_of_1990" 
  ]) + "\n")
for carbon_cost in emissions:
  for period in emissions[carbon_cost]: 
    emissions[carbon_cost][period]['total'] = \
      emissions[carbon_cost][period]['co2_tons'] + \
      emissions[carbon_cost][period]['spinning_co2_tons'] + \
      emissions[carbon_cost][period]['deep_cycling_co2_tons'] + \
      emissions[carbon_cost][period]['startup_co2_tons']        
    summary_output.write(delimiter.join( [
      scenario_id, carbon_cost, str(period), 
      str(emissions[carbon_cost][period]['co2_tons']),
      str(emissions[carbon_cost][period]['spinning_co2_tons']),
      str(emissions[carbon_cost][period]['deep_cycling_co2_tons']),
      str(emissions[carbon_cost][period]['startup_co2_tons']),
      str(emissions[carbon_cost][period]['total'] ),
      str(emission_targets[period]),
      str((emissions[carbon_cost][period]['total'] - emission_targets[period]) / emission_targets[period]),
      str(emissions[carbon_cost][period]['total']/num_years_per_period/emissions_1990),
      str(emission_targets[period]/num_years_per_period/emissions_1990)
    ]) + "\n")
summary_output.close()


# Sort the capacity shortfall records by the magnitude of shortfall
capacity_shortfalls.sort(key=lambda x: x["cap_shortfall_mw"], reverse=True)
# Write out the results
summary_output = open("cap_shortfall_summary.txt","w")
summary_output.write(delimiter.join( [
    "scenario_id", "carbon_cost", "test_set_id", 
    "timepoint", "period", "capacity_shortfall_mw" ]) 
  + "\n")
for record in capacity_shortfalls: 
  summary_output.write(delimiter.join( [
      scenario_id, record["carbon_cost"], record["test_set_id"], 
      record["timepoint"], record["period"], str(record["cap_shortfall_mw"]) ] )
  + "\n")
summary_output.close()
