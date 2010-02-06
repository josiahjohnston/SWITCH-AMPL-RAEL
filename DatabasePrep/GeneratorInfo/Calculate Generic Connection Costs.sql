-- calculates the connection cost for renewables and non renewables from eia860 interconnection cost data

-- the field 'transmission_line' denotes whether a transmission line had to be added to get the generator on the grid
-- so for the way Switch does connection costs, this means that that for renewables with specific sites from which
-- we calculate the distance to the grid, the cost of building a transmission line is already included,
-- so only a generic charge for hooking up a line to a substation should be included,
-- i.e. transmission_line like 'N'

-- but for other technologies that we build anywhere in a load area, there may or may not need to be added transmission
-- but we would have no way of knowing until we scoped specific sites, so we should include an average cost of transmission
-- therefore transmission_line like 'Y'




-- for site specific projects, which gives connect_cost_generic = $65639/MW
select round(avg(interconnection_cost_per_mw)) from (
select generator_info.eia860gen07.plntcode,
    generator_info.eia860gen07.gencode,
    nameplate,
    interconnection_cost*1000 as interconnection_cost,
    transmission_line,
    grid_enhancement_cost* 1000 as grid_enhancement_cost,
    (interconnection_cost + grid_enhancement_cost)*1000/nameplate as interconnection_cost_per_mw
from 
generator_info.eia860IntconY07, generator_info.eia860gen07
where interconnection_year > 2005
and generator_info.eia860IntconY07.plntcode = generator_info.eia860gen07.plntcode
and generator_info.eia860IntconY07.gencode = generator_info.eia860gen07.gencode
and transmission_line like 'N'
) as foo


-- for nonsite specific projects, which gives connect_cost_generic = $91289
select round(avg(interconnection_cost_per_mw)) from (
select generator_info.eia860gen07.plntcode,
    generator_info.eia860gen07.gencode,
    nameplate,
    interconnection_cost*1000 as interconnection_cost,
    transmission_line,
    grid_enhancement_cost* 1000 as grid_enhancement_cost,
    (interconnection_cost + grid_enhancement_cost)*1000/nameplate as interconnection_cost_per_mw
from 
generator_info.eia860IntconY07, generator_info.eia860gen07
where interconnection_year > 2005
and generator_info.eia860IntconY07.plntcode = generator_info.eia860gen07.plntcode
and generator_info.eia860IntconY07.gencode = generator_info.eia860gen07.gencode
and transmission_line like 'Y'
) as foo