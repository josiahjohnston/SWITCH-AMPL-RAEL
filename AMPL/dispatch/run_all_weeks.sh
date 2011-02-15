#!/bin/bash
if [ -z "$ILOG_LICENSE_FILE" ]; then
        env_vars="ILOG_LICENSE_FILE=/global/home/groups/dkammen/software/centos-5.x86_64/modules/ampl-cplex/bin/access.ilm; " 
else
        env_vars="ILOG_LICENSE_FILE=$ILOG_LICENSE_FILE"
fi
if [ -z "$ZIENA_LICENSE_NETWORK_ADDR" ] ; then
        env_vars=$env_vars"ZIENA_LICENSE_NETWORK_ADDR=rael.berkeley.edu:8349;"
else
        env_vars=$env_vars"ZIENA_LICENSE_NETWORK_ADDR=$ZIENA_LICENSE_NETWORK_ADDR;"
fi
#env_vars="ILOG_LICENSE_FILE=/global/home/groups/dkammen/software/centos-5.x86_64/modules/ampl-cplex/bin/access.ilm; ZIENA_LICENSE_NETWORK_ADDR=rael.berkeley.edu:8349;"

for d in $(ls -1d week*); do
	printf "$env_vars cd $d; echo 'include test.run; exit;' | ampl 1>>../logs/switch.$d.log 2>>../logs/switch.$d.error_log; for f in "'$(ls -1 results/*nl)'"; do base_name="'$(echo $f | sed "s/\.nl//")'"; if [ ! -f \$base_name.sol ]; then cplexamp \$base_name -AMPL 'lpdisplay=1 iisfind=1 mipdisplay=2 presolve=1 prestats=1 timing=1 threads=1' 1>>../logs/cplexamp.$d.log 2>>../logs/cplexamp.$d.error_log; fi; done; echo 'include test.run; exit;' | ampl 1>>../logs/switch.$d.log 2>>../logs/switch.$d.error_log; if [ "'$(ls -1 results | grep -e "sol$" | wc -l | sed "s/ //g")'" -ne "'$(ls -1 results | grep -e "nl$" | wc -l | sed "s/ //g")'" ]; then echo $d' did not produce a solution.'; fi; cd ..;\n"
done
