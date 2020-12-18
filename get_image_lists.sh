#!/bin/sh
# 22.2.2018

# Get all images from the PM20 file systems - use "*_A.JPG" as indicator

# VIA SMB SHARES, VERY TIME CONSUMING

find /mnt/digidata/P -name "*_A.JPG" >  ../var/imagedata/pe_image.lst
find /mnt/inst/F     -name "*_A.JPG" > ../var/imagedata/co_image.lst
find /mnt/pers/A     -name "*_A.JPG" >> ../var/imagedata/co_image.lst
find /mnt/sach/S     -name "*_A.JPG" >  ../var/imagedata/sh_image.lst
find /mnt/ware/W     -name "*_A.JPG" >  ../var/imagedata/wa_image.lst
