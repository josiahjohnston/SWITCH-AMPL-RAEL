-- build a table of data on existing plants


-- dispatchable plants are non-cogen natural gas plants
-- baseload plants are all others

-- efficiency of plants (heat rate) is based on net_gen_mwh and elec_fuel_mbtu, using the predominant fuel from 2007 generation

-- gets all of the plants in wecc, as assigned in eia860plant07_postgresql from postgresql

-- ########################

use generator_info;


-- create the existing plants table for EIA form 860, which contains info about plants, and their generating units
-- here we insert a seperate line for each possible fuel that each plant-primemover-cogen combination could burn
-- then aggregate the total capacity up to plant-primemover-cogen-fuel
-- and then use EIA form 960 data to pick only the plant-primemover-cogen-fuel combination that generated the most electricity in 2007
-- (the assumption being that this plant will continue to use the same fuel as its primary fuel)

-- first correct errors made by the eia:
update eia860gen07 set Cogenerator = 'N' where plntcode = 10755;
update eia860gen07 set Cogenerator = 'Y' where plntcode = 7552;
update grid.eia906_07_US set Combined_Heat_And_Power_Plant = 'Y' where plntcode = 7552;

-- no primary key here because we're going to use this table to pick a distinct fuel for each generator
drop table if exists existing_plants_860_gen_tmp;
create table existing_plants_860_gen_tmp (
	plntcode int NOT NULL,
	primemover varchar(4) NOT NULL,
	cogen boolean NOT NULL,
	fuel varchar(3) NOT NULL,
	start_year year NOT NULL,
	capacity_MW double NOT NULL,
	INDEX (plntcode, primemover, cogen, fuel)
	);


-- make a procedure that pivots the energy_source_1-6 into the existing_plants_860_gen format
	DROP PROCEDURE IF EXISTS pivot_860_energy_source;
	
	delimiter $$
	create procedure pivot_860_energy_source()
	BEGIN
	
	set @energy_source_tmp = 1;
	
	energy_source_loop: LOOP
	
	set @each_energy_source_insert_statment =
		concat( 'insert into existing_plants_860_gen_tmp (plntcode, primemover, cogen, fuel, start_year, capacity_MW) ',
				'select Plntcode as plntcode, Primemover as primemover, if(Cogenerator like \'Y\', 1, 0) as cogen, Energy_Source_',
				@energy_source_tmp,
				' as fuel, max(Operating_Year) as start_year, sum(nameplate) as capacity_MW ',
				'from eia860gen07 where Status like \'OP\' and Energy_Source_',
				@energy_source_tmp,
				' not like \'\' group by plntcode, primemover, cogen, fuel;'
				);

	PREPARE stmt_name FROM @each_energy_source_insert_statment;
	EXECUTE stmt_name;
	DEALLOCATE PREPARE stmt_name;
	
	set @energy_source_tmp = @energy_source_tmp + 1;
	
	IF (@energy_source_tmp > 6)
	    THEN LEAVE energy_source_loop;
	        END IF;
	END LOOP energy_source_loop;
	
	END;
	$$
	delimiter ;


	call pivot_860_energy_source();
	drop procedure pivot_860_energy_source;

-- now actually aggregate to plant-primemover-cogen-fuel
drop table if exists existing_plants_860_gen;
create table existing_plants_860_gen (
	plntcode int NOT NULL,
	primemover varchar(4) NOT NULL,
	cogen boolean NOT NULL,
	fuel varchar(3) NOT NULL,
	start_year year NOT NULL,
	capacity_MW double NOT NULL,
	total_fuel_consumption_mmbtus double,
	elec_fuel_consumption_mmbtus double,
	net_generation_megawatthours double,
	PRIMARY KEY (plntcode, primemover, cogen, fuel)
	);


insert into existing_plants_860_gen (plntcode, primemover, cogen, fuel, start_year, capacity_MW)
select 	plntcode,
		primemover,
		cogen,
		fuel,
		max(start_year) as start_year,
		sum(capacity_MW) as capacity_MW
from existing_plants_860_gen_tmp
group by plntcode, primemover, cogen, fuel;

