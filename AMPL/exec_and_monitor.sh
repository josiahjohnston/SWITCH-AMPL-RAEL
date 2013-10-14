#!/bin/bash

# Call AMPL to compile the problem; hand it off to cplex. Profile them both till they die.

./run_switch.sh 1 &
worker_pid=$(jobs -l | grep './run_switch.sh' | awk '{print $2}')
echo "worker_pid is $worker_pid"


if [ ! -f profile_data.txt ]; then
	printf "%s\t%s\n" "date" "$(ps -eo pid,ppid,rss,vsize,pcpu,pmem,cmd -ww --sort=pid | head -n1)" >> profile_data.txt;
fi

i=0
while [ $(jobs | wc -l) -gt 0 ]; do
	ps -eo pid,ppid,rss,vsize,pcpu,pmem,cmd -ww --sort=pid |
		grep $worker_pid |
		grep -v grep |
		while read line; do 
			printf "%s %s\n" "$(date +%T)" "$line" >> profile_data.txt;
		done
	sleep 5
	i=$(($i+1))
	if [ $i -ge 120 ]; then
		i=0
		ps -eo pid,ppid,rss,vsize,pcpu,pmem,cmd -ww --sort=pid >> full_ps_list.txt
	fi
done
