#!/bin/bash

if [ -z $(which getid) ]; then
	NUM_WORKERS=1
	WORKER_ID=0
else
	if [ $# -ne 1 ]; then
		echo "This script needs one argument: the number of workers on this job."
		exit
	fi
	WORKER_ID=$(getid | awk '{print $1}')
	NUM_WORKERS=$1
fi
if [ ! -d logs ]; then mkdir logs; fi

# Make a path for this processes log files based on the name of the node this is running on (hostname) and the process id of this process ($$)
log_base="logs/"$(hostname)"_pid$$_switch"
# Start ampl and log appropriately
echo "Starting AMPL on "$(hostname)" with worker $WORKER_ID of $NUM_WORKERS. Logs written to $log_base..."
#printf "AMPL commands are:\n   include windsun.run; let worker_id := $WORKER_ID; let num_workers := $NUM_WORKERS; let compile_mip_only := 1; include switch.run; exit;\n"
echo "include windsun.run; let worker_id := $WORKER_ID; let num_workers := $NUM_WORKERS; let compile_mip_only := 1; include switch.run; exit;" | ampl 1>$log_base".log"  2>$log_base".error_log" 
echo "	AMPL finished compiling the problems and has exited. About to solve them with cplex." >> $log_base
cplex_options=$(sed -e "s/^[^']*'\([^']*\)'.*$/\1/" results/cplex_options)
for f in $(ls -1 results/*nl); do 
  base_name=$(echo $f | sed "s/\.nl//"); 
  if [ ! -f $base_name.sol ]; then 
#    echo "  cplexamp params are: $base_name -AMPL $cplex_options"
    cplexamp $base_name -AMPL "$cplex_options" 1>>$log_base"_cplex.log" 2>>$log_base"_cplex.error_log"; 
    echo "  cplexamp finished solving $base_name"
  fi; 
done; 
echo "	Using AMPL to parse cplex solutions and write result files."
echo 'include windsun.run; let worker_id := $WORKER_ID; let num_workers := $NUM_WORKERS; let compile_mip_only := 1; include switch.run; exit;' | ampl 1>>$log_base".log"  2>>$log_base".error_log" 
