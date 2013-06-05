#!/usr/bin/python
# encoding: utf8

from lxml import etree

xml_tostring = lambda node: etree.tostring(node, pretty_print = True)

class _uninit(object):
    def __getitem__(self, item):
        raise Exception("Object not initialized yet")
uninit = _uninit()   

def succ(start = 1):
    _ = start
    while True:
        yield str(_)
        _ += 1
        
def map_dict(fn, iter):
    return dict(zip(iter, map(fn, iter)))
    
# Find in `xml` the element of type `xml_type` which has the child `<name>name</name>` 
# and possibly other constraints `where_(child attribute name)`, and return the value of the child node
# `requested_child`, which defualts to `(xml_type)_id` (t_object -> object_id).
def typed_name_to_id(xml, xml_type, requested_child = None, **where):
    if requested_child is None and xml_type[:2] == "t_":
        requested_child = xml_type[2:] + "_id"
        
    xpath_constraints = []
    for k, v in where.items():
        if k[:6] == "where_":
            xpath_constraints.append("{attribute}='{value}'".format(attribute = k[6:], value = v))
    xpath_constraint = " and ".join(xpath_constraints)
    xpath_constraint = "[" + xpath_constraint + "]" if xpath_constraint != "" else xpath_constraint
    
    xpath = "//{xml_type}{constraint}/{requested_child}/text()".format(
        xml_type = xml_type, constraint = xpath_constraint, requested_child = requested_child)
    # print xpath   
    _ = xml.xpath(xpath)

    if len(_) > 1:
        return _
    return "".join(_)