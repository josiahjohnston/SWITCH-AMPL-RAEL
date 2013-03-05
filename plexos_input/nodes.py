#!/usr/bin/python
# encoding: utf8

# We'll try to hew to TemplateForSwitch.xml first...

import csv, sys, itertools
from itertools import islice
from lxml import etree
from lxml.builder import E

def succ(start = 0):
    _ = start
    while True:
        yield str(_)
        _ += 1
        
# We could stick to one global generator, but let's not.
generators = ["object", "membership"]
generators = dict(zip(generators, map(lambda _: succ(), generators)))
# Add here ids that need to start from some value

xml_tostring = lambda node: etree.tostring(node, pretty_print = True)

def typed_name_to_id(xml, xml_type, name, requested_child = None):
    # Set requested_child as {type}_id unless we're asked otherwise
    if requested_child is None and xml_type[:2] == "t_":
        requested_child = xml_type[2:] + "_id"
    _ = xml.xpath("//{xml_type}[name='{name}']/{child}/text()".format(xml_type = xml_type, name = name, child = requested_child))
    return "".join(_)
    
# Is this even necessary? Maybe we should just write out the xpath, if it's a one time thing...
def typed_collection_relations_to_id(xml, xml_type, name, parent, child):
    _ = xml.xpath("//{xml_type}[name='{name}' and parent_class_id='{parent}' and child_class_id='{child}']/collection_id/text()".format(
        xml_type = xml_type, name = name, parent = parent, child = child))
    return "".join(_)
    
# We'll refer to t_classes by name for sanity...
classes_collections = etree.parse(open("templates/classes_collections.xml"))

# Creating nodes
# Not sure about categories for now. We will not include them
# Do we want to keep collection definitions static? For now, generate only memberships

LOAD_AREAS = "../AMPL/inputs/load_areas.tab"

areas = open(LOAD_AREAS, "rb").readlines()[1:]
parsed = csv.DictReader(areas, delimiter = "\t")

node_class_id = typed_name_to_id(classes_collections, "t_class", "Node")
region_class_id = typed_name_to_id(classes_collections, "t_class", "Region")
membership_collection_id = typed_collection_relations_to_id(classes_collections, "t_collection", "Region", node_class_id, region_class_id)

nodes = []
regions = []
memberships = []

for row in parsed:
    (node_instance_id, region_instance_id) = islice(generators["object"], 2)
    node = (
        E.t_object(
            E.object_id(node_instance_id),
            E.class_id(node_class_id),
            E.name(row["load_area"]),
            E.description(row["load_area"])
        )
    )
    region = (
        E.t_object(
            E.object_id(region_instance_id),
            E.class_id(region_class_id),
            E.name("Region for " + row["load_area"]),
            E.description("Region for " + row["load_area"])
        )
    )
    # For some reason it's reversed and the node is the parent and the region is the child.
    membership = (
        E.t_membership(
            etree.Comment("Node to region membership for {0}".format(row["load_area"])),
            E.membership_id(generators["membership"].next()),
            E.parent_class_id(node_class_id),
            E.parent_object_id(node_instance_id),
            E.collection_id(membership_collection_id), # FIXME
            E.child_class_id(region_class_id),
            E.child_object_id(region_instance_id)
        )
    )
    nodes.append(node)
    regions.append(region)
    memberships.append(membership)
    
node_xml = "".join(map(xml_tostring, nodes))
region_xml = "".join(map(xml_tostring, regions))
membership_xml = "".join(map(xml_tostring, memberships))
print node_xml, region_xml, membership_xml
