#!/bin/sh

for folder in "co/041780" "co/014709"   "co/048852"  "co/009737" ; do
  echo folder https://purl.org/pressemappe20/folder/$folder ...
  perl create_folder_pages.pl $folder ##> /dev/null
  make -C ../web SET=$folder > /dev/null
done
