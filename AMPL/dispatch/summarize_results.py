#!/usr/bin/env python
import os
import glob
import re
import csv

capacity_shortfalls = []
ng_consumption = {}                    # indexed by carbon cost & period
ng_consumption_projections = {}
biomass_consumption = {}               # indexed by carbon cost, period & load area
biomass_consumption_projections = {}
biomass_consumption_indexes = []
ng_consumption_indexes = []

scenario_id = str(int(open("scenario_id.txt").read()))

for test_dir in glob.glob('test_set_*'):
  test_set_id = test_dir.replace('test_set_','')
  for extra_peaker_path in glob.glob(test_dir + '/results/dispatch_extra_peakers_*'):
    carbon_cost = re.sub(r'^.*/dispatch_extra_peakers_(\d+).txt', r'\1', extra_peaker_path)
    load_infeasible_path = extra_peaker_path.replace('dispatch_extra_peakers','load_infeasibilities')
    balancing_infeasible_path = extra_peaker_path.replace('dispatch_extra_peakers','balancing_infeasibilities')

    # Make a unique list of infeasible timepoints referenced in the two infeasibility files 
    infeasible_timepoints = {}
    if os.path.isfile(load_infeasible_path):
      f = open(load_infeasible_path, 'rb')
      dat = csv.reader(f, delimiter='\t')
      col_headers = dat.next()
      for row in dat:
        period = row[2]
        timepoint = row[5]
        infeasible_timepoints[timepoint] = period
      f.close()
    if os.path.isfile(balancing_infeasible_path):
      f = open(balancing_infeasible_path, 'rb')
      dat = csv.reader(f, delimiter='\t')
      col_headers = dat.next()
      for row in dat:
        period = row[2]
        timepoint = row[4]
        infeasible_timepoints[timepoint] = period
      f.close()
    
    # Summarize capacity shortfall by period
    cap_shortfall_by_period = {}
    if os.path.isfile(extra_peaker_path):
      f = open(extra_peaker_path, 'rb')
      dat = csv.reader(f, delimiter='\t')
      col_headers = dat.next()
      for row in dat:
        period = row[2]
        cap_shortfall = row[14]
        if period not in cap_shortfall_by_period.keys():
          cap_shortfall_by_period[period] = float(cap_shortfall)
        else: 
          cap_shortfall_by_period[period] += float(cap_shortfall)
      f.close()

    # Update the capacity shortfalls to include capacity was built in earlier periods
    for period1 in cap_shortfall_by_period.keys():
      for period2 in cap_shortfall_by_period.keys():
        if period2 < period1:
          cap_shortfall_by_period[period1] += cap_shortfall_by_period[period2]

    # Cross the infeasible timepoints with the capacity shortfalls to produce the summary records
    for period in cap_shortfall_by_period.keys():
      for tp in filter(lambda x: infeasible_timepoints[x] == period, infeasible_timepoints.keys()): 
        capacity_shortfalls.append( 
          {"period": period, "timepoint": tp, "carbon_cost": carbon_cost, 
           "test_set_id": test_set_id, 
           "cap_shortfall_mw": cap_shortfall_by_period[period]})
      if len(filter(lambda x: infeasible_timepoints[x] == period, infeasible_timepoints.keys())) == 0: 
        capacity_shortfalls.append( 
          {"period": period, "timepoint": "?", "carbon_cost": carbon_cost, 
           "test_set_id": test_set_id, 
           "cap_shortfall_mw": cap_shortfall_by_period[period]})
  
  # Add the biomass consumption for this test set
  for biomass_consumed_path in glob.glob(test_dir + '/results/biomass_consumed_*'):
    carbon_cost = re.sub(r'^.*/biomass_consumed_(\d+).txt', r'\1', biomass_consumed_path)
    if carbon_cost not in biomass_consumption.keys():
      biomass_consumption[carbon_cost] = {}
    f = open(biomass_consumed_path, 'rb')
    dat = csv.reader(f, delimiter='\t')
    col_headers = dat.next()
    for row in dat:
      period = row[2]
      load_area = row[4]
      consumption = float(row[6])
      if period not in biomass_consumption[carbon_cost].keys():
        biomass_consumption[carbon_cost][period] = {}
      if load_area not in biomass_consumption[carbon_cost][period].keys():
        biomass_consumption[carbon_cost][period][load_area] = consumption
        biomass_consumption_indexes.append( [ carbon_cost, period, load_area ] )
      else:
        biomass_consumption[carbon_cost][period][load_area] += consumption
    f.close()

  # Add the biomass consumption for this test set
  for ng_consumed_path in glob.glob(test_dir + '/results/ng_consumed_*'):
    carbon_cost = re.sub(r'^.*/ng_consumed_(\d+).txt', r'\1', ng_consumed_path)
    if carbon_cost not in ng_consumption.keys():
      ng_consumption[carbon_cost] = {}
    f = open(ng_consumed_path, 'rb')
    dat = csv.reader(f, delimiter='\t')
    col_headers = dat.next()
    for row in dat:
      period = row[2]
      consumption = float(row[4])
      if period not in ng_consumption[carbon_cost].keys():
        ng_consumption[carbon_cost][period] = consumption
        ng_consumption_indexes.append( [ carbon_cost, period ] )
      else:
        ng_consumption[carbon_cost][period] += consumption
    f.close()

# Determine the projected consumption levels for biomass
for biomass_projections_path in glob.glob('common_inputs/biomass_consumption_and_prices_by_period_*'):
  carbon_cost = re.sub(r'^.*/biomass_consumption_and_prices_by_period_(\d+).tab', r'\1', biomass_projections_path)
  if carbon_cost not in biomass_consumption_projections.keys():
    biomass_consumption_projections[carbon_cost] = {}
  f = open(biomass_projections_path, 'rb')
  dat = csv.reader(f, delimiter='\t')
  ampl_header = dat.next()
  col_headers = dat.next()
  for row in dat:
    period = row[1]
    load_area = row[0]
    breakpoint_id = row[2]
    projected_consumption = float(row[3])
    if int(breakpoint_id) != 1: continue
    if period not in biomass_consumption_projections[carbon_cost].keys():
      biomass_consumption_projections[carbon_cost][period] = {}
    biomass_consumption_projections[carbon_cost][period][load_area] = projected_consumption
  f.close()

# Determine the projected consumption levels for natural gas
for ng_projections_path in glob.glob('common_inputs/ng_consumption_and_prices_by_period_*'):
  carbon_cost = re.sub(r'^.*/ng_consumption_and_prices_by_period_(\d+).tab', r'\1', ng_projections_path)
  if carbon_cost not in ng_consumption_projections.keys():
    ng_consumption_projections[carbon_cost] = {}
  f = open(ng_projections_path, 'rb')
  dat = csv.reader(f, delimiter='\t')
  ampl_header = dat.next()
  col_headers = dat.next()
  for row in dat:
    period = row[0]
    breakpoint_id = row[1]
    projected_consumption = float(row[2])
    if int(breakpoint_id) != 1: continue
    ng_consumption_projections[carbon_cost][period] = projected_consumption
  f.close()


# Start printing the summary output
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
    scenario_id, carbon_cost, period, load_area, 
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
    scenario_id, carbon_cost, period, 
    str(ng_consumption[carbon_cost][period]),
    str(ng_consumption_projections[carbon_cost][period]),
    str((ng_consumption[carbon_cost][period] - ng_consumption_projections[carbon_cost][period]) / ng_consumption_projections[carbon_cost][period])
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
