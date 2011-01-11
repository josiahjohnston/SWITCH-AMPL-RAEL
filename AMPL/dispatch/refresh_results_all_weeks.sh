#!/bin/bash

for d in $(ls -1d week*); do
	echo "Executing $d..."
	cd $d;
	echo 'include test.run; exit;' | ampl 
	if [ $(ls -1 results | grep -e 'sol$' | wc -l | sed 's/ //g') -eq 0 ]; then 
		echo "$w_path did not produce a solution."
	fi
	cd ..
done
