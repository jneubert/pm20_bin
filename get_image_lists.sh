#!/bin/sh
# 22.2.2018

# Get all images from the PM20 file systems - use "*_A.JPG" as indicator

find /pm20/folder/pe -name "*_A.JPG" >  /pm20/data/imagedata/pe_image.lst
find /pm20/folder/sh -name "*_A.JPG" >  /pm20/data/imagedata/sh_image.lst