-- EIA Form 906 ------------
-- now aggregate generation data from 2007 to calculate plant-primemover-cogen-fuel heat rates (in MMBtu per MWh)
-- to then be joined with plant capacity and start year data from existing_plants_860_gen
drop table if exists existing_plants_906;
create table existing_plants_906(
	plntcode int NOT NULL,
	primemover varchar(4) NOT NULL,
	cogen boolean NOT NULL,
	fuel varchar(3) NOT NULL,
	total_fuel_consumption_mmbtus double NOT NULL,
	elec_fuel_consumption_mmbtus double NOT NULL,
	net_generation_megawatthours double NOT NULL,
	PRIMARY KEY (plntcode, primemover, cogen, fuel)
	);

-- don't calculate heat rates for non-thermalish generators (hydro, solar, wind), as they're not used.
-- also, exclude fuels that Switch can't deal with yet (OTH, DFO, JF, KER, PC, RFO, WO)
-- also, don't calculate heat rates for units that didn't produce any electricity
-- but we want to keep units that didn't use any fuel as the steam turbine part of combined cycle plants may not use fuel directly

-- Municipal Solid Waste doesn't match because in eia860gen07 it's MSW
-- and in eia906_07_US it's a combination of biogenic and nonbiogenic components, MSB and MSN
-- we'll call it all MSW and call it bio solid for Switch
insert into existing_plants_906 (plntcode, primemover, cogen, fuel, total_fuel_consumption_mmbtus, elec_fuel_consumption_mmbtus, net_generation_megawatthours)
select 	plntcode,
		primemover,
		if(Combined_Heat_And_Power_Plant = 'Y', 1, 0) as cogen,
		if(Reported_Fuel_Type_Code in ('MSB', 'MSN'), 'MSW', Reported_Fuel_Type_Code) as fuel,
		sum(total_fuel_consumption_mmbtus) as total_fuel_consumption_mmbtus,
		sum(elec_fuel_consumption_mmbtus) as elec_fuel_consumption_mmbtus,
		sum(net_generation_megawatthours) as net_generation_megawatthours
from grid.eia906_07_US
where net_generation_megawatthours > 0
and ( elec_fuel_consumption_mmbtus > 0 or primemover in ('CT', 'CA', 'CS') )
-- and Reported_Fuel_Type_Code in ('BIT', 'LIG', 'SUB', 'WC', 'SC', 'NG', 'NUC', 'AB', 'MSB', 'OBS', 'TDF', 'WDS', 'LFG', 'OBG', 'GEO', 'MSN')
and Reported_Fuel_Type_Code not in ('WAT', 'SUN', 'WND', 'PUR', 'WH', 'OTH')
group by plntcode, primemover, cogen, fuel;

-- the EIA messed up some of the primemovers of geothermal plants between 860 and 906
-- we're going to trust eia860gen07 as it has specific info on the generating units
-- this means that some ST generators in 906 become BT in 860
-- there is a single plant (plntcode 10018) that has both BT and ST in eia860gen07, so it's excluded from the update
update existing_plants_906 join existing_plants_860_gen using (plntcode, cogen, fuel)
set existing_plants_906.primemover = existing_plants_860_gen.primemover
where plntcode != 10018
and fuel = 'GEO';

-- the EIA also didn't label coal as BIT/SUB correctly for a few plants... this is corrected here
update existing_plants_860_gen set fuel = 'SUB' where fuel = 'BIT' and plntcode in (113, 2442) and primemover = 'ST' and cogen = 0;
update existing_plants_860_gen set fuel = 'BIT' where fuel = 'SUB' and plntcode in (126) and primemover = 'ST' and cogen = 0;
update existing_plants_860_gen set fuel = 'BIT' where fuel = 'SUB' and plntcode in (10673, 10768, 54318, 54960) and primemover = 'ST' and cogen = 1;


-- now join on plant-primemover-cogen-fuel
update existing_plants_860_gen join existing_plants_906 using (plntcode, primemover, cogen, fuel)
set existing_plants_860_gen.total_fuel_consumption_mmbtus = existing_plants_906.total_fuel_consumption_mmbtus,
existing_plants_860_gen.elec_fuel_consumption_mmbtus = existing_plants_906.elec_fuel_consumption_mmbtus,
existing_plants_860_gen.net_generation_megawatthours = existing_plants_906.net_generation_megawatthours;

