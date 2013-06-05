#!/usr/bin/python
# encoding: utf8

# Parse the t_class and t_collection names into ids so we can sanely look them up.

import itertools, os, sys
from lxml import etree

from util import *

NO_NAMESPACES = ' xmlns="http://tempuri.org/MasterDataSet.xsd"'
TEMPLATE_FILE = "template.xml"

verbatim = [
    "t_category",
    "t_class",
    "t_collection",
    "t_collection_report",
    "t_property",
    "t_property_group",
    "t_property_report",
    "t_attribute",
    "t_attribute_data",
    # "t_band",
    "t_config",
    "t_report",
    "t_message",
    "t_unit"
]

template = None
class_ids, collection_ids, property_ids = uninit, uninit, uninit

def parse_id():
    global template, class_ids, collection_ids, property_ids
    # We'll refer to t_classes by name for sanity...
    # definitions = map_dict(lambda name: etree.parse(open(os.path.join("templates", name + ".xml"))), definitions)
    
    template = etree.XML(open(TEMPLATE_FILE).read().replace(NO_NAMESPACES, ""))
    
    # Automatically get the class_ids.
    class_ids = dict(zip(\
        typed_name_to_id(template, "t_class", requested_child = "name"), \
        typed_name_to_id(template, "t_class", requested_child = "class_id")))
    
    # Automatically get the collection ids.
    collection_ids = list(itertools.permutations(class_ids.keys(), 2))
    collection_ids = map_dict( \
        lambda relation_tuple: typed_name_to_id(template, "t_collection", **dict(zip(("where_parent_class_id", "where_child_class_id"), map(lambda class_name: class_ids[class_name], relation_tuple)))), \
        collection_ids)
        
    # Remove collections that don't exist.
    collection_ids = {k: v for k, v in collection_ids.items() if v is not ""}

    # Now try to guess the most probable collection.
    for k, v in {k: v for k, v in collection_ids.items() if type(v) == list}.items():
        # Try making a plural of the name of the child of the collection
        plural = k[1] + "s"
        # print plural
        maybe = typed_name_to_id(template, "t_collection", where_name = plural, where_parent_class_id = class_ids[k[0]], where_child_class_id = class_ids[k[1]])
        if maybe != "":
            print >> sys.stderr, "Warning: ambiguous collection for", k, ", guessing collection", maybe, "(", plural, ")"
            collection_ids[k] = maybe
        # Too complicated (usually it has importing/exporting or buying/selling. Hope we don't get called on.
        else:
            print >> sys.stderr, "Warning: ambiguous collection for", k, ", not adding"
            del collection_ids[k]

    # For now we're really only interested in this property.
    property_ids = {
        "Load Participation Factor": typed_name_to_id(template, "t_property", where_name = "Load Participation Factor", where_collection_id = collection_ids[("System", "Node")])
    }
    
def emit_verbatim():
    rv = ""
    for cls in verbatim:
        rv += "".join(map(lambda e: etree.tostring(e), template.xpath("//" + cls)))
    return rv