#!/usr/bin/env python
# encoding: utf8

import sys
from lxml import etree

# Attempt to give some comments to this damn file.

NO_NAMESPACES = ' xmlns="http://tempuri.org/MasterDataSet.xsd"'
TEMPLATE_FILE = sys.argv[1]

t = etree.XML(open(TEMPLATE_FILE).read().replace(NO_NAMESPACES, ""))

# Parsing.

classes = {}
for e in t.xpath("//t_class"):
    classes[e.find("class_id").text] = e.find("name").text
    
collections = {}
for e in t.xpath("//t_collection"):
    collections[e.find("collection_id").text] = e.find("name").text
    
objects = {}
for e in t.xpath("//t_object"):
    objects[e.find("object_id").text] = e.find("name").text


# Annotating.
    
for e in t.xpath("//t_object"):
    clsid = e.find("class_id")
    cls = classes[clsid.text]
    e.insert(list(e).index(clsid), etree.Comment("class " + cls))
    
for e in t.xpath("//t_collection"):
    parent_clsid = e.find("parent_class_id")
    child_clsid = e.find("child_class_id")
    parent_cls = classes[parent_clsid.text]
    child_cls = classes[child_clsid.text]
    e.insert(list(e).index(parent_clsid), etree.Comment("class " + parent_cls))
    e.insert(list(e).index(child_clsid), etree.Comment("class " + child_cls))
    
for e in t.xpath("//t_membership"):
    parent_clsid = e.find("parent_class_id")
    child_clsid = e.find("child_class_id")
    parent_cls = classes[parent_clsid.text]
    child_cls = classes[child_clsid.text]
    e.insert(list(e).index(parent_clsid), etree.Comment("class " + parent_cls))
    e.insert(list(e).index(child_clsid), etree.Comment("class " + child_cls))
    
    parent_objid = e.find("parent_object_id")
    child_objid = e.find("child_object_id")
    parent_obj = objects[parent_objid.text]
    child_obj = objects[child_objid.text]
    e.insert(list(e).index(parent_objid), etree.Comment("object " + parent_obj))
    e.insert(list(e).index(child_objid), etree.Comment("object " + child_obj))
    
    collid = e.find("collection_id")
    coll = collections[collid.text]
    e.insert(list(e).index(collid), etree.Comment("collection " + coll))

for e in t.xpath("//t_attribute"):
    clsid = e.find("class_id")
    cls = classes[clsid.text]
    e.insert(list(e).index(clsid), etree.Comment("class " + cls))
    
for e in t.xpath("//t_property"):
    collid = e.find("collection_id")
    coll = collections[collid.text]
    e.insert(list(e).index(collid), etree.Comment("collection " + coll))
    
print etree.tostring(t)