-- remove all plant-primemover-cogen-fuel combinations that didn't generate anything
delete from existing_plants_860_gen where net_generation_megawatthours is null;

-- aggregate combined cycle generators because their primemovers are labeled as either 'CT', 'CA', or 'CS' depending on plant config
drop table if exists combined_cycle_agg;
create temporary table combined_cycle_agg as
	select 	plntcode,
			'CC' as primemover,
			cogen,
			fuel,
			max(start_year) as start_year,
			sum(capacity_MW) as capacity_MW,
			sum(total_fuel_consumption_mmbtus) as total_fuel_consumption_mmbtus,
			sum(elec_fuel_consumption_mmbtus) as elec_fuel_consumption_mmbtus,
			sum(net_generation_megawatthours) as net_generation_megawatthours
	from existing_plants_860_gen
	where primemover in ('CT', 'CA', 'CS')
	group by plntcode, cogen, fuel;
	

delete from existing_plants_860_gen where primemover in ('CT', 'CA', 'CS');
insert into existing_plants_860_gen select * from combined_cycle_agg;


-- also aggregate a few biogas plants whose primemovers are GTs or OTs instead of ICs...
-- they're functionally the same in Switch and similar in real life so we'll rename them here to IC
drop table if exists biogas_agg;
create temporary table biogas_agg as
		select 	plntcode,
			'IC' as primemover,
			cogen,
			fuel,
			max(start_year) as start_year,
			sum(capacity_MW) as capacity_MW,
			sum(total_fuel_consumption_mmbtus) as total_fuel_consumption_mmbtus,
			sum(elec_fuel_consumption_mmbtus) as elec_fuel_consumption_mmbtus,
			sum(net_generation_megawatthours) as net_generation_megawatthours
	from existing_plants_860_gen
	where primemover in ('OT', 'GT', 'IC')
	and fuel in ('LFG', 'OBG')
	group by plntcode, cogen, fuel;
	
delete from existing_plants_860_gen where primemover in ('OT', 'GT', 'IC') and fuel in ('LFG', 'OBG');
insert into existing_plants_860_gen select * from biogas_agg;


-- now actually pick the primary fuel for each generating unit, along with the concomiant start year, capacity and heat rate
drop table existing_plants;
create table existing_plants(
	load_area varchar(11),
	plntname varchar(50),
	plntcode int NOT NULL,
	primemover varchar(4) NOT NULL,
	cogen boolean NOT NULL,
	fuel varchar(64) NOT NULL,
	start_year year NOT NULL,
	capacity_MW double NOT NULL,
	heat_rate double,
	cogen_thermal_demand_mmbtus_per_mwh double default 0,
	PRIMARY KEY (plntcode, primemover, cogen)
	);	

-- find the fuel with the most generation below
-- this could in theory give multiple fuels if they had the exact same net_generation_megawatthours,
-- but the primary key above will throw an error if this is the case
insert into existing_plants (plntcode, primemover, cogen, fuel, start_year, capacity_MW, heat_rate, cogen_thermal_demand_mmbtus_per_mwh)
SELECT	plntcode,
		primemover,
		cogen,
		fuel,
		start_year,
		capacity_MW,
		elec_fuel_consumption_mmbtus / net_generation_megawatthours as heat_rate,
		(total_fuel_consumption_mmbtus - elec_fuel_consumption_mmbtus) / net_generation_megawatthours as cogen_thermal_demand_mmbtus_per_mwh
from existing_plants_860_gen join
	( select 	plntcode,
				primemover,
				cogen,
				max(net_generation_megawatthours) as net_generation_megawatthours
		from existing_plants_860_gen
		group by plntcode, primemover, cogen
		) as max_gen
	using (plntcode, primemover, cogen, net_generation_megawatthours)
;


-- two generators have heat rates < 3.413 (the conversion factor for MMBtu to MWh)
-- which means they're creating energy out of nothing. These are the error of the EIA,
-- so we'll insert the capacity-weighted average heat rate for their primemover-cogen-fuel combo here
update existing_plants,
	(select 	primemover,
				cogen,
				fuel,
				sum(capacity_MW * heat_rate)/sum_capacity_MW as avg_heat_rate
		from 	existing_plants join
			(select primemover,
					cogen,
					fuel,
					sum(capacity_MW) as sum_capacity_MW
				from existing_plants
				where 	heat_rate > 3.413
				group by primemover, cogen, fuel ) as sum_cap_table
			using (primemover, cogen, fuel)		
		where 	heat_rate > 3.413
		group by primemover, cogen, fuel) as avg_heat_rate_table
