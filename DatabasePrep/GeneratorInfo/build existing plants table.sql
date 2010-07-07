use generator_info;

--########################
-- build a table of data on existing plants
-- Assumptions:
-- eia_sector = 3, 5, or 7 for cogen plants; others are electricity-only
-- dispatchable plants are eia_sector 1, 2, 6 with the main fuel = "NG" (gas)
-- baseload plants are all others, if fuel is "COL", "GEO", "NUC"

-- Cogen plants are 80% efficient (i.e., produce 0.8 units of electricity 
-- for every extra unit of heat they use, compared to a steam-only plant or mode)

-- efficiency of non-cogen plants is based on net_gen_mwh and elec_fuel_mbtu
-- efficiency and fuel are based on the predominant fuel and the sum of all primemovers at each plant

-- From Matthias... check at some point:
-- capacity factor (i.e., forced outage rate for baseload plants) is based on all fuels and all primemovers


-- cost for each primemover-fuel combination is as follows:


-- first, get data (aggregated to plant-primemover level) from eia906 database
-- this includes the primary fuel, heat rate when using the primary fuel, and total net_gen_mwh for all fuels

-- gets all of the plants in wecc, as assigned in grid.eia860gen07_us from postgresql
-- we appear to lose one very small (net_generation__mwh=1077) NG plant (plntcode = 56508) because it doesn't appear in grid.eia860gen07_us... don't think this should be a problem.
-- note: does not remove retired or out of service generators yet.  This will be done when summing up the generation and fuel consumption because some plants have parts that are operational and some that aren't.

-- a few generators are left out of the load area identifiation because they're in the ocean, most importantly a 2GW nuke near San Diego.
-- this updates their load_areas...
update eia860plant07_postgresql set load_area = 'CA_SCE_S' where plntcode = 56051;
update eia860plant07_postgresql set load_area = 'CA_SDGE' where plntcode = 360;

	
drop table if exists weccplants;
create table weccplants
	select 	distinct(eia860plant07_postgresql.plntcode),
			eia860plant07_postgresql.load_area
	from eia860plant07_postgresql
	where load_area is not null
	and load_area not like ''
	order by plntcode;
	
-- netgenerators gets the non-hydro plant-primemovers for which the net generation in 2007 was greater than zero.
drop table if exists maxgen;
create table maxgen 
	SELECT 	grid.eia906_07_US.plntcode,
			grid.eia906_07_US.primemover,
			grid.eia906_07_US.aer_fuel_type_code,
			max(grid.eia906_07_US.net_generation_megawatthours) as net_generation_megawatthours,
			weccplants.load_area
			FROM 	grid.eia906_07_US,
					weccplants,
					(select *
					from (SELECT 	plntcode,
									primemover,
									sum(net_generation_megawatthours) as netmwh
									FROM grid.eia906_07_US
									where primemover not in ('HY', 'PS')
									group by plntcode, primemover)
					as generators where netmwh > 0) as netgenerators
	 where grid.eia906_07_US.primemover not in ('HY', 'PS')
	 and grid.eia906_07_US.plntcode = weccplants.plntcode
	 and netgenerators.plntcode = grid.eia906_07_US.plntcode
	 and netgenerators.primemover = grid.eia906_07_US.primemover
	 and grid.eia906_07_US.net_generation_megawatthours > 0
	 group by 1,2,3
	 order by plntcode;

-- finds plant-primemovers that use multiple fuels by the table 'count'
-- note that net_generation_megawatthours is a handle for figuring out which fuel type is the primary type
-- it will later be aggreagted to be the maximum generation by all units of a plant that share the same primemover and fuel.
drop table if exists primaryfuel_for_multigen;
create table primaryfuel_for_multigen
	select maxgen.*
	from
		maxgen,
		(select single_or_multifuel.plntcode,
				single_or_multifuel.primemover,
				max(maxgen.net_generation_megawatthours) as maxgen_mwh
		from 	maxgen,
				(SELECT plntcode,
						primemover,
						aer_fuel_type_code,
						count(plntcode) as count
					FROM maxgen
					group by plntcode, primemover) as single_or_multifuel
		where count > 1
		and single_or_multifuel.plntcode = maxgen.plntcode
		and single_or_multifuel.primemover = maxgen.primemover
		group by 1,2) as multifuel_plants_maxgen
where multifuel_plants_maxgen.maxgen_mwh = maxgen.net_generation_megawatthours
and multifuel_plants_maxgen.plntcode = maxgen.plntcode
and multifuel_plants_maxgen.primemover = maxgen.primemover;

-- now replace the entries in maxgen for multifuel plant-primemovers with the fuel type that generates the most power.
delete from maxgen
	where (maxgen.plntcode, maxgen.primemover) in (select plntcode, primemover from primaryfuel_for_multigen);
insert into maxgen (select * from primaryfuel_for_multigen);

-- deletes any fuel type that Switch can't handle yet... should include more in the future.
delete FROM maxgen where aer_fuel_type_code not in ("NUC", "COL", "NG", "GEO");
-- deletes the only very small NG (net_generation_mwh=8) plant that has a primemover of 'OT'
delete FROM maxgen where primemover like 'OT';

