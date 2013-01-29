#!/usr/bin/env python
import os
import glob
import re
import csv

scenario_id = str(int(open("scenario_id.txt").read()))
capacity_shortfalls = [];
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
        

# Sort the resulting data by magnitude of shortfall
capacity_shortfalls.sort(key=lambda x: x["cap_shortfall_mw"], reverse=True)
# Write out the results
summary_output = open("cap_shortfall_summary.txt","w")
delimiter="\t"
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