set heat_rate = avg_heat_rate
where heat_rate < 3.413;


-- add plntname and load_area ---------

-- a few generators are left out of the load area identifiation because they're in the ocean, most importantly a 2GW nuke near San Diego.
-- this updates their load_areas...
update eia860plant07_postgresql set load_area = 'CA_SCE_S' where plntcode = 56051;
update eia860plant07_postgresql set load_area = 'CA_SDGE' where plntcode = 360;

-- get all plants in wecc, along with their load areas
drop table if exists existing_plants_860_plant;
create table existing_plants_860_plant (
	plntcode int primary key,
	plntname varchar(50) NOT NULL,
	load_area varchar(11) NOT NULL
	);

-- remove spaces and dashes from the plntname to make it all nice
insert into existing_plants_860_plant (plntcode, plntname, load_area)
	select 	distinct
			plntcode,
			replace(replace(replace(replace(plntname, ' ', '_'), '-', '_'), '/', '_'), '#', '_') as plntname,
			load_area
	from eia860plant07_postgresql
	where load_area is not null
	and load_area not like ''
	order by plntcode;

-- actually update existing_plants
update existing_plants join existing_plants_860_plant using (plntcode)
set existing_plants.load_area = existing_plants_860_plant.load_area,
existing_plants.plntname = existing_plants_860_plant.plntname;

-- delete all non-wecc plants
delete from existing_plants where load_area is null;


-- UPDATE FUELS to SWITCH FUELS ----------

-- aggregate other biogas with landfill gas
-- many biomass solids
-- many biomass liquids
-- waste coal and petroleum coke with coal
update existing_plants
set fuel = 	CASE
			WHEN fuel in ('BIT', 'LIG', 'SUB', 'WC', 'SC', 'PC') THEN 'Coal'
			WHEN fuel in ('NG', 'BFG', 'OG', 'PG') THEN 'Gas'
			WHEN fuel in ('DFO', 'JF', 'KER') THEN 'DistillateFuelOil'
			WHEN fuel in ('RFO', 'WO') THEN 'ResidualFuelOil'
			WHEN fuel = 'NUC' THEN 'Uranium'
			WHEN fuel in ('AB', 'MSB', 'OBS', 'TDF', 'WDS', 'MSN', 'MSW' ) THEN 'Bio_Solid'
			WHEN fuel in ('BLQ', 'OBL', 'SLW', 'WDL') THEN 'Bio_Liquid'
			WHEN fuel in ('LFG', 'OBG') then 'Bio_Gas'
			WHEN fuel = 'GEO' THEN 'Geothermal'
END;



-- select mn.plntcode, mn.primemover, mxyr, mnyr, mxyr- mnyr as mxdiff from
-- (select plntcode, primemover, max(Operating_Year) as mxyr from 
--  (select plntcode, primemover, count(*) as cnt from existing_plants group by 1,2 order by cnt desc) g join 
--  existing_plants using (plntcode, primemover) group by 1,2) as mx,
-- (select plntcode, primemover, min(Operating_Year) as mnyr from 
--  (select plntcode, primemover, count(*) as cnt from existing_plants group by 1,2 order by cnt desc) g join 
--  existing_plants using (plntcode, primemover) group by 1,2) as mn
-- where mn.plntcode = mx.plntcode and mn.primemover = mx.primemover
-- and mxyr- mnyr > 0
-- order by mxdiff desc
--
-- --------------------------------------------------------------
-- CANADA and MEXICO

-- for Canada, should use 'Electric Power Generating Stations Annual'
-- http://www.statcan.gc.ca/cgi-bin/imdb/p2SV.pl?Function=getSurvey&SurvId=2193&SurvVer=0&InstaId=14395&InstaVer=6&SDDS=2193&lang=en&db=IMDB&adm=8&dis=2

-- now we bring in nonhydro Canadian and Mexican generators from the TEPPC data.

