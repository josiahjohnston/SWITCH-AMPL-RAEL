-- build a table of data on existing plants
-- Assumptions:
-- eia_sector = 3, 5, or 7 for cogen plants; others are electricity-only
-- dispatchable plants are eia_sector 1, 2, 6 with the main fuel = "NG" (gas)
-- baseload plants are all others, if fuel is "COL", "GEO", "NUC"

-- efficiency of plants is based on net_gen_mwh and elec_fuel_mbtu
-- efficiency and fuel are based on the predominant fuel and the sum of all primemovers at each plant


-- first, get data (aggregated to plant-primemover level) from eia906 database
-- this includes the primary fuel, heat rate when using the primary fuel, and total net_gen_mwh for all fuels

-- gets all of the plants in wecc, as assigned in grid.eia860gen07_us from postgresql
-- we appear to lose one very small (net_generation__mwh=1077) NG plant (plntcode = 56508) because it doesn't appear in grid.eia860gen07_us... don't think this should be a problem.
-- note: does not remove retired or out of service generators yet.  This will be done when summing up the generation and fuel consumption because some plants have parts that are operational and some that aren't.

--########################

use generator_info;

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
create table existing_plants (
	plntname varchar(64) NOT NULL,
	plntcode int NOT NULL,
	primemover varchar(4) NOT NULL,
	fuel varchar(20)  NOT NULL,
	net_gen_mwh float,
	fuel_consumption float,
	eia_sector_number int,
	cogen boolean,
	load_area varchar(11),
	nameplate float,
	peak_mw float,
	start_year year,
	baseload boolean,
	PRIMARY KEY (plntcode, primemover, fuel, eia_sector_number, cogen, start_year, nameplate)
	);
	
	
insert into existing_plants (plntname, plntcode, primemover, fuel, net_gen_mwh, fuel_consumption, eia_sector_number,
							cogen, load_area, nameplate, peak_mw, start_year)
select 	eia860gen07.plntname,
		maxgen.plntcode,
		maxgen.primemover,
		maxgen.aer_fuel_type_code as fuel,
		maxgen.net_generation_megawatthours as net_gen_mwh,
		maxgen.elec_fuel_consumption_mmbtus as fuel_consumption,
		maxgen.eia_sector_number,
		if(maxgen.cogen like 'Y', 1, 0) as cogen,
		maxgen.load_area,
		sum(eia860gen07.nameplate) as nameplate,
		sum((eia860gen07.Summer_Capacity+eia860gen07.Winter_Capacity)/2) as peak_mw,
--		eia860gen07.Operating_Year as start_year
		max(eia860gen07.Operating_Year) as start_year
from maxgen, eia860gen07
where maxgen.plntcode = eia860gen07.plntcode
and (maxgen.primemover = eia860gen07.primemover
	or (maxgen.primemover like 'CC' and eia860gen07.primemover in ('CA', 'CT', 'CS') and maxgen.plntcode = eia860gen07.plntcode))
group by eia860gen07.plntcode, eia860gen07.primemover, fuel, cogen, eia_sector_number;
-- group by eia860gen07.plntcode, eia860gen07.primemover, eia860gen07.Operating_Year;

-- fill in baseload (as described at top of file)
update existing_plants set baseload = if(eia_sector_number in (1, 2, 6) and fuel="NG", 0, 1);


-- get heat rate for each plant-primemover-fuel-year combination
alter table existing_plants add column heat_rate float;
update	existing_plants e, 
		(SELECT plntcode,
 				primemover,
 				fuel,
 				start_year,
 				sum(fuel_consumption)/sum(net_gen_mwh) as heat_rate
 			FROM existing_plants
 			group by plntcode, primemover, fuel, start_year) as h 
set e.heat_rate = h.heat_rate
where e.plntcode = h.plntcode
and e.primemover = h.primemover
and e.fuel = h.fuel
and e.start_year = h.start_year;

-- two GTs have heat_rates of ~1000, not the ~10000 that they should have..
-- I'm assuming that this is because someone (not me... I checked) messed up a decimal point somewhere
-- I therefore multiply their heat rates by 10, which returns a normal heat rate for GTs
update existing_plants set heat_rate = 10 * heat_rate where heat_rate < 2;


