#!/usr/bin/python
# encoding: utf8

# We'll try to hew to TemplateForSwitch.xml first...

import csv, sys, itertools, os
from itertools import islice
from lxml import etree
from lxml.builder import E

def succ(start = 0):
    _ = start
    while True:
        yield str(_)
        _ += 1
        
def map_dict(fn, iter):
    return dict(zip(iter, map(fn, iter)))
        
# We could stick to one global generator, but let's not.
generators = ["object", "membership", "data"]
generators = map_dict(lambda _: succ(), generators)
# Add here ids that need to start from some value
# No, I don't know what uids are or why they start from here.
generators["uid"] = succ(128635360)

xml_tostring = lambda node: etree.tostring(node, pretty_print = True)
    
# Is this even necessary? Maybe we should just write out the xpath, if it's a one time thing...
# Find in `xml` the element of type `xml_type` which has the child `<name>name</name>` 
# and possibly other constraints `where_(child attribute name)`, and return the value of the child node
# `requested_child`, which defualts to `(xml_type)_id` (t_object -> object_id).
def typed_name_to_id(xml, xml_type, name, requested_child = None, **where):
    if requested_child is None and xml_type[:2] == "t_":
        requested_child = xml_type[2:] + "_id"
        
    xpath_constraint = ""
    for k, v in where.items():
        if k[:6] == "where_":
            xpath_constraint += " and {attribute}='{value}'".format(attribute = k[6:], value = v)
    
    xpath = "//{xml_type}[name='{name}'{constraint}]/{requested_child}/text()".format(
        xml_type = xml_type, name = name, constraint = xpath_constraint, requested_child = requested_child)
    # print xpath   
    _ = xml.xpath(xpath)
    return "".join(_)
    
# We'll refer to t_classes by name for sanity...
definitions = ["classes", "properties"]
definitions = map_dict(lambda name: etree.parse(open(os.path.join("templates", name + ".xml"))), definitions)

# Creating nodes
# Not sure about categories for now. We will not include them
# Do we want to keep collection definitions static? For now, generate only memberships

LOAD_AREAS = "../AMPL/inputs/load_areas.tab"

areas = open(LOAD_AREAS, "rb").readlines()[1:]
parsed = csv.DictReader(areas, delimiter = "\t")

class_ids = ["System", "Node", "Region"]
class_ids = map_dict( \
    lambda class_name: typed_name_to_id(definitions["classes"], "t_class", class_name), \
    class_ids)

# This map would be too insane. Just do it manually.
# Keys are (Parent, Child)
collection_ids = {
    ("System", "Node"): typed_name_to_id(definitions["classes"], "t_collection", "Nodes", where_parent_class_id = class_ids["System"], where_child_class_id = class_ids["Node"]),
    ("Node", "Region"): typed_name_to_id(definitions["classes"], "t_collection", "Region", where_parent_class_id = class_ids["Node"], where_child_class_id = class_ids["Region"])
}

# For now we're really only interested in this property.
property_ids = {
    "Load Participation Factor": typed_name_to_id(definitions["properties"], "t_property", "Load Participation Factor", where_collection_id = collection_ids[("System", "Node")])
}

nodes = []
regions = []
memberships = []
data = []

# Generate the system node once.
system_id = generators["object"].next()
system = E.t_object(
    E.object_id(system_id),
    E.class_id(class_ids["System"]),
    E.name("Generated"),
    E.description("The system object")
)

nodes.append(system)

for row in parsed:
    (node_instance_id, region_instance_id) = islice(generators["object"], 2)
    (system_node_member_id, node_region_member_id) = islice(generators["membership"], 2)
    node = (
        E.t_object(
            E.object_id(node_instance_id),
            E.class_id(class_ids["Node"]),
            E.name(row["load_area"]),
            E.description(row["load_area"])
        )
    )
    region = (
        E.t_object(
            E.object_id(region_instance_id),
            E.class_id(class_ids["Region"]),
            E.name("Region for " + row["load_area"]),
            E.description("Region for " + row["load_area"])
        )
    )
    # For some reason it's reversed and the node is the parent and the region is the child.
    region_membership = (
        E.t_membership(
            etree.Comment("Node to region membership for {0}".format(row["load_area"])),
            E.membership_id(node_region_member_id),
            E.parent_class_id(class_ids["Node"]),
            E.parent_object_id(node_instance_id),
            E.collection_id(collection_ids[("Node", "Region")]), # FIXME
            E.child_class_id(class_ids["Region"]),
            E.child_object_id(region_instance_id)
        )
    )
    system_membership = (
        E.t_membership(
            etree.Comment("Node to system membership for {0}".format(row["load_area"])),
            E.membership_id(system_node_member_id),
            E.parent_class_id(class_ids["System"]),
            E.parent_object_id(system_id),
            E.collection_id(collection_ids[("System", "Node")]),
            E.child_class_id(class_ids["Node"]),
            E.child_object_id(node_instance_id)
        )
    )
    
    lpf_data = (
        E.t_data(
            etree.Comment("Load participation factor for {0}".format(row["load_area"])),
            E.data_id(generators["data"].next()),
            E.membership_id(system_node_member_id),
            E.property_id(property_ids["Load Participation Factor"]), # FIX
            E.value("1"), # Always 100% load participation in its region
            E.uid(generators["uid"].next())
        )
    )

    
    nodes.append(node)
    regions.append(region)
    memberships.append(region_membership)
    memberships.append(system_membership)
    data.append(lpf_data)
    
node_xml = "".join(map(xml_tostring, nodes))
region_xml = "".join(map(xml_tostring, regions))
membership_xml = "".join(map(xml_tostring, memberships))
print node_xml, region_xml, membership_xml
