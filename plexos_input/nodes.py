#!/usr/bin/python
# encoding: utf8

# We'll try to hew to TemplateForSwitch.xml first...

import csv, sys, itertools, os
from itertools import islice
from pprint import pprint
from lxml import etree
from lxml.builder import E

import id
from util import *

LOAD_AREAS = "../AMPL/inputs/load_areas.tab"


id.parse_id()

areas = open(LOAD_AREAS, "rb").readlines()[1:]
parsed = csv.DictReader(areas, delimiter = "\t")

# Which types do we generate? We need to extract everything else from the template.
generated_class_ids = ["System", "Generator", "Fuel", "Emission", "Region", "Node"]

# We need to also copy verbatim the objects in the classes we didn't generate.
verbatim_xpath = "//t_object[" + " or ".join(["class_id=" + id.class_ids[_id] for _id in list(set(id.class_ids.keys()).difference(generated_class_ids))]) + "]"
verbatim_t_objects = id.template.xpath(verbatim_xpath)
t_object_max = max([int(e.find("object_id").text) for e in verbatim_t_objects])
verbatim_t_objects = "".join(map(etree.tostring, verbatim_t_objects))

# We could stick to one global generator, but let's not.
generators = ["membership", "data"]
generators = map_dict(lambda _: succ(), generators)
# We need to suss out the max existing t_... entities that we copy verbatim.
# Add here ids that need to start from some value
# No, I don't know what uids are or why they start from here.
generators["object"] = succ(t_object_max + 1)
generators["uid"] = succ(128635360)

nodes = []
regions = []
memberships = []
data = []

# Generate the system node.
system_id = generators["object"].next()
system = E.t_object(
    E.object_id(system_id),
    E.class_id(id.class_ids["System"]),
    E.name("Generated"),
    E.description("The system object")
)

nodes.append(system)

# Generate some dummy objects we don't have yet.

dummy_generator_id = generators["object"].next()
dummy_generator = E.t_object(
    etree.Comment("Dummy generator object"),
    E.object_id(dummy_generator_id),
    E.class_id(id.class_ids["Generator"]),
    E.name("Dummy generator object"),
    E.description("Dummy generator object")
)

dummy_fuel_id = generators["object"].next()
dummy_fuel = E.t_object(
    etree.Comment("Dummy fuel"),
    E.object_id(dummy_fuel_id),
    E.class_id(id.class_ids["Fuel"]),
    E.name("Dummy fuel"),
    E.description("Dummy fuel")
)

dummy_emission_id = generators["object"].next()
dummy_emission = E.t_object(
    etree.Comment("Dummy emission"),
    E.object_id(dummy_emission_id),
    E.class_id(id.class_ids["Emission"]),
    E.name("Dummy emission"),
    E.description("Dummy emission")
)

dummy_node_id = generators["object"].next()
dummy_node = E.t_object(
    etree.Comment("Dummy node"),
    E.object_id(dummy_node_id),
    E.class_id(id.class_ids["Node"]),
    E.name("Dummy node"),
    E.description("Dummy node")
)

dummy_region_id = generators["object"].next()
dummy_region = E.t_object(
    etree.Comment("Dummy region"),
    E.object_id(dummy_region_id),
    E.class_id(id.class_ids["Region"]),
    E.name("Dummy region"),
    E.description("Dummy region")
)

dummy_system_generator_member_id = generators["membership"].next()
dummy_system_generator_member = E.t_membership(
    etree.Comment("Dummy system -> generator membership"),
    E.membership_id(dummy_system_generator_member_id),
    E.parent_class_id(id.class_ids["System"]),
    E.parent_object_id(system_id),
    E.collection_id(id.collection_ids[("System", "Generator")]),
    E.child_class_id(id.class_ids["Generator"]),
    E.child_object_id(dummy_generator_id)
)

dummy_system_fuel_member_id = generators["membership"].next()
dummy_system_fuel_member = E.t_membership(
    etree.Comment("Dummy system -> fuel membership"),
    E.membership_id(dummy_system_fuel_member_id),
    E.parent_class_id(id.class_ids["System"]),
    E.parent_object_id(system_id),
    E.collection_id(id.collection_ids[("System", "Fuel")]),
    E.child_class_id(id.class_ids["Fuel"]),
    E.child_object_id(dummy_fuel_id)
)

dummy_system_emission_member_id = generators["membership"].next()
dummy_system_emission_member = E.t_membership(
    etree.Comment("Dummy system -> emission membership"),
    E.membership_id(dummy_system_emission_member_id),
    E.parent_class_id(id.class_ids["System"]),
    E.parent_object_id(system_id),
    E.collection_id(id.collection_ids[("System", "Emission")]),
    E.child_class_id(id.class_ids["Emission"]),
    E.child_object_id(dummy_emission_id)
)

dummy_system_node_member_id = generators["membership"].next()
dummy_system_node_member = E.t_membership(
    etree.Comment("Dummy system -> node membership"),
    E.membership_id(dummy_system_node_member_id),
    E.parent_class_id(id.class_ids["System"]),
    E.parent_object_id(system_id),
    E.collection_id(id.collection_ids[("System", "Node")]),
    E.child_class_id(id.class_ids["Node"]),
    E.child_object_id(dummy_node_id)
)

