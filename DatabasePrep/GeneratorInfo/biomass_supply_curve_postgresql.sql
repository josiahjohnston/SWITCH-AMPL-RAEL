-- creates a supply curve of biomass solids in each load area
-- and also finds the amount of bio gas produced in each load area


-- Sources:
-- 
-- http://bioenergy.ornl.gov/main.aspx
-- 
-- under Databases,
-- 
-- By State and Price:
-- Estimated Annual Cumulative Biomass Resources Available by State and Price (Spreadsheet)
-- Oak Ridge National Laboratory
-- 
-- same data with more explanation
-- http://bioenergy.ornl.gov/resourcedata/index.html
-- 
-- from NREL - biomass by county
-- http://www.nrel.gov/docs/fy06osti/39181.pdf (also in the GIS/Biomass folder)
-- http://www.nrel.gov/gis/biomass.html
-- 
-- Biomass as done in NEMS can be found here... might be a bit old
-- http://www.eia.doe.gov/oiaf/analysispaper/biomass/pdf/biomass.pdf
-- 

-- Canada: http://www.cbin-rcib.gc.ca/pro/index-eng.php

-- -----------------
-- import the price tier by state data
drop table if exists biomass_price_tiers_by_state_import;
create temporary table biomass_price_tiers_by_state_import(
	state character varying(30),
	urban_wood_wastes bigint,
	mill_wastes bigint,
	forest_residues bigint,
	agricultural_residues bigint,
	switchgrass bigint,
	short_rotation_woody_crops bigint
);

COPY biomass_price_tiers_by_state_import
FROM '/Volumes/1TB_RAID/Models/GIS/Biomass/biomass_price_tiers_by_state.csv'
WITH CSV HEADER;

alter table biomass_price_tiers_by_state_import add column row_id serial primary key;


-- the biomass data is ordered by price tier.. there are 48 states in the study (no AK and HI)
-- such that rows 1-48 represent $20/dry ton, 49-96 represent $30/dry ton and so on through $50/dry ton.
-- swrc = short-rotation woody crops.  This type of biomass is left off here because Switchgrass seems to be cheaper
-- for every place and they compete for land.  This query shows this fact (change > to < and =. A lot of the values are zero)

-- select switchgrass_table.state, switchgrass_table.price_dollars_per_dry_ton
-- from
-- (select state, price_dollars_per_dry_ton, quantity_dry_tons_per_year
-- from biomass_price_tiers_by_state
-- where type_of_biomass = 'short_rotation_woody_crops') as short_rotation_woody_crops_table,
-- (select state, price_dollars_per_dry_ton, quantity_dry_tons_per_year
-- from biomass_price_tiers_by_state
-- where type_of_biomass = 'switchgrass') as switchgrass_table
-- where short_rotation_woody_crops_table.state = switchgrass_table.state
-- and short_rotation_woody_crops_table.price_dollars_per_dry_ton = switchgrass_table.price_dollars_per_dry_ton
-- and short_rotation_woody_crops_table.quantity_dry_tons_per_year > switchgrass_table.quantity_dry_tons_per_year

