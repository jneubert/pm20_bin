#!/bin/sh

for folder in "pe/000010" "pe/000012" "co/019784" "sh/141113,161612" ; do
  echo folder https://pm20.zbw.eu/iiifview/folder/$folder ...
  perl create_iiif_img.pl $folder
  perl create_iiif_manifest.pl $folder
done