dummy_system_region_member_id = generators["membership"].next()
dummy_system_region_member = E.t_membership(
    etree.Comment("Dummy system -> region membership"),
    E.membership_id(dummy_system_region_member_id),
    E.parent_class_id(id.class_ids["System"]),
    E.parent_object_id(system_id),
    E.collection_id(id.collection_ids[("System", "Region")]),
    E.child_class_id(id.class_ids["Region"]),
    E.child_object_id(dummy_region_id)
)

dummy_generator_fuel_member_id = generators["membership"].next()
dummy_generator_fuel_member = E.t_membership(
    etree.Comment("Dummy generator -> fuel membership"),
    E.membership_id(dummy_generator_fuel_member_id),
    E.parent_class_id(id.class_ids["Generator"]),
    E.parent_object_id(dummy_generator_id),
    E.collection_id(id.collection_ids[("Generator", "Fuel")]), 
    E.child_class_id(id.class_ids["Fuel"]),
    E.child_object_id(dummy_fuel_id)
)

dummy_emission_generator_member_id = generators["membership"].next()
dummy_emission_generator_member = E.t_membership(
    etree.Comment("Dummy emission -> generator membership"),
    E.membership_id(dummy_emission_generator_member_id),
    E.parent_class_id(id.class_ids["Emission"]),
    E.parent_object_id(dummy_emission_id),
    E.collection_id(id.collection_ids[("Emission", "Generator")]), 
    E.child_class_id(id.class_ids["Generator"]),
    E.child_object_id(dummy_generator_id)
)

dummy_generator_node_member_id = generators["membership"].next()
dummy_generator_node_member = E.t_membership(
    etree.Comment("Dummy generator -> node membership"),
    E.membership_id(dummy_generator_node_member_id),
    E.parent_class_id(id.class_ids["Generator"]),
    E.parent_object_id(dummy_generator_id),
    E.collection_id(id.collection_ids[("Generator", "Node")]), 
    E.child_class_id(id.class_ids["Node"]),
    E.child_object_id(dummy_node_id)
)

nodes.append(dummy_generator)
nodes.append(dummy_fuel)
nodes.append(dummy_emission)
nodes.append(dummy_node)
nodes.append(dummy_region)

memberships.append(dummy_system_generator_member)
memberships.append(dummy_system_fuel_member)
memberships.append(dummy_system_emission_member)
memberships.append(dummy_system_node_member)
memberships.append(dummy_system_region_member)
memberships.append(dummy_generator_fuel_member)
memberships.append(dummy_emission_generator_member)
memberships.append(dummy_generator_node_member)

for row in parsed:
    (node_instance_id, region_instance_id) = islice(generators["object"], 2)
    (system_node_member_id, node_region_member_id, system_region_member_id) = islice(generators["membership"], 3)
    node = (
        E.t_object(
            E.object_id(node_instance_id),
            E.class_id(id.class_ids["Node"]),
            E.name(row["load_area"]),
            E.description(row["load_area"])
        )
    )
    region = (
        E.t_object(
            E.object_id(region_instance_id),
            E.class_id(id.class_ids["Region"]),
            E.name("Region for " + row["load_area"]),
            E.description("Region for " + row["load_area"])
        )
    )
    node_region_membership = (
        E.t_membership(
            etree.Comment("Node to region membership for {0}".format(row["load_area"])),
            E.membership_id(node_region_member_id),
            E.parent_class_id(id.class_ids["Node"]),
            E.parent_object_id(node_instance_id),
            E.collection_id(id.collection_ids[("Node", "Region")]),
            E.child_class_id(id.class_ids["Region"]),
            E.child_object_id(region_instance_id)
        )
    )
    system_node_membership = (
        E.t_membership(
            etree.Comment("System to node membership for {0}".format(row["load_area"])),
            E.membership_id(system_node_member_id),
            E.parent_class_id(id.class_ids["System"]),
            E.parent_object_id(system_id),
            E.collection_id(id.collection_ids[("System", "Node")]),
            E.child_class_id(id.class_ids["Node"]),
            E.child_object_id(node_instance_id)
        )
    )
    system_region_membership = (
        E.t_membership(
            etree.Comment("System to region membership for {0}".format(row["load_area"])),
            E.membership_id(system_region_member_id),
            E.parent_class_id(id.class_ids["System"]),
            E.parent_object_id(system_id),
            E.collection_id(id.collection_ids[("System", "Region")]),
            E.child_class_id(id.class_ids["Region"]),
            E.child_object_id(region_instance_id)
        )
    )
    
    lpf_data = (
        E.t_data(
            etree.Comment("Load participation factor for {0}".format(row["load_area"])),
            E.data_id(generators["data"].next()),
            E.membership_id(system_node_member_id),
            E.property_id(id.property_ids["Load Participation Factor"]), # FIX
            E.value("1"), # Always 100% load participation in its region
            E.uid(generators["uid"].next())
        )
    )
    
    # nodes.append(node)
    # regions.append(region)
    # memberships.append(node_region_membership)
    # memberships.append(system_node_membership)
    # memberships.append(system_region_membership)
    # data.append(lpf_data)
    
node_xml = "".join(map(xml_tostring, nodes))
region_xml = "".join(map(xml_tostring, regions))
membership_xml = "".join(map(xml_tostring, memberships))
data_xml = "".join(map(xml_tostring, data))

print '<MasterDataSet xmlns="http://tempuri.org/MasterDataSet.xsd">'
print "<!-- BEGIN GENERATED XML -->"
print node_xml, region_xml, membership_xml, data_xml
print "<!-- END GENERATED XML -->"

print id.emit_verbatim()
print verbatim_t_objects
print '</MasterDataSet>'