-- the dollar years are all messed up in the data set (not my fault!)
-- forest_residues, agricultural_residues are in $1995
-- short_rotation_woody_crops, switchgrass: $1997
-- unknown: mill_wastes, urban_wood_wastes - we'll say $1997..
-- the mill_wastes price data is imprecise in the first place (see http://bioenergy.ornl.gov/resourcedata/index.html)
-- to go from $1995 -> $2007, multiply by 1.36
-- to go from $1997 -> $2007, multiply by 1.29

drop table if exists biomass_price_tiers_by_state;
create table biomass_price_tiers_by_state(
	state character varying(30),
	type_of_biomass character varying(30),
	price_dollars_per_dry_ton float,
	quantity_dry_tons_per_year float
);

insert into biomass_price_tiers_by_state
		select 	state,
				'urban_wood_wastes',
					CASE
						when row_id between 1 and 48 THEN 20
						when row_id between 49 and 96 THEN 30
						when row_id between 97 and 144 THEN 40
						when row_id between 145 and 192 THEN 50
					END,
				urban_wood_wastes
		from biomass_price_tiers_by_state_import
	UNION
		select 	state,
				'mill_wastes',
					CASE
						when row_id between 1 and 48 THEN 20
						when row_id between 49 and 96 THEN 30
						when row_id between 97 and 144 THEN 40
						when row_id between 145 and 192 THEN 50
					END,
				mill_wastes
		from biomass_price_tiers_by_state_import	
	UNION
		select 	state,
				'forest_residues',
					CASE
						when row_id between 1 and 48 THEN 20
						when row_id between 49 and 96 THEN 30
						when row_id between 97 and 144 THEN 40
						when row_id between 145 and 192 THEN 50
					END,
				forest_residues
		from biomass_price_tiers_by_state_import
	UNION
		select 	state,
				'agricultural_residues',
					CASE
						when row_id between 1 and 48 THEN 20
						when row_id between 49 and 96 THEN 30
						when row_id between 97 and 144 THEN 40
						when row_id between 145 and 192 THEN 50
					END,
				agricultural_residues
		from biomass_price_tiers_by_state_import	
		UNION
		select 	state,
				'switchgrass',
					CASE
						when row_id between 1 and 48 THEN 20
						when row_id between 49 and 96 THEN 30
						when row_id between 97 and 144 THEN 40
						when row_id between 145 and 192 THEN 50
					END,
				switchgrass
		from biomass_price_tiers_by_state_import
;

-- the above biomass quantities are cumulative, i.e. each price tier
-- includes the quantity from all of the lower price tiers
-- so these three updates subtract the lower price tier quantities to make a supply curve for each tier
-- must be done in order listed because they rely on data already present in the columns
update biomass_price_tiers_by_state
	set quantity_dry_tons_per_year = biomass_price_tiers_by_state.quantity_dry_tons_per_year - quantity_at_40_table.quantity_dry_tons_per_year
		from 	(select state,
						type_of_biomass,
						quantity_dry_tons_per_year
				from biomass_price_tiers_by_state
				where price_dollars_per_dry_ton = 40) as quantity_at_40_table
	where price_dollars_per_dry_ton = 50
	and quantity_at_40_table.state = biomass_price_tiers_by_state.state
	and quantity_at_40_table.type_of_biomass = biomass_price_tiers_by_state.type_of_biomass;

update biomass_price_tiers_by_state
	set quantity_dry_tons_per_year = biomass_price_tiers_by_state.quantity_dry_tons_per_year - quantity_at_30_table.quantity_dry_tons_per_year
		from 	(select state,
						type_of_biomass,
						quantity_dry_tons_per_year
				from biomass_price_tiers_by_state
				where price_dollars_per_dry_ton = 30) as quantity_at_30_table
	where price_dollars_per_dry_ton = 40
	and quantity_at_30_table.state = biomass_price_tiers_by_state.state
	and quantity_at_30_table.type_of_biomass = biomass_price_tiers_by_state.type_of_biomass;

update biomass_price_tiers_by_state
	set quantity_dry_tons_per_year = biomass_price_tiers_by_state.quantity_dry_tons_per_year - quantity_at_20_table.quantity_dry_tons_per_year
		from 	(select state,
						type_of_biomass,
						quantity_dry_tons_per_year
				from biomass_price_tiers_by_state
				where price_dollars_per_dry_ton = 20) as quantity_at_20_table
	where price_dollars_per_dry_ton = 30
	and quantity_at_20_table.state = biomass_price_tiers_by_state.state
	and quantity_at_20_table.type_of_biomass = biomass_price_tiers_by_state.type_of_biomass;


-- as mentioned above, the dollar years of the prices are messed up
-- now that we have the price tier quantities sorted out
-- we'll update the dollars to $2007 here using the conversion factors above
update biomass_price_tiers_by_state
	set price_dollars_per_dry_ton = 
		CASE
			WHEN type_of_biomass in ('forest_residues', 'agricultural_residues') THEN 1.36 * price_dollars_per_dry_ton
			WHEN type_of_biomass in ('switchgrass', 'mill_wastes', 'urban_wood_wastes') THEN 1.29 * price_dollars_per_dry_ton
		END;

-- makes the state names into abbreviations because the county biomass potential table has state abbreviations not state names
update biomass_price_tiers_by_state
	set state = abbrev
	from ventyx_states_region
	where biomass_price_tiers_by_state.state = ventyx_states_region."name";




-- -----------------------

-- pivot the NREL biomass by county data into state level data to compare against the price tier data
-- be sure to include DC when we go to the whole country
drop table if exists biomass_total_by_state;
create table biomass_total_by_state as
	SELECT 	st_abbr as state,
		'urban_wood_wastes' as type_of_biomass,
		sum(urban_wood) as total_quantity_dry_tons_per_year
	from ventyx_counties_region
	where st_abbr not in ('AK', 'HI', 'GU', 'AS', 'PR', 'VI')
	and urban_wood >= 0
	group by state
UNION
	SELECT 	st_abbr as state,
		'mill_wastes' as type_of_biomass,
		sum(primmill + secmill) as total_quantity_dry_tons_per_year
	from ventyx_counties_region
	where st_abbr not in ('AK', 'HI', 'GU', 'AS', 'PR', 'VI')
	and primmill >= 0 and secmill >= 0
	group by state
UNION
	SELECT 	st_abbr as state,
		'forest_residues' as type_of_biomass,
		sum(forest) as total_quantity_dry_tons_per_year
	from ventyx_counties_region
	where st_abbr not in ('AK', 'HI', 'GU', 'AS', 'PR', 'VI')
	and forest >= 0
	group by state	
UNION
	SELECT 	st_abbr as state,
		'agricultural_residues' as type_of_biomass,
		sum(crops) as total_quantity_dry_tons_per_year
	from ventyx_counties_region
	where st_abbr not in ('AK', 'HI', 'GU', 'AS', 'PR', 'VI')
	and crops >= 0
	group by state	
UNION
	SELECT 	st_abbr as state,
		'switchgrass' as type_of_biomass,
		sum(switchgras) as total_quantity_dry_tons_per_year
	from ventyx_counties_region
	where st_abbr not in ('AK', 'HI', 'GU', 'AS', 'PR', 'VI')
	and switchgras >= 0
	group by state	
UNION
	SELECT 	st_abbr as state,
		'Bio_Gas' as type_of_biomass,
		sum(lndfil_ch4 + manure + wwtp_ch4) as total_quantity_dry_tons_per_year
	from ventyx_counties_region
	where st_abbr not in ('AK', 'HI', 'GU', 'AS', 'PR', 'VI')
	and lndfil_ch4 >= 0 and manure >= 0 and wwtp_ch4 >= 0
	group by state	
;


-- ---------------------
-- compare the two data sets: ideally the county level NREL data set would have more
-- total available biomass than the ORNL state based tiered data because NREL was trying
-- to do a total assessment of biomass availability, while biomass only makes it into the ORNL data set
-- if the price is <$50/t.

-- this is however not the case, of course

-- make a table to compare the two data sets
drop table if exists tier_total_comparison_table;
create temporary table tier_total_comparison_table as
select 	biomass_total_by_state.state,
	biomass_total_by_state.type_of_biomass,
	biomass_total_by_state.total_quantity_dry_tons_per_year,
	biomass_total_by_state.total_quantity_dry_tons_per_year - sum(biomass_price_tiers_by_state.quantity_dry_tons_per_year) as tier_quantity_diff_from_total
from biomass_total_by_state, biomass_price_tiers_by_state
where biomass_total_by_state.state = biomass_price_tiers_by_state.state
and biomass_total_by_state.type_of_biomass = biomass_price_tiers_by_state.type_of_biomass
group by biomass_total_by_state.state, biomass_total_by_state.type_of_biomass, biomass_total_by_state.total_quantity_dry_tons_per_year
order by tier_quantity_diff_from_total
;


-- if the NREL county availability data has LESS biomass than ORNL data (aggregated to the state level)
-- a supply curve is constructed for each state for each type of biomass
-- based on the percentage of resource availability at each of the four price tiers.
-- the total state level biomass availability from the NREL counties study is then multiplied by this percentage supply curve
-- giving the available biomass at each price
-- thereby assuming that the distribution of biomass within a state is similar in both studies
-- an assumption that is not completely true because each study makes different assumptions when deriving their availability numbers.

-- the total amount of biomass, 
drop table if exists corrected_biomass_price_tiers_by_state;
create temporary table corrected_biomass_price_tiers_by_state as 
select 	biomass_price_tiers_by_state.state,
		biomass_price_tiers_by_state.type_of_biomass,
		price_dollars_per_dry_ton,
		total_quantity_dry_tons_per_year*(quantity_dry_tons_per_year/total_biomass) as quantity_dry_tons_per_year
from 	biomass_price_tiers_by_state,
		tier_total_comparison_table,
		(select state,
				type_of_biomass,
				sum(quantity_dry_tons_per_year) as total_biomass
		from biomass_price_tiers_by_state
		where quantity_dry_tons_per_year > 0
		group by state, type_of_biomass) as total_biomass_table
where total_biomass_table.state = biomass_price_tiers_by_state.state
and total_biomass_table.type_of_biomass = biomass_price_tiers_by_state.type_of_biomass
and tier_total_comparison_table.state = biomass_price_tiers_by_state.state
and tier_total_comparison_table.type_of_biomass = biomass_price_tiers_by_state.type_of_biomass
and tier_quantity_diff_from_total < 0
order by 1,2,3
;


-- if the NREL county availability data has MORE biomass than ORNL data (aggregated to the state level)
-- the additional biomass is assumed to have a price higher than $50/t
-- here we assume $60/t which when brought from $1997 to $2007 yields $77.4/t.
-- more investigation here would be warranted... likely the price of this extra biomass could vary largely

-- first, insert the totals from the lower price tiers as they're not going to change for this case
insert into corrected_biomass_price_tiers_by_state
select 	biomass_price_tiers_by_state.state,
		biomass_price_tiers_by_state.type_of_biomass,
		price_dollars_per_dry_ton,
		quantity_dry_tons_per_year
from tier_total_comparison_table, biomass_price_tiers_by_state
where tier_total_comparison_table.state = biomass_price_tiers_by_state.state
and tier_total_comparison_table.type_of_biomass = biomass_price_tiers_by_state.type_of_biomass
and tier_quantity_diff_from_total > 0
;

-- now add the extra biomass at $77.4/t
insert into corrected_biomass_price_tiers_by_state
select 	state,
		type_of_biomass,
		77.4 as price_dollars_per_dry_ton,
		tier_quantity_diff_from_total as quantity_dry_tons_per_year
from tier_total_comparison_table
where tier_quantity_diff_from_total > 0
;


-- in case any of the two availabality data sets had the exact amount, then add it here to the supply curve
insert into corrected_biomass_price_tiers_by_state
select 	biomass_price_tiers_by_state.state,
		biomass_price_tiers_by_state.type_of_biomass,
		price_dollars_per_dry_ton,
		quantity_dry_tons_per_year
from tier_total_comparison_table, biomass_price_tiers_by_state
where tier_total_comparison_table.state = biomass_price_tiers_by_state.state
and tier_total_comparison_table.type_of_biomass = biomass_price_tiers_by_state.type_of_biomass
and tier_quantity_diff_from_total = 0
;

-- ------------------
-- construct a supply curve for each county, which is made from the state level supply curve
-- scaled to the biomass availabality of each type in each county
-- the assumption here is that biomass resources within a state are similar
-- an assumption that will be correct in many cases but not completely valid for all
-- (e.g. eastern oregon is a lot different than western oregon)

-- first make the county level pivot table
drop table if exists biomass_by_county;
create temporary table biomass_by_county as
	SELECT 	st_abbr as state,
			county,
			'urban_wood_wastes' as type_of_biomass,
			urban_wood as county_quantity_dry_tons_per_year
	from ventyx_counties_region
	where st_abbr not in ('AK', 'HI', 'GU', 'AS', 'PR', 'VI')
	and urban_wood >= 0
UNION
	SELECT 	st_abbr as state,
			county,
			'mill_wastes' as type_of_biomass,
			primmill + secmill as county_quantity_dry_tons_per_year
	from ventyx_counties_region
	where st_abbr not in ('AK', 'HI', 'GU', 'AS', 'PR', 'VI')
	and primmill >= 0 and secmill >= 0
UNION
	SELECT 	st_abbr as state,
			county,
			'forest_residues' as type_of_biomass,
			forest as county_quantity_dry_tons_per_year
	from ventyx_counties_region
	where st_abbr not in ('AK', 'HI', 'GU', 'AS', 'PR', 'VI')
	and forest >= 0
UNION
	SELECT 	st_abbr as state,
			county,
			'agricultural_residues' as type_of_biomass,
			crops as county_quantity_dry_tons_per_year
	from ventyx_counties_region
	where st_abbr not in ('AK', 'HI', 'GU', 'AS', 'PR', 'VI')
	and crops >= 0
UNION
	SELECT 	st_abbr as state,
			county,
			'switchgrass' as type_of_biomass,
			switchgras as county_quantity_dry_tons_per_year
	from ventyx_counties_region
	where st_abbr not in ('AK', 'HI', 'GU', 'AS', 'PR', 'VI')
	and switchgras >= 0
UNION
	SELECT 	st_abbr as state,
			county,
			'Bio_Gas' as type_of_biomass,
			lndfil_ch4 + manure + wwtp_ch4 as county_quantity_dry_tons_per_year
	from ventyx_counties_region
	where st_abbr not in ('AK', 'HI', 'GU', 'AS', 'PR', 'VI')
	and lndfil_ch4 >= 0 and manure >= 0 and wwtp_ch4 >= 0
;



-- finally make the county level supply curve
drop table if exists biomass_county_supply_curve;
create table biomass_county_supply_curve(
	state character varying(2),
	county character varying(75),
	type_of_biomass character varying(30),
	price_dollars_per_dry_ton float,
	quantity_dry_tons_per_year float,
	CONSTRAINT bio_pkey PRIMARY KEY (state, county, type_of_biomass, price_dollars_per_dry_ton)
);

-- multiplies the amount of each type of biomass in each county by the supply curve,
-- here represented for each state by quantity_dry_tons_per_year/total_quantity_dry_tons_per_year
insert into biomass_county_supply_curve
select 	corrected_biomass_price_tiers_by_state.state,
		county,
		corrected_biomass_price_tiers_by_state.type_of_biomass,
		corrected_biomass_price_tiers_by_state.price_dollars_per_dry_ton,
		county_quantity_dry_tons_per_year*(corrected_biomass_price_tiers_by_state.quantity_dry_tons_per_year/biomass_total_by_state.total_quantity_dry_tons_per_year)
from 	corrected_biomass_price_tiers_by_state,
		biomass_by_county,
		biomass_total_by_state 
where 	biomass_by_county.state = corrected_biomass_price_tiers_by_state.state
and		biomass_by_county.state = biomass_total_by_state.state
and		biomass_by_county.type_of_biomass = corrected_biomass_price_tiers_by_state.type_of_biomass
and		biomass_by_county.type_of_biomass = biomass_total_by_state.type_of_biomass
and 	biomass_total_by_state.total_quantity_dry_tons_per_year > 0
;


-- now add the CH4 sources back
-- they didn't match above because they don't have a supply curve because you just  
-- collect gas onsite and your fuel costs are wrapped up in the captial, variable and fixed O+M of the plant
insert into biomass_county_supply_curve
select 	state,
		county,
		type_of_biomass,
		0 as price_dollars_per_dry_ton,
		county_quantity_dry_tons_per_year
from 	biomass_by_county
where	type_of_biomass = 'Bio_Gas';



-- now convert to million btus (mbtus)
-- and add the correct prices in $2007/mbtu

-- Conversion factors:
-- http://bioenergy.ornl.gov/papers/misc/energy_conv.html
-- agricultural residues/crops have an energy content of 10-17 GJ/t depending on moisture -> use upper end estimate of 15 GJ/t because the biomass availablity is in dry ton
-- 1BTU = 1054.350J or equivalently 1mbtu = 1054350000J so this is 
-- 15 GJ/t * 10^9 J/GJ* ( 1 mbtu / 1054350000 J) = 14.23 mbtu/t

-- http://bioenergy.ornl.gov/papers/bioen96/mclaugh.html
-- Wood(dry): 	18.6 mbtu/t (for mill wastes, forest and urban wood)
-- Switchgrass: 17.4 mbtu/t

-- http://www.window.state.tx.us/specialrpt/energy/exec/landfill.html
-- which references the eia website
-- the NREL data has the tonnes of methane, not of landfill gas, so this number can be directly converted
-- into energy using the energy content of natural gas.  The non-methane portions of landfill gas are effectively discarded
-- landfill gas/bio gas: 1031 Btu/ft^3 * ( 1 mbtu / 10^6 Btu ) * ( 1ft^3 /28.3168466 L ) * 22.4L/1mol * 1mol/16g * (10^6g/1t) = 51.0 mbtu/t

alter table biomass_county_supply_curve add column price_dollars_per_mbtu double precision;
update biomass_county_supply_curve
set price_dollars_per_mbtu = 
	CASE
		when type_of_biomass in ('mill_wastes', 'forest_residues', 'urban_wood_wastes') THEN price_dollars_per_dry_ton / 18.6
		when type_of_biomass in ('switchgrass') THEN price_dollars_per_dry_ton / 17.4
		when type_of_biomass in ('agricultural_residues') THEN price_dollars_per_dry_ton / 14.23
		when type_of_biomass in ('Bio_Gas') THEN price_dollars_per_dry_ton / 51.0		
	END;

alter table biomass_county_supply_curve add column mbtus_per_year double precision;
update biomass_county_supply_curve
set mbtus_per_year = 
	CASE
		when type_of_biomass in ('mill_wastes', 'forest_residues', 'urban_wood_wastes') THEN quantity_dry_tons_per_year * 18.6
		when type_of_biomass in ('switchgrass') THEN quantity_dry_tons_per_year * 17.4
		when type_of_biomass in ('agricultural_residues') THEN quantity_dry_tons_per_year * 14.23
		when type_of_biomass in ('Bio_Gas') THEN quantity_dry_tons_per_year * 51.0
	END;



-- -----------------------

-- divides up counties by land area in each load area to partition county biomass potentials into each load area.
-- Hawaii and Alaska are excluded to speed up the query.
-- there is a bit of shapefile overlap between the counties and the load areas that aren't in the US,
-- so we don't include non-US biomass potentials because the data is only for the US

Drop table if exists biomass_county_to_load_area;
Create table biomass_county_to_load_area as 
select 	load_area,
		ventyx_counties_region.st_abbr as state,
		ventyx_counties_region.county,
		area(ventyx_counties_region.the_geom) as county_area,
		area(intersection(ventyx_counties_region.the_geom, wecc_load_areas.polygon_geom))/area(ventyx_counties_region.the_geom) as county_area_fraction_in_load_area
from ventyx_counties_region, wecc_load_areas
where  	intersects(wecc_load_areas.polygon_geom, ventyx_counties_region.the_geom)
and		wecc_load_areas.polygon_geom && ventyx_counties_region.the_geom
and st_abbr not in ('AK', 'HI')
and load_area not like 'MEX%'
and load_area not like 'CAN%'
order by 1,2,3;



-- sums together all of the biomass potentials from each counties by load area
-- to get the total biomass potential by feedstock in each load area
Drop table if exists biomass_supply_curve_by_load_area;
Create table biomass_supply_curve_by_load_area(
	price_level_la_id serial primary key,
	breakpoint_id int,
	load_area character varying(11),
	fuel character varying(30),
	price_dollars_per_mbtu double precision,
	mbtus_per_year double precision,
	breakpoint_mbtus_per_year double precision
);

-- first do the solid biomass (will be used to cofire and in dedicated steam turbines)
insert into biomass_supply_curve_by_load_area (load_area, fuel, price_dollars_per_mbtu, mbtus_per_year)
select * from
	(SELECT load_area,
			cast('Bio_Solid' as text) as fuel,
			price_dollars_per_mbtu,
			sum( mbtus_per_year * county_area_fraction_in_load_area) as mbtus_per_year
	from	biomass_county_supply_curve,
			biomass_county_to_load_area
	where 	biomass_county_supply_curve.county = biomass_county_to_load_area.county
	and 	biomass_county_supply_curve.state = biomass_county_to_load_area.state
	and		type_of_biomass <> 'Bio_Gas'
	group by load_area, price_dollars_per_mbtu) as load_area_potential_subtable
where mbtus_per_year > 100
order by 1,2,3;

update biomass_supply_curve_by_load_area
set breakpoint_id = price_level_la_id - min_price_level_la_id + 1
from (select load_area, min(price_level_la_id) as min_price_level_la_id
		from biomass_supply_curve_by_load_area where fuel = 'Bio_Solid' group by load_area) as min_id_table
		where min_id_table.load_area = biomass_supply_curve_by_load_area.load_area
		and fuel = 'Bio_Solid';


-- now do the bio gas (will be used in landfill gas type generators)
-- there isn't a supply curve for Bio_Gas, but it's added here to be brought along with Bio_Solid
insert into biomass_supply_curve_by_load_area (load_area, fuel, price_dollars_per_mbtu, mbtus_per_year, breakpoint_mbtus_per_year)
select * from
	(SELECT load_area,
			cast('Bio_Gas' as text) as fuel,
			price_dollars_per_mbtu,
			sum( mbtus_per_year * county_area_fraction_in_load_area) as mbtus_per_year,
			sum( mbtus_per_year * county_area_fraction_in_load_area) as breakpoint_mbtus_per_year
	from	biomass_county_supply_curve,
			biomass_county_to_load_area
	where 	biomass_county_supply_curve.county = biomass_county_to_load_area.county
	and 	biomass_county_supply_curve.state = biomass_county_to_load_area.state
	and		type_of_biomass = 'Bio_Gas'
	group by load_area, price_dollars_per_mbtu) as load_area_potential_subtable
where mbtus_per_year > 100
order by 1,2,3;

-- the breakpoint_id for bio gas doesn't mean anything as it's only relevant for bio solid.
update biomass_supply_curve_by_load_area set breakpoint_id = price_level_la_id where fuel = 'Bio_Gas';

-- the above table represents the amount of biomass that can be obtained at a certain price point,
-- but for AMPL's piecewise linear cost forumlation, the total mbtus_per_year is needed
-- (i.e. the integral of mbtus_per_year from 0 to the current price_dollars_per_mbtu
-- this small procedure does this integral for each point

CREATE OR REPLACE FUNCTION sum_bio_potential() RETURNS VOID
AS $$

DECLARE current_load_area character varying(11);
DECLARE current_price_dollars_per_mbtu double precision;

BEGIN

drop table if exists la_price_level;
create temporary table la_price_level as 
	select 	distinct load_area, price_dollars_per_mbtu
		from biomass_supply_curve_by_load_area
		where fuel = 'Bio_Solid';

-- start the while loop to iterate over the grid_ids to make sure the farms don't have widely varying insolation
-- at the end of the loop, every gid from insolation_good_solar_land_grid should have been given a new polygon
-- so the while loop will stop after this becomes true
WHILE ( ( select count(*) from la_price_level ) > 0 ) LOOP

select load_area from la_price_level limit 1
	into current_load_area;
select price_dollars_per_mbtu from la_price_level where la_price_level.load_area = current_load_area limit 1
	into current_price_dollars_per_mbtu;

update 	biomass_supply_curve_by_load_area
	set breakpoint_mbtus_per_year = bp_table.breakpoint_mbtus_per_year
	from (select 	sum(mbtus_per_year) as breakpoint_mbtus_per_year
			from 	biomass_supply_curve_by_load_area
			where	load_area = current_load_area
			and		price_dollars_per_mbtu <= current_price_dollars_per_mbtu) as bp_table
	where load_area = current_load_area
	and	  price_dollars_per_mbtu = current_price_dollars_per_mbtu;
	
-- delete the current load area and price level
delete from la_price_level where load_area = current_load_area and price_dollars_per_mbtu = current_price_dollars_per_mbtu;

END LOOP;

END;
$$ LANGUAGE 'plpgsql';

-- Actually call the function
SELECT sum_bio_potential();
drop function sum_bio_potential();


-- export to csv to get to mysql
COPY 
(select breakpoint_id,
		load_area,
		price_dollars_per_mbtu,
		mbtus_per_year,
		breakpoint_mbtus_per_year
from biomass_supply_curve_by_load_area
where fuel = 'Bio_Solid'
order by load_area, breakpoint_id)
TO '/Volumes/1TB_RAID/Models/GIS/Biomass/biomass_solid_supply_curve_by_load_area.csv'
WITH 	CSV
		HEADER;

-- the proposed_renewable_sites script sweeps up this table and adds Bio_Solid and Bio_Gas to the sites