-- selects out generators that we want.
-- we took out SynCrude plants... they are a few hundred MW of generation in Alberta but we don't have time to deal with them at the moment... should be put in at some point
-- some generators strangly have min and max cap switched... this means that avg_mw > capacity_MW
drop table if exists canmexgen;
create table canmexgen
SELECT 	name,
		area as load_area,
		categoryname,
		upper(left(categoryname, 2)) as primemover,
		year(commissiondate) as start_year,
		if(mincap > maxcap, mincap, maxcap) as capacity_MW,
		heatrate as heat_rate
FROM grid.TEPPC_Generators
where area in ('cfe', 'bctc', 'aeso')
and categoryname not in ('canceled', 'conventional hydro', 'wind', 'Other Steam', 'Synthetic Crude', 'CT Old Oil')
and categoryname not like '%RPS'
and categoryname not like '%Future'
and year(commissionDate) < 2010
and year(retirementdate) > 2010
and if(mincap > maxcap, mincap, maxcap) > 0
order by categoryname;

-- a few plants have made it to canmexgen that probably aren't real (they have generic names).. these plants get deleted here
delete from canmexgen where name = 'Gen @'; 

-- switches TEPPC load areas to v2 WECC load areas
update canmexgen set load_area = 'MEX_BAJA' where load_area = 'cfe';
update canmexgen set load_area = 'CAN_BC' where load_area = 'bctc';
update canmexgen set load_area = 'CAN_ALB' where load_area = 'aeso';

-- get the correct heat rates from the TEPPC_Generator_Categories table
update canmexgen, grid.TEPPC_Generator_Categories
set canmexgen.heat_rate = grid.TEPPC_Generator_Categories.heatrate
where canmexgen.categoryname = grid.TEPPC_Generator_Categories.name;

-- get fuels
alter table canmexgen add column fuel varchar(64);
update canmexgen set fuel = 'Geothermal' where categoryname like 'Geothermal';
update canmexgen set fuel = 'Coal' where primemover like 'CO';
update canmexgen set fuel = 'Gas' where fuel is null;

-- change a few primemovers to look like the US existing plants 'CT' to 'CC'
-- need to find if the Mexican Geothermal plants are 'ST' or 'BT'... put them as ST here.
update canmexgen set primemover = 'CC' where categoryname like 'CC%';
update canmexgen set primemover = 'ST' where primemover like 'CO';
update canmexgen set primemover = 'ST' where primemover like 'GE';
update canmexgen set primemover = 'GT' where primemover like 'CT';


-- the following fixes some zero and null values in the TEPPC dataset by digging into other TEPPC tables
update canmexgen set capacity_MW = '46' where name like 'PANCAN 9_2';
update canmexgen set capacity_MW = '48' where name like 'NEXENG%';
update canmexgen set capacity_MW = '48' where name like 'MEGENER2'; 
update canmexgen set capacity_MW = '128' where name like 'VancIsland1'; 
 
-- looked up cogen status of a bunch of canmex generators.  References on following lines.
-- couldn't find any info about Mexican cogen.
-- Alberta: http://www.energy.gov.ab.ca/Electricity/682.asp
-- some of the syncrudes are cogen as well, but we don't include them yet
-- BC Cogen that I could find
-- http://www.kelsonenergy.com/html_08/ke_can_island.html
-- other plants that are cogen from the name (GTC = gas turbine cogen)

-- also here is very nice
-- http://www2.cieedac.sfu.ca/media/publications/Cogeneration%20Report%202010%20Final.pdf
alter table canmexgen add column cogen boolean default 0;

update canmexgen
set cogen = 1
where name in
(	'Primros1', 'DowChmcl1', 'DowChmcl2', 'Rainbw4', 'JoffrCgnP',
	'NovaJffr1A', 'NovaJffr1B', 'AirLiqd1', 'MedcnHt10', 'Cavalier1',
	'Balzac1', 'Carslnd1', 'Carslnd2', 'Rainbw56', 'Redwater',
	'MuskgRvr1', 'MuskgRvr2', 'ColdLake1', 'ColdLake2', 'ScotfordST',
	'Mackay', 'Foster Creek1', 'Foster Creek2', 'SC_FirebagS2_1', 'SC_FirebagS3_1',
	'SC_FirebagS3_2', 'IslndCgn', 'VancIsland1', 'WstCstn1', 'WstCstn2',
	'Cancarb1', 'Redwater', 'BrrrdTh5', 'Weldwood1', 'Weldwood2' )