--select mn.plntcode, mn.primemover, mxyr, mnyr, mxyr- mnyr as mxdiff from
--(select plntcode, primemover, max(Operating_Year) as mxyr from 
--  (select plntcode, primemover, count(*) as cnt from existing_plants group by 1,2 order by cnt desc) g join 
--  existing_plants using (plntcode, primemover) group by 1,2) as mx,
--(select plntcode, primemover, min(Operating_Year) as mnyr from 
--  (select plntcode, primemover, count(*) as cnt from existing_plants group by 1,2 order by cnt desc) g join 
--  existing_plants using (plntcode, primemover) group by 1,2) as mn
--where mn.plntcode = mx.plntcode and mn.primemover = mx.primemover
--and mxyr- mnyr > 0
--order by mxdiff desc
--
-- --------------------------------------------------------------
-- CANADA and MEXICO

-- for Canada, should use 'Electric Power Generating Stations Annual'
-- http://www.statcan.gc.ca/cgi-bin/imdb/p2SV.pl?Function=getSurvey&SurvId=2193&SurvVer=0&InstaId=14395&InstaVer=6&SDDS=2193&lang=en&db=IMDB&adm=8&dis=2

-- now we bring in nonhydro Canadian and Mexican generators from the TEPPC data.

-- selects out generators that we want.
-- we took out SynCrude plants... they are a few hundred MW of generation in Alberta but we don't have time to deal with them at the moment... should be put in at some point
-- some generators strangly have min and max cap switched... this means that avg_mw > peak_mw
drop table if exists canmexgen;
create table canmexgen
SELECT 	name,
		area as load_area,
		categoryname,
		upper(left(categoryname, 2)) as primemover,
		year(commissiondate) as start_year,
		if(mincap > maxcap, mincap, maxcap) as peak_mw,
		heatrate
FROM grid.TEPPC_Generators
where area in ('cfe', 'bctc', 'aeso')
and categoryname not in ('canceled', 'conventional hydro', 'wind', 'Other Steam', 'Synthetic Crude', 'CT Old Oil')
and categoryname not like '%RPS'
and categoryname not like '%Future'
and year(commissionDate) < 2010
and year(retirementdate) > 2010
and peak_mw > 0
order by categoryname

-- switches v1 WECC load areas to v2 WECC load areas
update canmexgen set load_area = 'MEX_BAJA' where load_area = 'cfe';
update canmexgen set load_area = 'CAN_BC' where load_area = 'bctc';
update canmexgen set load_area = 'CAN_ALB' where load_area = 'aeso';

-- get the correct heat rates from the TEPPC_Generator_Categories table
update canmexgen, grid.TEPPC_Generator_Categories
set canmexgen.heatrate = grid.TEPPC_Generator_Categories.heatrate
where canmexgen.categoryname = grid.TEPPC_Generator_Categories.name;

-- get fuels
alter table canmexgen add column fuel varchar(10);
update canmexgen set fuel = 'GEO' where categoryname like 'Geothermal';
update canmexgen set fuel = 'COL' where primemover like 'CO';
update canmexgen set fuel = 'NG' where fuel is null;

-- change a few primemovers to look like the US existing plants 'CT' to 'CC'
-- need to find if the Mexican Geothermal plants are 'ST' or 'BT'... put them as ST here.
update canmexgen set primemover = 'CC' where categoryname like 'CC%';
update canmexgen set primemover = 'ST' where primemover like 'CO';
update canmexgen set primemover = 'ST' where primemover like 'GE';
update canmexgen set primemover = 'GT' where primemover like 'CT';


alter table canmexgen add column baseload boolean;
alter table canmexgen add column cogen boolean default 0;

-- this sets the baseload and cogen values based on our regretably limited knowledge of especially the latter in Canada and Mexico now
update canmexgen set baseload = '1' where fuel in ('GEO', 'COL');
update canmexgen set baseload = '0' where fuel not in ('GEO', 'COL');

-- the following fixes some zero and null values in the TEPPC dataset by digging into other TEPPC tables
-- the two coded out below we don't think are real, so we're not going to include them.
-- update canmexgen set peak_mw = '280' where name like 'CCGT%'; 
-- update canmexgen set peak_mw = '48' where name like 'G-L_CG%';
update canmexgen set peak_mw = '46' where name like 'PANCAN 9_2';
update canmexgen set peak_mw = '48' where name like 'NEXENG%';
update canmexgen set peak_mw = '48' where name like 'MEGENER2'; 
update canmexgen set peak_mw = '128' where name like 'VancIsland1'; 
 
