
set search_path to chile;

--select define_new_training_sets();

--select * from scenarios_switch_chile;


drop table if exists training_set_timepoints;
drop table if exists training_set_periods;
drop table if exists training_sets CASCADE;

--drop table if exists training_set_timepoints_backup;

SELECT * FROM scenarios_switch_chile;