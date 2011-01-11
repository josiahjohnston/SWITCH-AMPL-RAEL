README

• Run the normal optimizations. 
• Ensure that makeTestSets.sql and makeDispatchWeeks.sql in the DatabasePrep directory have been run. 
• Go to the AMPL directory, open ampl, and include save_investments.run. This saves all of the investment decisions for each carbon price solution under dispatch/common_inputs
• Go to the dispatch directory and run get_test_inputs.sh from the command line. 
• Create a batch file for executing each week separately. This command will create a job file with one week per line: 
	./run_all_weeks.sh > jobs_list.txt
• If you are on the cluster, edit dispatch.qsub and update the working directory. Then type 
	qsub dispatch.qsub
• If you aren't on the cluster, you can execute all of the jobs sequentially by typing:
	source jobs_list.txt
• After the jobs have finished executing, import by executing:
	./import.sh
