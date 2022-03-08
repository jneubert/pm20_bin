#!/bin/sh
# 22.2.2018

# Get all document images from the PM20 file system - use "*_A.JPG" as indicator

DOCIMAGEROOT=/pm20/folder

for collection in co pe sh wa ; do
  output=/pm20/data/imagedata/${collection}_image.lst
  echo "$output"
  # follow symlinks - necessary for co folders linked to A and F directories
  find -L $DOCIMAGEROOT/$collection -name "*_A.JPG" > $output
done