-- looked up cogen status of a bunch of canmex generators.  References on following lines.
-- couldn't find any info about Mexican cogen.
-- Alberta: http://www.energy.gov.ab.ca/Electricity/682.asp
-- some of the syncrudes are cogen as well, but we don't include them yet
-- BC Cogen that I could find
-- http://www.kelsonenergy.com/html_08/ke_can_island.html
-- other plants that are cogen from the name (GTC = gas turbine cogen)

-- also here is very nice
-- http://www2.cieedac.sfu.ca/media/publications/Cogeneration%20Report%202010%20Final.pdf
update canmexgen
set cogen = 1,
baseload = 1
where name in
(	'Primros1', 'DowChmcl1', 'DowChmcl2', 'Rainbw4', 'JoffrCgnP',
	'NovaJffr1A', 'NovaJffr1B', 'AirLiqd1', 'MedcnHt10', 'Cavalier1',
	'Balzac1', 'Carslnd1', 'Carslnd2', 'Rainbw56', 'Redwater',
	'MuskgRvr1', 'MuskgRvr2', 'ColdLake1', 'ColdLake2', 'ScotfordST',
	'Mackay', 'Foster Creek1', 'Foster Creek2', 'SC_FirebagS2_1', 'SC_FirebagS3_1',
	'SC_FirebagS3_2', 'IslndCgn', 'VancIsland1', 'WstCstn1', 'WstCstn2',
	'Cancarb1', 'Redwater', 'BrrrdTh5', 'Weldwood1', 'Weldwood2' )
or categoryname like 'gtc'
or name like 'PANCAN%',
or name like 'NEXENG%',
or name like 'MEGEN%'
;

-- investment year of at least one BC plant is incorrect... see above reference
update canmexgen set start_year = 2002 where name = 'IslndCgn';

-- http://www.intergen.com/global/larosita.php... start year 2003
update canmexgen set start_year = 2003 where name = 'LaRosit1'

-- a few plants have made it through the process thusfar that probably aren't real (they have generic names)
-- these plants get deleted here
delete from canmexgen where name = 'Gen @'; 

-- the geothermal and cogen plants don't have heat rates,
-- so we just use the average US ones for each primemover-fuel-cogen combination.
-- if the average US cogen heat rate comes in higher than the heat rate listed in the TEPPC database,
-- take the TEPPC heat rate instead
update 	canmexgen,
		(select primemover,
				fuel,
				cogen,
				avg(heat_rate) as avg_heat_rate
			from existing_plants_agg
			group by 1,2,3
		) as avg_heat_rate_table
set heatrate =  if(heatrate = 0 or heatrate = null, avg_heat_rate,
					if(heatrate > avg_heat_rate, avg_heat_rate, heatrate)
				)
where 	canmexgen.primemover = avg_heat_rate_table.primemover
and		canmexgen.fuel = avg_heat_rate_table.fuel
and		canmexgen.cogen = avg_heat_rate_table.cogen
and		(canmexgen.cogen = 1 or canmexgen.fuel = 'GEO')
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
  			if(invsyear < 1900, 1900, invsyear) as start_year,
  			p.load_area,
    		sum( if( summcap > wintcap, summcap, wintcap ) ) as capacity_mw
 		from grid.eia860gen07_US g join generator_info.eia860plant07_postgresql p using (plntcode)
  		where primemover in ("HY", "PS")
  		and status like 'OP'
  		and p.load_area not like ''
  		group by 1, 2, 3, 4, 5;
alter table hydro_plantcap add primary key (plntcode, primemover, start_year);

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
  netgen_mwh float,
  input_electricity_mwh float default 0,
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

-- a few nonpumped plants have a slightly negative netgen_mwh - we zero this out here as it's not significant and makes things a lot easier downstream (heh)
update hydro_gen set netgen_mwh = 0 where primemover = 'HY' and netgen_mwh < 0;

