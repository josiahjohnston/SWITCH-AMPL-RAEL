How to run dispatch verification on the complete set of historic data.

• Run the normal optimizations in the base directory and export the results. 
• Go to a cluster environment.
• Run ./get_test_inputs.sh
• Run ./run_dispatch.sh
• After the jobs have finished, import by executing:
	./import.sh


Implementation description

Dispatch uses the database table dispatch_test_sets in the switch inputs database. The dispatch table has a similar structure to the _training_set_timepoints table: one row per timepoint that is included in the set. Both tables are defined in Setup_Study_Hours.sql. 
The dispatch table is populated as the same time as the _training_set_timepoints table when the function define_new_training_sets() is called.

...


svn rm test.run run_all_weeks.sh refresh_results_all_weeks.sh 
svn add ...