or categoryname like 'gtc'
or name like 'PANCAN%'
or name like 'NEXENG%'
or name like 'MEGEN%'
;

-- investment year of at least one BC plant is incorrect... see above reference
update canmexgen set start_year = 2002 where name = 'IslndCgn';

-- http://www.intergen.com/global/larosita.php... start year 2003
update canmexgen set start_year = 2003 where name = 'LaRosit1';

-- the geothermal and cogen plants don't have heat rates,
-- so we just use the average US ones for each primemover-fuel-cogen combination.
-- if the average US cogen heat rate comes in higher than the heat rate listed in the TEPPC database,
-- take the TEPPC heat rate instead
update 	canmexgen,
	(select 	primemover,
				cogen,
				fuel,
				sum(capacity_MW * heat_rate)/sum_capacity_MW as avg_heat_rate
		from 	existing_plants join
			(select primemover,
					cogen,
					fuel,
					sum(capacity_MW) as sum_capacity_MW
				from existing_plants
				group by primemover, cogen, fuel ) as sum_cap_table
			using (primemover, cogen, fuel)		
		group by primemover, cogen, fuel) as avg_heat_rate_table
set heat_rate =  if(heat_rate = 0 or heat_rate = null, avg_heat_rate,
					if(heat_rate > avg_heat_rate, avg_heat_rate, heat_rate)
				)
where 	canmexgen.primemover = avg_heat_rate_table.primemover
and		canmexgen.fuel = avg_heat_rate_table.fuel
and		canmexgen.cogen = avg_heat_rate_table.cogen
and		(canmexgen.cogen = 1 or canmexgen.fuel = 'GEO')
;

-- also add capacity-weighted cogen thermal demand
alter table canmexgen add column cogen_thermal_demand_mmbtus_per_mwh double default 0;
update 	canmexgen,
	(select 	primemover,
				cogen,
				fuel,
				sum(capacity_MW * cogen_thermal_demand_mmbtus_per_mwh)/sum_capacity_MW as avg_cogen_thermal_demand_mmbtus_per_mwh
		from 	existing_plants join
			(select primemover,
					cogen,
					fuel,
					sum(capacity_MW) as sum_capacity_MW
				from existing_plants
				group by primemover, cogen, fuel ) as sum_cap_table
			using (primemover, cogen, fuel)		
		group by primemover, cogen, fuel) as avg_cogen_thermal_demand_mmbtus_per_mwh_table
set cogen_thermal_demand_mmbtus_per_mwh = avg_cogen_thermal_demand_mmbtus_per_mwh
where 	canmexgen.primemover = avg_cogen_thermal_demand_mmbtus_per_mwh_table.primemover
and		canmexgen.fuel = avg_cogen_thermal_demand_mmbtus_per_mwh_table.fuel
and		canmexgen.cogen = avg_cogen_thermal_demand_mmbtus_per_mwh_table.cogen
and		canmexgen.cogen = 1
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

-- TODO: a few dams have start_years < 1900, which gives 0 here... update them to 1900ish
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
	fuel varchar(64),
	primemover varchar(4),
	cogen boolean,
	PRIMARY KEY (fuel, primemover, cogen),
	INDEX tech (technology) );
	