-- as we're not going to use the input_electricity_mwh for non-pumped hydro, delete it here
-- (could do in an if clause on elec_quanity_(month) above, but this is more simple
update hydro_gen set input_electricity_mwh = 0 where primemover = 'HY';


drop table if exists hydro_monthly_limits;
create table hydro_monthly_limits (
	load_area varchar(11),
	eia_id int default 0,
	canada_plant_code int default 0,
	plant_name varchar(64),
	primemover varchar(4),
	start_year year,
	year year,
	month tinyint,
	capacity_mw float,
	avg_output float,
	primary key (eia_id, canada_plant_code, primemover, start_year, year, month),
	index (year, month)
);

-- note: the fancy date math just figures out how many days there are in each month
-- also, the avg_output for pumped hydro plants will be updated below
-- the hydro output is by plant-primemover from eia906, but here we also have start_year to differentiate different turbines
-- so we apportion the turbine output proportionally to generator capacity
insert into hydro_monthly_limits (load_area, eia_id, plant_name, primemover, start_year, year, month, capacity_mw, avg_output)
  select 	hydro_plantcap.load_area,
			hydro_plantcap.plntcode,
			replace(hydro_plantcap.plntname, " ", "_"),
			hydro_plantcap.primemover,
			hydro_plantcap.start_year,
			year,
    		month,
    		capacity_mw,
		    ( capacity_mw / total_plant_primemover_cap_mw ) * sum(netgen_mwh) / 
      			(24 * datediff(
        			date_add(concat(year, "-", month, "-01"), interval 1 month), concat(year, "-", month, "-01")
      				)) as avg_output
    from (select	plntcode,
    				primemover,
    				sum(capacity_mw) as total_plant_primemover_cap_mw
    		from hydro_plantcap
    		group by 1,2 ) as total_cap_table
    		join hydro_plantcap using (plntcode, primemover)
    		join hydro_gen using (plntcode, primemover)
    group by 1, 2, 3, 4, 5, 6, 7, 8;

-- drop the sites that have too few months of data (i.e., started or stopped running in this period)
-- should check how many plants this is
-- only lose about 30MW of capacity... it's almost all 1-3 MW dams... could fill these in later.
drop temporary table if exists toofew;
create temporary table toofew
select eia_id, primemover, start_year, count(*) as n from hydro_monthly_limits group by 1, 2, 3 having n < 36;
delete l.* from hydro_monthly_limits l join toofew f using (eia_id, primemover, start_year);

-- also, any dam that is ouputing past capacity is scaled back to it's rated capacity.
-- this is generally less than 10% and for only a handful of dam-months
update hydro_monthly_limits set avg_output = capacity_mw where avg_output > capacity_mw;


-- PUMPED HYDRO

-- to determine the net stream flow of pumped hydro projects,
-- three approximations must be made, as the EIA does not give enough data to determine this number directly
-- first, that the total stock of water doesn't change from year to year, i.e. stockH20(Jan2004)=stockH20(Jan2005) and so on
-- this could be verified/modified with USGS water data.
-- second, that the efficiency of pumped hydro projects is known
-- 74%, from Samir Succar and Robert H. Williams: Compressed Air Energy Storage: Theory, Resources, And Applications For Wind Power, p. 39
-- third, that the release profile over a year for pumped hydro is similar to that of nonpumped hydro plants in the same load area

-- using the above assumptions, over a year,
-- stream_flow_mwh = sum( netgen_mwh + input_electricity_mwh * ( 1 - pumped_hydro_efficiency ) )
-- the last term represents the pumping losses

drop table if exists pumped_hydro_yearly_stream_flow;
create table pumped_hydro_yearly_stream_flow as
	select	plntcode as eia_id,
			start_year,
			load_area,
			year,
			(capacity_mw / total_plant_primemover_cap_mw )
					* sum( netgen_mwh + input_electricity_mwh * ( 1 - 0.74 ) ) as pumped_yearly_stream_flow_mwh
		from hydro_gen
		join hydro_plantcap using (plntcode, primemover)
		join (select	plntcode,
    					primemover,
    					sum(capacity_mw) as total_plant_primemover_cap_mw
    			from hydro_plantcap
    			group by 1,2 ) as total_cap_table using (plntcode, primemover)
		where hydro_gen.primemover = 'PS'
		group by 1,2,3,4;
	
-- some of these values come out a bit negative, meaning that either the total amount of water in the resevoir has changed or
-- the actual efficiency is less than the assumed efficiency, or a combination of both
-- we'll assume that it's predominantly efficiency, so zero out these negative values
update pumped_hydro_yearly_stream_flow set pumped_yearly_stream_flow_mwh = 0 where pumped_yearly_stream_flow_mwh < 0;


-- now update the avg_output for pumped hydro
-- using the generation profile from nonpumped hydro in the same load area for each month

-- aggregate pumped yearly flows to a load area basis and parse out the yearly MWh flows to each month
update 	hydro_monthly_limits,
		pumped_hydro_yearly_stream_flow,
		(select	load_area,
				year,
				month,
				sum(avg_output) / yearly_output_nonpumped as nonpumped_monthly_profile
			from 	(select load_area,
							year,
							sum(avg_output) as yearly_output_nonpumped
						from hydro_monthly_limits
						where primemover = 'HY'
						group by 1,2
					) as yearly_output_nonpumped_table
					join hydro_monthly_limits using (load_area, year)
			where 	primemover = 'HY'
			group by 1,2,3
		) as nonpumped_monthly_profile_table
set 	hydro_monthly_limits.avg_output = ( nonpumped_monthly_profile * pumped_yearly_stream_flow_mwh )
				/ 
 				(24 * datediff(
        			date_add(concat(hydro_monthly_limits.year, "-", hydro_monthly_limits.month, "-01"), interval 1 month),
        				concat(hydro_monthly_limits.year, "-", hydro_monthly_limits.month, "-01")
      				))
where 	hydro_monthly_limits.primemover = 'PS'
and 	hydro_monthly_limits.load_area	= nonpumped_monthly_profile_table.load_area
and 	hydro_monthly_limits.year 		= nonpumped_monthly_profile_table.year
and 	hydro_monthly_limits.month		= nonpumped_monthly_profile_table.month
and 	hydro_monthly_limits.start_year	= pumped_hydro_yearly_stream_flow.start_year
and 	hydro_monthly_limits.load_area	= pumped_hydro_yearly_stream_flow.load_area
and 	hydro_monthly_limits.year 		= pumped_hydro_yearly_stream_flow.year
;

update hydro_monthly_limits set avg_output = capacity_mw where avg_output > capacity_mw;


-- ------------------------------
-- CANADIAN HYDRO


-- doesn't appear that these two provinces have any pumped hydro from the ventyx database
-- this POSTGRESQL query gets you the capacities for the two provinces
-- select abbrev, sum(cap_mw) from ventyx_e_units_point,
-- ventyx_states_region
-- where intersects(ventyx_e_units_point.the_geom, ventyx_states_region.the_geom) and abbrev in ('BC', 'AB')
-- and pm_group like 'Hydraulic Turbine'
-- and statustype like 'Operating'
-- group by 1;


-- postgresql query to print out BC and Alberta hydro sites
-- copy
-- (select abbrev, ventyx_e_units_point.*, ventyx_e_plants_point.* from ventyx_states_region, ventyx_e_units_point join ventyx_e_plants_point using (plant_id)
-- where intersects(ventyx_states_region.the_geom, ventyx_e_units_point.the_geom)
-- and ventyx_states_region.the_geom && ventyx_e_units_point.the_geom
-- and abbrev in ('BC', 'AB')
-- and statustype like 'Operating'
-- and fuel_type = 'WAT'
-- order by abbrev, ventyx_e_units_point.plant_name, cap_mw)
-- to '/Volumes/1TB_RAID/Models/GIS/Canada_Hydro/BC_AB_hydro_sites.csv' WITH HEADER CSV;

-- this table was then added to and simplified to make a nice list of Canadian hydro generators with start years and all.
-- references: Electric Power Generating Stations 2000 Canada.pdf (in Canadian_Hydro folder)
-- for the above, took the latest date if there was a range of years
-- http://en.wikipedia.org/wiki/List_of_power_stations_in_Alberta#cite_note-APP-0 (also saved in Canadian Hydro folder)
-- http://en.wikipedia.org/wiki/List_of_power_stations_in_British_Columbia#cite_note-18
-- AB: Dickson dam: 1992 http://www.algonquinpower.com/business/facility/hydroelectric_dickson.asp
-- AB: Chin Chute:1994 Oldman River:2003  http://www.industcards.com/hydro-canada-ab.htm
-- AB: Irrican = Drops 4,5and 6:2004 http://www.smrid.ab.ca/Irrican%20Power%20General%20Information.pdf
-- AB (incorrectly listed as BC): St Mary:1992 http://www.transalta.com/facilities/plants-operation/st-mary
-- BC: Aberfeldie: 1953 http://www.virtualmuseum.ca/Exhibitions/Hydro/en/dams/?action=aberfeldie
-- BC: Gordon M. Shrum: 1968 http://photovalet.com/257624
-- BC: Arrow Lakes: 2002 http://www.columbiapower.org/projects/arrowlakesstation.asp
-- BC: Walden CN: 1992 http://www.fortisbc.com/downloads/about_fortisbc/2009%20AIF_FortisBC_I2_PB_SEDAR.pdf
-- BC: Upper Mamquam: 2005 http://www.renewableenergyworld.com/rea/news/article/2005/11/canada-opens-new-run-of-river-hydro-facility-38716
-- BC: Kemano had a really incorrect capacity: each of it's gens should be 112MW http://en.wikipedia.org/wiki/Kemano,_British_Columbia

drop table if exists canadian_hydro;
create table canadian_hydro (
	province varchar(2),
	unit varchar(15),
	capacity_mw float,
	unit_id int,
	plant_name varchar(64),
	plant_oper varchar(64),
	description varchar(64),
	city varchar(64),
	plant_id int,
	plntoperid int,
	rec_id int,
	start_year year
);

load data local infile
	'/Volumes/1TB_RAID/Models/GIS/Canada_Hydro/BC_AB_hydro_sites.csv'
	into table canadian_hydro
	fields terminated by	','
	optionally enclosed by '"'
	ignore 1 lines;



-- takes output constraints from Washington state hydro
-- because we don't yet have data on Canadian hydro output and Washington is the closest to British Columbia and the Albertan Cascade mountains,
-- where almost all the WECC Canadian hydro resides
-- TODO: buy and download provience level montly Canadian Hydro data from CANSIM
insert into hydro_monthly_limits ( load_area, canada_plant_code, plant_name, primemover, start_year,
								year, month, capacity_mw, avg_output )
	SELECT 	CASE 	WHEN province = 'BC' THEN 'CAN_BC'
					WHEN province = 'AB' then 'CAN_ALB'
				END as load_area, 
			plant_id as canada_plant_code,
			replace(plant_name, " ", "_") as plant_name,
			'HY' as primemover,
			start_year,
			year,
			month,
			sum(capacity_mw),
			sum(capacity_mw) * avg_output_fraction as avg_output
	FROM canadian_hydro,
		(SELECT year,
				month,
				sum(avg_output)/sum(capacity_mw) as avg_output_fraction
		FROM hydro_monthly_limits
		where load_area like 'WA%'
		and primemover like 'HY'
		group by year, month) as washington_hydro_output_table
	group by 1,2,3,4,5,6,7;


-- ------------------------


-- aggregate the plants as much as possible and convert names to SWITCH names
-- all units in MW, MWh and MBtu terms

drop table if exists existing_plant_technologies;
create table existing_plant_technologies (
	technology varchar(64),
	fuel varchar(20),
	primemover varchar(4),
	cogen boolean,
	PRIMARY KEY (fuel, primemover, cogen),
	INDEX tech (technology) );
	
insert into existing_plant_technologies (technology, fuel, primemover, cogen) values
	('Gas_Steam_Turbine_EP', 'NG', 'ST', 0),
	('Gas_Steam_Turbine_Cogen_EP', 'NG', 'ST', 1),
	('Gas_Combustion_Turbine_EP', 'NG', 'GT', 0),
	('Gas_Combustion_Turbine_Cogen_EP', 'NG', 'GT', 1),
	('Gas_Internal_Combustion_Engine_EP', 'NG', 'IC', 0),
	('Gas_Internal_Combustion_Engine_Cogen_EP', 'NG', 'IC', 1),
	('CCGT_EP', 'NG', 'CC', 0),
	('CCGT_Cogen_EP', 'NG', 'CC', 1),
	('Coal_Steam_Turbine_EP', 'COL', 'ST', 0),
	('Coal_Steam_Turbine_Cogen_EP', 'COL', 'ST', 1),
	('Nuclear_EP', 'NUC', 'ST', 0),
	('Geothermal_EP', 'GEO', 'ST', 0),
	('Geothermal_EP', 'GEO', 'BT', 0),
	('Wind_EP', 'WND', 'WND', 0),
	('Hydro_NonPumped', 'WAT', 'HY', 0),
	('Hydro_Pumped', 'WAT', 'PS', 0)
	;


drop table if exists existing_plants_agg;
CREATE TABLE existing_plants_agg(
	ep_id mediumint unsigned PRIMARY KEY AUTO_INCREMENT,
	technology varchar(64) NOT NULL,
	load_area varchar(11) NOT NULL,
	plant_name varchar(64) NOT NULL,
	eia_id varchar(64) default 0,
	start_year year(4) NOT NULL,
	primemover varchar(4) NOT NULL,
	cogen boolean NOT NULL,
	fuel varchar(20)  NOT NULL,
	capacity_MW float NOT NULL,
	heat_rate float NOT NULL default 0,
	UNIQUE (plant_name, eia_id, primemover, cogen, fuel, start_year)
);


-- USA existing plants - wind and hydro excluded
-- should we capacity weight heat rate??? 
insert into existing_plants_agg (technology, load_area, plant_name, eia_id, start_year,
								primemover, cogen, fuel, capacity_MW, heat_rate)
	select 	technology,
			load_area,
  			replace(plntname, " ", "_") as plant_name,
  			plntcode as eia_id,
  			start_year,
			primemover,
			cogen,
  			fuel, 
			sum(peak_mw) as capacity_MW,
			avg(heat_rate) as heat_rate
	from	existing_plants join existing_plant_technologies using (fuel, primemover, cogen)
	group by 1,2,3,4,5,6,7,8;

-- add existing windfarms
insert into existing_plants_agg (technology, load_area, plant_name, eia_id, start_year,
								primemover, cogen, fuel, capacity_MW, heat_rate)
select 	'Wind_EP' as technology,
		load_area,
		concat('Wind_EP', '_', 3tier.windfarms_existing_info_wecc.windfarm_existing_id) as plant_name,
		0 as eia_id,
		year_online as start_year,
		'WND' as primemover,
		0 as cogen,
		'Wind' as fuel,
		capacity_MW,
		0 as heat_rate
from 	3tier.windfarms_existing_info_wecc;

-- add Canada and Mexico
insert into existing_plants_agg (technology, load_area, plant_name, eia_id, start_year,
								primemover, cogen, fuel, capacity_MW, heat_rate)
	select 	technology,
			load_area,
  			replace(name, " ", "_") as plant_name,
  			0 as eia_id,
   			start_year,
 			primemover,
  			cogen, 
  			fuel,
  			peak_mw as capacity_MW,
  			heatrate
  from canmexgen join existing_plant_technologies using (fuel, primemover, cogen);
  
-- add hydro to existing plants
-- we don't define an id for canadian plants (default 0) - they do have a name at least 
insert into existing_plants_agg (technology, load_area, plant_name, eia_id, start_year,
								primemover, cogen, fuel, capacity_MW, heat_rate)
	select 	distinct
			technology,
			load_area,
			plant_name,
			eia_id,
			start_year,
			primemover,
			0 as cogen,
			'Water' as fuel,
			capacity_mw,
			0 as heat_rate
	from hydro_monthly_limits
	join existing_plant_technologies using (primemover);
  

-- make EIA (aer) fuels into SWITCH fuels
update existing_plants_agg
set fuel = 	CASE WHEN fuel like 'NG' THEN 'Gas'
			WHEN fuel like 'NUC' THEN 'Uranium'
			WHEN fuel like 'COL' THEN 'Coal'
			WHEN fuel like 'GEO' THEN 'Geothermal'
			WHEN fuel like 'WND' THEN 'Wind'
			WHEN fuel like 'WAT' THEN 'Water'
			WHEN fuel like 'DFO' THEN 'DistillateFuelOil'
			WHEN fuel like 'RFO' THEN 'ResidualFuelOil'
			ELSE fuel
END;