-- adds a column for fuel consumption
-- inserts aggregated fuel consumption and electricty production to prepare to caluclate heat rate.
alter table maxgen add column elec_fuel_consumption_mmbtus double;
update 	maxgen,
		(SELECT plntcode,
				primemover,
				aer_fuel_type_code,
				sum(elec_fuel_consumption_mmbtus) as elec_fuel_consumption_mmbtus,
				sum(net_generation_megawatthours) as net_generation_megawatthours
		FROM grid.eia906_07_US
		group by 1,2,3) as fuel_consumption_generation
set maxgen.elec_fuel_consumption_mmbtus = fuel_consumption_generation.elec_fuel_consumption_mmbtus,
maxgen.net_generation_megawatthours = fuel_consumption_generation.net_generation_megawatthours
where fuel_consumption_generation.plntcode = maxgen.plntcode
and fuel_consumption_generation.primemover = maxgen.primemover
and fuel_consumption_generation.aer_fuel_type_code = maxgen.aer_fuel_type_code;

-- lookup the total power generated by each plant-primemover
-- (for the model, we will assume that all of this is generated using the predominant fuel)
alter table maxgen add column avg_gen_mw double;
update maxgen set avg_gen_mw = net_generation_megawatthours/8760;

-- add nameplate capacity
-- excludes retired ('re') and out of service ('os') plants
alter table maxgen add column nameplate_mw double;

update maxgen, 
		(select plntcode, primemover, sum(nameplate) as nameplate_mw from grid.eia860gen07_US where status not like 're' and status not like 'os' group by plntcode, primemover) as calcnameplate
set maxgen.nameplate_mw = calcnameplate.nameplate_mw
where maxgen.plntcode = calcnameplate.plntcode
and maxgen.primemover = calcnameplate.primemover;

