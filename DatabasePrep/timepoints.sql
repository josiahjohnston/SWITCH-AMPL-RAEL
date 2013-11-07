set search_path to wecc_inputs, public;

-- create a table of timepoints which will be referenced by hourly data henceforth
-- the timestamp here is implicitly Universal Coordinated Time (UTC)
drop table if exists timepoints cascade;
create table timepoints (
	timepoint_id serial PRIMARY KEY ,
	timepoint TIMESTAMP NOT NULL,
	date DATE,
	year smallint,
	month_of_year smallint,
	day_of_month smallint,
	hour_of_day smallint,
	UNIQUE (timepoint)
);

insert into timepoints (timepoint)
	select generate_series('2004-1-1 00:00'::timestamp, '2060-1-2 00:00'::timestamp, '1 hours');
	
update timepoints set
	date = DATE(timepoint),
	year = EXTRACT(YEAR FROM timepoint),
	month_of_year = EXTRACT(MONTH FROM timepoint),
	day_of_month = EXTRACT(DAY FROM timepoint),
	hour_of_day = EXTRACT(HOUR FROM timepoint);
	
create index on timepoints (year);
create index on timepoints (date);
create index on timepoints (month_of_year, day_of_month, hour_of_day);
create index on timepoints (month_of_year);
create index on timepoints (day_of_month);
create index on timepoints (hour_of_day);
