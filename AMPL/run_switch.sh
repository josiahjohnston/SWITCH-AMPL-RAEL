#!/bin/bash
if [ $# -ne 1 ]; then
  echo "This script needs one argument: the number of workers on this job."
  exit
fi

WORKER_ID=$(getid | awk '{print $1}')
NUM_WORKERS=$1

# Make a path for this processes log files based on the name of the node this is running on (hostname) and the process id of this process ($$)
log_base="logs/"$(hostname)"_pid$$_switch"
# Start ampl and log appropriately
echo "About to start AMPL on "$(hostname)" with worker $WORKER_ID of $NUM_WORKERS" > $log_base
echo "include windsun.run; let worker_id := $WORKER_ID; let num_workers := $NUM_WORKERS; include switch.run; exit;" | ampl 1>$log_base".log" 
2>$log_base".error_log" 
echo "AMPL has exited." >> $log_base