-- for rouge plants (ones that don't match on primemover), the nameplate code can't find the nameplate capacity, so it's updated seperatly here.
update 	maxgen,
			(SELECT 	plntcode,
					sum(nameplate) as nameplate_mw
			from eia860gen07
			where plntcode in (select plntcode from maxgen where nameplate_mw is null)
			group by plntcode) as rouge_plant_table
set maxgen.nameplate_mw = rouge_plant_table.nameplate_mw
where rouge_plant_table.plntcode = maxgen.plntcode;

-- one really small plant (1077 MWh) doesn't match, so we delete it here...
delete from maxgen where nameplate_mw is null;

-- updates eia sector number and cogen
alter table maxgen add column eia_sector_number int;
alter table maxgen add column cogen char(1);

update maxgen,
	(select plntcode, primemover, eia_sector_number, combined_heat_and_power_plant as cogen from grid.eia906_07_US group by 1, 2) as sector_cogen
set maxgen.eia_sector_number = sector_cogen.eia_sector_number,
maxgen.cogen = sector_cogen.cogen
where sector_cogen.plntcode = maxgen.plntcode
and sector_cogen.primemover = maxgen.primemover;

-- the model doesn't currently run existing combustion turbines because they're aggregated by this code
-- and mislabeled as CCs.... the actual running of them won't change... should be fixed in ther larger existing plant revision
drop table if exists combined_cycle_update;
create temporary table combined_cycle_update
	select 	maxgen.plntcode,
			'CC' as primemover,
			aer_fuel_type_code,
			sum(net_generation_megawatthours) as net_generation_megawatthours,
			load_area,
			sum(elec_fuel_consumption_mmbtus) as elec_fuel_consumption_mmbtus,
			sum(avg_gen_mw) as avg_gen_mw,
			sum(nameplate_mw) as nameplate_mw,
			eia_sector_number,
			cogen
		from maxgen
where maxgen.primemover in ('CA', 'CT', 'CS')
group by maxgen.plntcode;

delete from maxgen where primemover in ('CA', 'CT', 'CS');

insert into maxgen
select * from combined_cycle_update;


-- the latest year is chosen for plant-primemovers that have generators that came online in many years.
-- might lose a CC or two, but this will be filled out in the plant update.
drop table if exists existing_plants;
create table existing_plants
select 	maxgen.plntcode,
		maxgen.primemover,
		maxgen.aer_fuel_type_code as aer_fuel,
		maxgen.net_generation_megawatthours as net_gen_mwh,
		maxgen.elec_fuel_consumption_mmbtus as fuel_consumption,
		maxgen.eia_sector_number,
		maxgen.cogen,
		maxgen.load_area,
		sum(eia860gen07.nameplate) as nameplate,
		(sum(eia860gen07.nameplate)/maxgen.nameplate_mw)*maxgen.avg_gen_mw as avg_mw,
		sum((eia860gen07.Summer_Capacity+eia860gen07.Winter_Capacity)/2) as peak_mw,
		max(eia860gen07.Operating_Year) as invsyear
from maxgen, eia860gen07
where maxgen.plntcode = eia860gen07.plntcode
and (maxgen.primemover = eia860gen07.primemover
	or (maxgen.primemover like 'CC' and eia860gen07.primemover in ('CA', 'CT', 'CS') and maxgen.plntcode = eia860gen07.plntcode))
group by eia860gen07.plntcode, eia860gen07.primemover;


-- add heat rates
alter table existing_plants add column heat_rate double;
update existing_plants, (SELECT plntcode, primemover, sum(fuel_consumption)/sum(net_gen_mwh) as heat_rate FROM existing_plants group by plntcode, primemover) as heat_rate_calc
set existing_plants.heat_rate = heat_rate_calc.heat_rate
where existing_plants.plntcode = heat_rate_calc.plntcode
and existing_plants.primemover = heat_rate_calc.primemover;

-- two GTs have heat_rates of ~1000, not the ~10000 that they should have..
-- I'm assuming that this is because someone (not me... I checked) messed up a decimal point somewhere
-- I therefore multiply their heat rates by 10, which returns a normal heat rate for GTs
update existing_plants set heat_rate = 10 * heat_rate where heat_rate < 2;

-- fill in baseload (as described at top of file)
alter table existing_plants add column baseload int;
update existing_plants set baseload = if(eia_sector_number in (1, 2, 6) and aer_fuel="NG", 0, 1);

-- fill in cogen
update existing_plants set cogen = if(cogen like 'Y', 1, 0);
ALTER TABLE existing_plants MODIFY COLUMN cogen TINYINT;


-- aggregate the plants as much as possible.
-- we assume all cogen plants have the same efficiency for electricity production (0.8),
-- and that none of them will be retired during the study, so they can all be aggregated within each load zone.
-- TODO: get a better efficiency estimate for cogen plants, maybe treat retirements better

drop table if exists existing_plants_agg;
CREATE TABLE  existing_plants_agg(
  ep_id mediumint unsigned PRIMARY KEY AUTO_INCREMENT,
  load_area varchar(11),
  plant_code varchar(30),
  gentype varchar(4),
  aer_fuel varchar(20),
  peak_mw double,
  avg_mw double,
  heat_rate double,
  start_year year(4),
  baseload int(11),
  cogen int(1) NOT NULL default '0',
  overnight_cost double,
  fixed_o_m double,
  variable_o_m double,
  forced_outage_rate double,
  scheduled_outage_rate double,
  max_age double,
  intermittent tinyint(1) default '0',
  technology varchar(64)
);



insert into existing_plants_agg (load_area, plant_code, gentype, aer_fuel, peak_mw, avg_mw, heat_rate, start_year, baseload, cogen)
  select load_area, concat(plntcode, "-", primemover) as plant_code, primemover as gentype, aer_fuel, 
    sum(peak_mw) as peak_mw, sum(avg_mw) as avg_mw, avg(heat_rate) as heat_rate, max(invsyear) as start_year,
    baseload, 0 as cogen
    from existing_plants where cogen = 0
	group by plntcode, gentype;

insert into existing_plants_agg (load_area, plant_code, gentype, aer_fuel, peak_mw, avg_mw, heat_rate, start_year, baseload, cogen)
  select load_area, concat("cogen-", plntcode, "-", primemover, "-", aer_fuel) as plant_code, primemover as gentype, aer_fuel, 
    sum(peak_mw) as peak_mw, sum(avg_mw) as avg_mw, 3.412 / 0.8 as heat_rate, max(invsyear) as start_year,
    1 as baseload, 1 as cogen 
    from existing_plants where cogen = 1
    group by 1, 2, 3, 4;

-- a few plants have a bit of extra average capacity over peak, so we set the peak capacity to the average.
update existing_plants_agg set peak_mw = avg_mw where avg_mw > peak_mw;





----------------------------------------------------------------
-- this code was run before the above code, which takes v1 WECC l

-- CANADA and MEXICO

-- now we bring in nonhydro Canadian and Mexican generators from the TEPPC data.

-- selects out generators that we want.
-- we took out SynCrude plants... they are a few hundred MW of generation in Alberta but we don't have time to deal with them at the moment... should be put in at some point
drop table if exists canmexgen;
create table canmexgen
SELECT 	name,
		area as load_area,
		categoryname,
		upper(left(categoryname, 2)) as primemover,
		year(commissiondate) as start_year,
		mincap as min_mw,
		(mincap+maxcap)/2 as avg_mw,
		maxcap as peak_mw,
		heatrate
FROM grid.TEPPC_Generators
where (area like 'cfe' or area like 'bctc' or area like 'aeso')
and categoryname not like 'canceled'
and categoryname not like '% Future'
and categoryname not like 'conventional hydro'
and categoryname not like 'wind'
and categoryname not like '%RPS'
and categoryname not like 'Other Steam'
and categoryname not like 'Synthetic Crude'
and categoryname not like 'CT Old Oil'
and year(commissionDate) < 2010
and year(retirementdate) > 2010;

-- switches v1 WECC load areas to v2 WECC load areas
update canmexgen set load_area = 'MEX_BAJA' where load_area = 'cfe';
update canmexgen set load_area = 'CAN_BC' where load_area = 'bctc';
update canmexgen set load_area = 'CAN_ALB' where load_area = 'aeso';

-- some generators strangly have min and max cap switched... this means that avg_mw > peak_mw
update canmexgen
set peak_mw = min_mw,
min_mw = peak_mw
where min_mw > peak_mw;

-- get the correct heat rates from the TEPPC_Generator_Categories table
update canmexgen, grid.TEPPC_Generator_Categories
set canmexgen.heatrate = grid.TEPPC_Generator_Categories.heatrate
where canmexgen.categoryname = grid.TEPPC_Generator_Categories.name;

-- get the fuels from the categoryname.. not ideal but not too bad either.
alter table canmexgen add column aer_fuel varchar(10);
update canmexgen set aer_fuel = 'GEO' where categoryname like 'Geothermal';
update canmexgen set aer_fuel = 'COL' where primemover like 'CO';
update canmexgen set aer_fuel = 'NG' where aer_fuel is null;

-- change a few primemovers to look like the US existing plants 'CT' to 'CC'
-- need to find if the Mexican Geothermal plants are 'ST' or 'BT'... put them as ST here.
update canmexgen set primemover = 'CC' where primemover like 'CT';
update canmexgen set primemover = 'ST' where primemover like 'CO';
update canmexgen set primemover = 'ST' where primemover like 'GE';


alter table canmexgen add column baseload int;
alter table canmexgen add column cogen int;

-- this sets the baseload and cogen values based on our regretably limited knowledge of especially the latter in Canada and Mexico now
update canmexgen set baseload = '1' where aer_fuel in ('GEO', 'COL');
update canmexgen set baseload = '0' where aer_fuel not in ('GEO', 'COL');
update canmexgen set cogen = '0';

-- the following fixes some zero and null values in the TEPPC dataset by digging into other TEPPC tables
-- the four coded out below we don't think are real, so we're not going to include them.
-- update canmexgen set peak_mw = '280' where name like 'CCGT%'; 
-- update canmexgen set avg_mw = '165' where name like 'CCGT%';
-- update canmexgen set peak_mw = '48' where name like 'G-L_CG%';
-- update canmexgen set avg_mw = '36.5' where name like 'G-L_CG%';
update canmexgen set peak_mw = '46' where name like 'PANCAN 9_2';
update canmexgen set avg_mw = (0.4005*peak_mw + peak_mw)/2 where name like 'PANCAN 9_2';
update canmexgen set peak_mw = '48' where name like 'NEXENG%';
update canmexgen set avg_mw = (0.48*peak_mw + peak_mw)/2 where name like 'NEXENG%';
update canmexgen set peak_mw = '48' where name like 'MEGENER2'; 
update canmexgen set avg_mw = (0.48*peak_mw + peak_mw)/2 where name like 'MEGENER2';
update canmexgen set peak_mw = '128' where name like 'VancIsland1'; 
update canmexgen set avg_mw = (0.5582*peak_mw + peak_mw)/2 where name like 'VancIsland1';
update canmexgen set avg_mw = (0.481*peak_mw + peak_mw)/2 where name like 'BAJA-SL';
update canmexgen set avg_mw = (0.481*peak_mw + peak_mw)/2 where name like 'PJX 3_1';
update canmexgen set avg_mw = (0.4175*peak_mw + peak_mw)/2 where name like 'LaRosit1';
update canmexgen set avg_mw = (0.4175*peak_mw + peak_mw)/2 where name like 'NovaJffr%';
update canmexgen set avg_mw = (0.3623*peak_mw + peak_mw)/2 where name like 'Wabamun4';


 
-- looked up cogen status of a bunch of canmex generators.  References on following lines.
-- couldn't find any info about Mexican cogen.
-- Alberta: http://www.energy.gov.ab.ca/Electricity/682.asp
-- some of the syncrudes are cogen as well, but we don't include them yet
-- BC Cogen that I could find
-- http://www.kelsonenergy.com/html_08/ke_can_island.html
-- other plants that are cogen from the name (GTC = gas turbine cogen)
update canmexgen
set cogen = 1,
baseload = 1
where name like 'Primros1'
or name like 'DowChmcl1'
or name like 'DowChmcl2'
or name like 'Rainbw4'
or name like 'JoffrCgnP'
or name like 'NovaJffr1A'
or name like 'NovaJffr1B'
or name like 'AirLiqd1'
or name like 'MedcnHt10'
or name like 'Cavalier1'
or name like 'Balzac1'
or name like 'Carslnd1'
or name like 'Carslnd2'
or name like 'Rainbw56'
or name like 'Redwater'
or name like 'MuskgRvr1'
or name like 'MuskgRvr2'
or name like 'ColdLake1'
or name like 'ColdLake2'
or name like 'ScotfordST'
or name like 'Mackay'
or name like 'Foster Creek1'
or name like 'Foster Creek2'
or name like 'SC_FirebagS2_1'
or name like 'SC_FirebagS3_1'
or name like 'SC_FirebagS3_2'
or name like 'IslndCgn'
or name like 'PANCAN%'
or name like 'NEXENG%'
or name like 'MEGEN%'
or name like 'VancIsland1'
or categoryname like 'gtc';

-- a few plants have made it through the process thusfar that probably aren't real (they have generic names)
-- these plants get deleted here
delete from canmexgen where peak_mw = 0;

-- the geothermal plants don't have a heat rate, so we just use the avergae US one, which is 21017.
update canmexgen set canmexgen.heatrate = 21.017 where aer_fuel like 'GEO' ;

update canmexgen set canmexgen.heatrate = 3.412 / 0.8 where cogen = 1;

delete from canmexgen where name like 'Gen @'; 

-- investment year of at least one BC plant is incorrect... see above reference
update canmexgen
set start_year = 2002
where name like 'IslndCgn';

insert into existing_plants_agg (load_area, plant_code, gentype, aer_fuel, peak_mw, avg_mw, heat_rate, start_year, baseload, cogen)
  select load_area, concat(replace(name, ' ',''), aer_fuel) as plant_code, primemover as gentype, aer_fuel, 
  peak_mw, avg_mw, heatrate, start_year, baseload, cogen 
  from canmexgen
    group by 1, 2, 3, 4;
    


------------------------------------------------------------
-- add costs, tabluated from the ReEDS input assumptions/ Black and Veatch for REFutures (12-02-09 update)
-- took the cost in 2000 (in $2007), as we don't have earlier data on plant costs.
-- took CoalOldScr costs, Gas ST = OGS = Oil Gas Steam 
-- set existing nuke lifetime to 60 years (was 30 in ReEDS) 
-- http://www.eia.doe.gov/oiaf/aeo/nuclear_power.html, but should consider making nukes pay for 40 year upgrades when we expand east.

-- also, Geothermal lifetimes were very short at 20 years in ReEDS.. they are about 45 years in actuality.  Couldn't quickly find a better reference than below.
-- http://energyexperts.org/EnergySolutionsDatabase/ResourceDetail.aspx?id=2354

-- note: we assume that cogen plants have 3/4 of the capital cost of a pure-electric plant
-- (to reflect shared infrastructure for cogen), but the same operating costs.
-- TODO: find better costs for cogen plants
-- all units in MW, MWh and MBtu terms
drop table if exists epcosts;
create table epcosts (
  gentype char(2),
  aer_fuel char(3),
  overnight_cost double,
  fixed_o_m double,
  variable_o_m double,
  fuel varchar(20),
  forced_outage_rate double,
  scheduled_outage_rate double,
  max_age double,
  index (gentype, aer_fuel)
  );

insert into epcosts values
	('BT','GEO',3397000,261269,0,'Geothermal',0.075,0.0241,45),
	('CC','NG',955000,11322,3.35,'Gas',0.04,0.06,30),
	('GT','NG',652000,11322,3.35,'Gas',0.03,0.05,30),
	('IC','NG',652000,30000,1,'Gas',0.03,0.05,30),
	('ST','COL',1322000,25703,3.73,'Coal',0.06,0.10,60),
	('ST','GEO',3397000,261269,0,'Geothermal',0.075,0.0241,45),
	('ST','NG',435000,27730,3.47,'Gas',0.10,0.026, 45),
	('ST','NUC',3319000,90034,0.49,'Nuclear',0.04,0.06,60);


update existing_plants_agg e join epcosts c using (gentype, aer_fuel)
  set e.overnight_cost=if(cogen, 0.75, 1)*c.overnight_cost,
    e.fixed_o_m=c.fixed_o_m,
    e.variable_o_m = c.variable_o_m,
    e.aer_fuel = c.aer_fuel,
    e.forced_outage_rate = c.forced_outage_rate,
    e.scheduled_outage_rate = c.scheduled_outage_rate,
    e.max_age = c.max_age;
-- fix a few that have higher production than theoretically possible
update existing_plants_agg
  set peak_mw = avg_mw / (1-forced_outage_rate) where avg_mw > peak_mw * (1-forced_outage_rate);


ALTER TABLE existing_plants_agg MODIFY COLUMN aer_fuel Varchar(20);

update existing_plants_agg set aer_fuel = 'Gas' where aer_fuel like 'NG';
update existing_plants_agg set aer_fuel = 'Uranium' where aer_fuel like 'NUC';
update existing_plants_agg set aer_fuel = 'Coal' where aer_fuel like 'COL';
update existing_plants_agg set aer_fuel = 'Geothermal' where aer_fuel like 'GEO';

update existing_plants_agg set technology = concat(aer_fuel, '_', gentype);

-- Update technology names - make these above in the future

update existing_plants_agg set technology = 'Coal_Steam_Turbine_EP' where technology = 'Coal_ST';
update existing_plants_agg set technology = 'Geothermal_EP' where technology in ('Geothermal_ST', 'Geothermal_BT');
update existing_plants_agg set technology = 'Gas_Combustion_Turbine_EP' where technology in ('Gas_GT', 'Gas_IC');
update existing_plants_agg set technology = 'Gas_Steam_Turbine_EP' where technology = 'Gas_ST';
update existing_plants_agg set technology = 'CCGT_EP' where technology = 'Gas_CC';
update existing_plants_agg set technology = 'Nuclear_EP' where technology = 'Uranium_ST';
update existing_plants_agg set technology = replace(technology, "_EP", "_Cogen_EP") where cogen;

-- add in Wind existing plants
-- existing windfarms added here
-- costs from from the ReEDS input assumptions/ Black and Veatch for REFutures (12-02-09 update)
-- max age from base input spreadsheet for switch
-- fixed O+M,forced_outage_rate are from new wind
insert into existing_plants_agg
		(load_area,
		plant_code,
		gentype,
		aer_fuel,
		peak_mw,
		avg_mw,
		heat_rate,
		start_year,
		baseload,
		cogen,
		overnight_cost,
		fixed_o_m,
		variable_o_m,
		forced_outage_rate,
		scheduled_outage_rate,
		max_age,
		intermittent,
		technology)
select 	load_area,
		concat('Wind_EP', '_', load_area, '_', 3tier.windfarms_existing_info_wecc.windfarm_existing_id) as plant_code,
		'Wind' as gentype,
		'Wind' as aer_fuel,
		capacity_mw as peak_mw,
		avg(cap_factor) * capacity_mw as avg_mw,
		0 as heat_rate,
		year_online as start_year,
		0 as baseload,
		0 as cogen,
		1724000 as overnight_cost,
		57790 as fixed_o_m,
		0 as variable_o_m,
		0.015 as forced_outage_rate,
		0.003 as scheduled_outage_rate,
		30 as max_age,
		1 as intermittent,
		'Wind_EP' as technology
from 	3tier.windfarms_existing_info_wecc join 
		3tier.windfarms_existing_cap_factor using(windfarm_existing_id)
group by 3tier.windfarms_existing_info_wecc.windfarm_existing_id
;



-- HYDRO----------

-- a few plants have different summer and winter capacities listed in grid.eia860gen07_US
-- but these are likely due to generator outages/repairs rather than any operational constraint
-- as these dams do generate electricity in summer and winter...
-- if the two capacities are different then this sets the capacity to the greater of the two
drop table if exists hydro_plantcap;
create table hydro_plantcap
  	select 	g.plntcode,
  			g.plntname,
  			primemover,
  			p.load_area,
    		sum( if( summcap > wintcap, summcap, wintcap ) ) as capacity_mw
 		from grid.eia860gen07_US g join generator_info.eia860plant07_postgresql p using (plntcode)
  		where primemover in ("HY", "PS")
  		and status like 'OP'
  		and p.load_area not like ''
  		group by 1, 2, 3, 4;
alter table hydro_plantcap add primary key (plntcode, primemover);

-- for now, we assume:
-- maximum flow is equal to the plant capacity (summer or winter, ignoring discrepancy from nameplate)
-- minimum flow is negative of the pumped storage capacity, if applicable, or 0.25 * average flow for simple hydro
-- TODO: find better estimates of minimum flow, e.g., by looking through remarks in the USGS datasheets, or looking
--   at the lowest daily average flow in each month.
-- daily average is equal to net historical production of power
-- look here for a good program that can download water flow data: http://www.hec.usace.army.mil/software/hec-dss/hecdssvue-download.htm
-- TODO: find a better estimate of pumping capacity, rather than just the negative of the PS generating capacity
-- TODO: estimate net daily energy balance in the reservoir, not via netgen. i.e., avg_flow should be based on the
--   total flow of water (and its potential energy), not the net power generation, which includes losses from 
--   inefficiency on both the generation and storage sides 
--   (we ignore this for now, which is OK if net flow and net gen are both much closer to zero than max flow)
--   This can be done by fitting a linear model of water flow and efficiency to the eia energy consumption and net_gen
--   data and the USGS monthly water flow data, for pumped storage facilities. This model may be improved by looking up
--   the head height for each dam, to link water flows directly to power.

-- NOTE: Jimmy converted 'flow' to 'output' and 'input' below, as right now all data comes from EIA 906 data, which is in terms of MWh instead of water units
-- as said above, it would be much better to get USGS data on dams and water flows to make these quantities in water stocks and flows

drop table if exists hydro_gen;
create table hydro_gen(
  plntcode int,
  plntname varchar(50),
  primemover char(2),
  year year,
  month tinyint,
  netgen_mwh double,
  input_electricity_mwh double,
  INDEX pm (plntcode, primemover),
  INDEX ym (year, month)
);

insert into hydro_gen select plntcode, plntname, primemover, year, 1, netgen_jan, elec_quantity_jan from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year between 2004 and 2006;
insert into hydro_gen select plntcode, plntname, primemover, year, 2, netgen_feb, elec_quantity_feb from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year between 2004 and 2006;
insert into hydro_gen select plntcode, plntname, primemover, year, 3, netgen_mar, elec_quantity_mar from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year between 2004 and 2006;
insert into hydro_gen select plntcode, plntname, primemover, year, 4, netgen_apr, elec_quantity_apr from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year between 2004 and 2006;
insert into hydro_gen select plntcode, plntname, primemover, year, 5, netgen_may, elec_quantity_may from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year between 2004 and 2006;
insert into hydro_gen select plntcode, plntname, primemover, year, 6, netgen_jun, elec_quantity_jun from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year between 2004 and 2006;
insert into hydro_gen select plntcode, plntname, primemover, year, 7, netgen_jul, elec_quantity_jul from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year between 2004 and 2006;
insert into hydro_gen select plntcode, plntname, primemover, year, 8, netgen_aug, elec_quantity_aug from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year between 2004 and 2006;
insert into hydro_gen select plntcode, plntname, primemover, year, 9, netgen_sep, elec_quantity_sep from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year between 2004 and 2006;
insert into hydro_gen select plntcode, plntname, primemover, year, 10, netgen_oct, elec_quantity_oct from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year between 2004 and 2006;
insert into hydro_gen select plntcode, plntname, primemover, year, 11, netgen_nov, elec_quantity_nov from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year between 2004 and 2006;
insert into hydro_gen select plntcode, plntname, primemover, year, 12, netgen_dec, elec_quantity_dec from grid.eia906_04_to_07_us where primemover in ("PS", "HY") and year between 2004 and 2006;

-- as we're not going to use the input_electricity_mwh for non-pumped hydro, delete it here
-- (could do in an if clause on elec_quanity_(month) above, but this is more simple
update hydro_gen set input_electricity_mwh = 0 where primemover = 'HY';

-- to determine the net stream flow of pumped hydro projects,
-- three approximations must be made, as the EIA does not give enough data to determine this number directly
-- first, that the total stock of water doesn't change from year to year, i.e. stockH20(Jan2004)=stockH20(Jan2005) and so on
-- this could be verified/modified with USGS water data.
-- second, that the efficiency of pumped hydro projects is known
-- Black and Veach gives this number at 87%, but everywhere else says lower...
-- http://www.electricitystorage.org/site/technologies/pumped_hydro/ says 70-85%.. we'll assume 80%
-- third, that the release profile over a year for pumped hydro is similar to that of nonpumped hydro plants in the same load area

-- using the above assumptions, over a year,
-- stream_flow_mwh = sum( netgen_mwh + input_electricity_mwh * ( 1 - pumped_hydro_efficiency ) )
-- the last term represents the pumping losses

drop table if exists hydro_pumped_yearly_stream_flow;
create table hydro_pumped_yearly_stream_flow as
select	plntcode,
		load_area,
		year,
		sum( netgen_mwh + input_electricity_mwh * ( 1 - 0.80 ) ) as avg_yearly_stream_flow_mwh
from hydro_gen join hydro_plantcap using (plntcode, primemover)
where hydro_gen.primemover = 'PS'
group by 1,2,3;
	
-- some of these values come out a bit negative, meaning that either the total amount of water in the resevoir has changed or
-- the actual efficiency is less than the assumed efficiency, or a combination of both
-- we'll assume that it's predominantly efficiency, so zero out these negative values
update hydro_pumped_yearly_stream_flow set avg_yearly_stream_flow_mwh = 0 where avg_yearly_stream_flow_mwh < 0;


-- first do on a plant level, then aggregate below
-- note: the fancy date math just figures out how many days there are in each month
-- also, the avg_output for pumped hydro plants will be updated below
drop table if exists hydro_monthly_limits;
create table hydro_monthly_limits
  select 	hydro_plantcap.load_area,
			hydro_plantcap.plntcode,
			hydro_plantcap.plntname,
			hydro_plantcap.primemover,
			year,
    		month,
    		capacity_mw,
		    sum(netgen_mwh / 
      			(24 * datediff(
        			date_add(concat(year, "-", month, "-01"), interval 1 month), concat(year, "-", month, "-01")
      				))) as avg_output
    from hydro_gen join hydro_plantcap using (plntcode, primemover)
    group by 1, 2, 3, 4, 5, 6, 7;

alter table hydro_monthly_limits add index ym (year, month);

-- drop the sites that have too few months of data (i.e., started or stopped running in this period)
-- should check how many plants this is
-- only lose about 30MW of capacity... it's almost all 1-3 MW dams... could fill these in later.
drop temporary table if exists toofew;
create temporary table toofew
select plntcode, primemover, count(*) as n from hydro_monthly_limits group by 1 having n < 36;
delete l.* from hydro_monthly_limits l join toofew f using (plntcode, primemover);


-- make a table of hydro sites with an auto-increment unique identifier
drop table if exists hydro_sites;
CREATE TABLE IF NOT EXISTS hydro_sites (
  hydro_id mediumint unsigned PRIMARY KEY AUTO_INCREMENT,
  load_area varchar(11) default NULL,
  primemover char(2),
  UNIQUE (load_area, primemover)
);
insert into hydro_sites ( load_area, primemover )
	SELECT 	distinct load_area,
			primemover
		from hydro_monthly_limits;

drop table if exists hydro_monthly_limits_agg;
CREATE TABLE IF NOT EXISTS hydro_monthly_limits_agg (
  hydro_id mediumint unsigned,
  primemover char(2) NOT NULL,
  load_area varchar(11) NOT NULL,	 
  year year(4) NOT NULL,
  month tinyint(4) NOT NULL,
  capacity_mw double NOT NULL,
  avg_output double NOT NULL,
  FOREIGN KEY (hydro_id) REFERENCES hydro_sites(hydro_id)  
);

insert into hydro_monthly_limits_agg ( hydro_id, primemover, load_area, year, month, capacity_mw, avg_output )
	SELECT 	hydro_id, 
			primemover,
			load_area,
			year,
			month,
			sum(capacity_mw) as capacity_mw,
			sum(avg_output) as avg_output 
		from hydro_monthly_limits join hydro_sites using (load_area, primemover)
		group by 1,2,3,4,5;


-- now aggregate and add Canadian Hydro...
-- TODO: buy and download provience level montly Canadian Hydro data from CANSIM

-- Canadian Hydro
-- takes output constraints from Washington state hydro
-- becasue we don't yet have data on Canadian hydro output and Washington is the closest to British Columbia,
-- where almost all the WECC Canadian hydro resides
-- uses the total capacity for each province in a hydro aggregate

-- doesn't appear that these two provinces have any pumped hydro from the ventyx database
-- this POSTGRESQL query gets you the capacities for the two provinces
-- select abbrev, sum(cap_mw) from ventyx_e_units_point,
-- ventyx_states_region
-- where intersects(ventyx_e_units_point.the_geom, ventyx_states_region.the_geom) and abbrev in ('BC', 'AB')
-- and pm_group like 'Hydraulic Turbine'
-- and statustype like 'Operating'
-- group by 1;

insert into hydro_sites ( load_area, primemover ) VALUES ( 'CAN_BC', 'HY' ), ('CAN_ALB', 'HY');

insert into hydro_monthly_limits_agg ( hydro_id, primemover, load_area, year, month, capacity_mw, avg_output )
	SELECT 	(select hydro_id from hydro_sites WHERE primemover = 'HY' and hydro_sites.load_area = 'CAN_BC'), 
			'HY',
			'CAN_BC',
			year,
			month,
			11870 as capacity_mw,
			avg_output_fraction * 11870 as avg_output
	FROM
		(SELECT year,
				month,
				sum(avg_output)/sum(capacity_mw) as avg_output_fraction
		FROM hydro_monthly_limits
		where load_area like 'WA%'
		and primemover like 'HY'
		group by year, month) as washington_hydro_output_table;
insert into hydro_monthly_limits_agg ( hydro_id, primemover, load_area, year, month, capacity_mw, avg_output )
	SELECT 	(select hydro_id from hydro_sites WHERE primemover = 'HY' and hydro_sites.load_area = 'CAN_ALB'), 
			'HY',
			'CAN_ALB',
			year,
			month,
			911 as capacity_mw,
			avg_output_fraction * 911 as avg_output
	FROM
		(SELECT year,
				month,
				sum(avg_output)/sum(capacity_mw) as avg_output_fraction
		FROM hydro_monthly_limits
		where load_area like 'WA%'
		and primemover like 'HY'
		group by year, month) as washington_hydro_output_table
;


-- now update the avg_output for pumped hydro
-- using the generation profile from nonpumped hydro in the same load area for each month

-- aggregate pumped yearly flows to a load area basis and parse out the yearly MWh flows to each month
update 	hydro_monthly_limits_agg,
		(select load_area,
				year,
				sum(avg_yearly_stream_flow_mwh) as pumped_yearly_stream_flow_mwh
			from hydro_pumped_yearly_stream_flow
			group by 1,2
		) as pumped_yearly_stream_flow_table,
		(select	agg.load_area,
				month,
				agg.year,
				avg_output / yearly_output_nonpumped as nonpumped_monthly_profile
			from 	hydro_monthly_limits_agg agg,
					(select load_area,
							year,
							sum(avg_output) as yearly_output_nonpumped
						from hydro_monthly_limits_agg
						where primemover = 'HY'
						group by 1,2
					) as yearly_output_nonpumped_table
			where 	agg.load_area = yearly_output_nonpumped_table.load_area
			and		agg.year = yearly_output_nonpumped_table.year
			and		agg.primemover = 'HY'
		) as nonpumped_monthly_profile_table
set 	hydro_monthly_limits_agg.avg_output = ( nonpumped_monthly_profile * pumped_yearly_stream_flow_mwh )
				/ 
 				(24 * datediff(
        			date_add(concat(hydro_monthly_limits_agg.year, "-", hydro_monthly_limits_agg.month, "-01"), interval 1 month),
        				concat(hydro_monthly_limits_agg.year, "-", hydro_monthly_limits_agg.month, "-01")
      				))
where 	hydro_monthly_limits_agg.primemover = 'PS'
and 	hydro_monthly_limits_agg.load_area  = nonpumped_monthly_profile_table.load_area
and 	hydro_monthly_limits_agg.month		= nonpumped_monthly_profile_table.month
and 	hydro_monthly_limits_agg.year 		= nonpumped_monthly_profile_table.year
and 	hydro_monthly_limits_agg.load_area 	= pumped_yearly_stream_flow_table.load_area
and 	hydro_monthly_limits_agg.year 		= pumped_yearly_stream_flow_table.year;


-- also, any dam that is ouputing past capacity is scaled back to it's rated capacity.
-- this is generally less than 10% and for only a handful of dam-months
update hydro_monthly_limits_agg set avg_output = capacity_mw where avg_output > capacity_mw;




-- drop some temp tables... kept around above for debugging
drop table if exists hydro_plantcap;
drop table if exists hydro_gen;
drop table if exists hydro_pumped_yearly_stream_flow;
drop table if exists hydro_monthly_limits;


