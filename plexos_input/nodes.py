#!/usr/bin/python
# encoding: utf8

# We'll try to hew to TemplateForSwitch.xml first...

import csv
from lxml import etree
from lxml.builder import E

def succ():
    _ = 0
    while True:
        yield str(_)
        _ += 1
succ = succ()

def typed_name_to_id(xml, xml_type, name):
    _ = xml.xpath("//{xml_type}[name='{name}']/class_id/text()".format(xml_type = xml_type, name = name))
    return  "".join(_)

# We'll refer to t_classes by name for sanity...
classes_collections = etree.parse(open("templates/classes_collections.xml"))

# Creating nodes
# Not sure about categories for now. We will not include them

LOAD_AREAS = "../AMPL/inputs/load_areas.tab"

areas = open(LOAD_AREAS, "rb").readlines()[1:]
parsed = csv.DictReader(areas, delimiter = "\t")
class_id = typed_name_to_id(classes_collections, "t_class", "Node")

nodes = []
for row in parsed:
    node = (
        E.t_object(
            E.object_id(succ.next()),
            E.class_id(class_id),
            E.name(row["load_area"]),
            E.description(row["load_area"])
        )
    )
    nodes.append(node)
    # print etree.tostring(node, pretty_print = True)

node_xml = "".join(map(lambda node: etree.tostring(node, pretty_print = True), nodes))
print node_xml
    

    