insert into existing_plant_technologies (technology, fuel, primemover, cogen) values
	('DistillateFuelOil_Combustion_Turbine_EP', 'DistillateFuelOil', 'GT', 0),
	('DistillateFuelOil_Internal_Combustion_Engine_EP', 'DistillateFuelOil', 'IC', 0),
	('Gas_Steam_Turbine_EP', 'Gas', 'ST', 0),
	('Gas_Steam_Turbine_Cogen_EP', 'Gas', 'ST', 1),
	('Gas_Combustion_Turbine_EP', 'Gas', 'GT', 0),
	('Gas_Combustion_Turbine_Cogen_EP', 'Gas', 'GT', 1),
	('Gas_Internal_Combustion_Engine_EP', 'Gas', 'IC', 0),
	('Gas_Internal_Combustion_Engine_Cogen_EP', 'Gas', 'IC', 1),
	('CCGT_EP', 'Gas', 'CC', 0),
	('CCGT_Cogen_EP', 'Gas', 'CC', 1),
	('Coal_Steam_Turbine_EP', 'Coal', 'ST', 0),
	('Coal_Steam_Turbine_Cogen_EP', 'Coal', 'ST', 1),
	('Nuclear_EP', 'Uranium', 'ST', 0),
	('Geothermal_EP', 'Geothermal', 'ST', 0),
	('Geothermal_EP', 'Geothermal', 'BT', 0),
	('Wind_EP', 'Wind', 'WND', 0),
	('Hydro_NonPumped', 'Water', 'HY', 0),
	('Hydro_Pumped', 'Water', 'PS', 0),
	('Bio_Gas_Internal_Combustion_Engine_EP', 'Bio_Gas', 'IC', 0),
	('Bio_Gas_Internal_Combustion_Engine_Cogen_EP', 'Bio_Gas', 'IC', 1),
	('Bio_Gas_Steam_Turbine_EP', 'Bio_Gas', 'ST', 0),
	('Bio_Liquid_Steam_Turbine_Cogen_EP', 'Bio_Liquid', 'ST', 1),
	('Bio_Solid_Steam_Turbine_EP', 'Bio_Solid', 'ST', 0),
	('Bio_Solid_Steam_Turbine_Cogen_EP', 'Bio_Solid', 'ST', 1)
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
	fuel varchar(64)  NOT NULL,
	capacity_MW float NOT NULL,
	heat_rate float default 0,
	cogen_thermal_demand_mmbtus_per_mwh float default 0,
	UNIQUE (plant_name, eia_id, primemover, cogen, fuel, start_year)
);

-- add existing windfarms
insert into existing_plants_agg (technology, load_area, plant_name, eia_id, start_year,
								primemover, cogen, fuel, capacity_MW, heat_rate, cogen_thermal_demand_mmbtus_per_mwh)
select 	'Wind_EP' as technology,
		load_area,
		concat('Wind_EP', '_', 3tier.windfarms_existing_info_wecc.windfarm_existing_id) as plant_name,
		0 as eia_id,
		year_online as start_year,
		'WND' as primemover,
		0 as cogen,
		'Wind' as fuel,
		capacity_MW,
		0 as heat_rate,
		0 as cogen_thermal_demand_mmbtus_per_mwh
from 	3tier.windfarms_existing_info_wecc;

-- add hydro to existing plants
-- we don't define an id for canadian plants (default 0) - they do have a name at least 
insert into existing_plants_agg (technology, load_area, plant_name, eia_id, start_year,
								primemover, cogen, fuel, capacity_MW, heat_rate, cogen_thermal_demand_mmbtus_per_mwh)
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
			0 as heat_rate,
			0 as cogen_thermal_demand_mmbtus_per_mwh
	from hydro_monthly_limits
	join existing_plant_technologies using (primemover);
  

-- USA existing plants - wind and hydro excluded
insert into existing_plants_agg (technology, load_area, plant_name, eia_id, start_year,
								primemover, cogen, fuel, capacity_MW, heat_rate, cogen_thermal_demand_mmbtus_per_mwh)
	select 	technology,
			load_area,
  			replace(plntname, " ", "_") as plant_name,
  			plntcode as eia_id,
  			start_year,
			primemover,
			cogen,
  			fuel, 
			capacity_MW,
			heat_rate,
			cogen_thermal_demand_mmbtus_per_mwh
	from	existing_plants join existing_plant_technologies using (primemover, fuel, cogen);

	
-- add Canada and Mexico
insert into existing_plants_agg (technology, load_area, plant_name, eia_id, start_year,
								primemover, cogen, fuel, capacity_MW, heat_rate, cogen_thermal_demand_mmbtus_per_mwh)
	select 	technology,
			load_area,
  			replace(name, " ", "_") as plant_name,
  			0 as eia_id,
   			start_year,
 			primemover,
  			cogen, 
  			fuel,
  			capacity_MW,
  			heat_rate,
  			cogen_thermal_demand_mmbtus_per_mwh
  from canmexgen join existing_plant_technologies using (fuel, primemover, cogen);
  
