#!/bin/bash

docs=(
  # Bergedorfer Eisenwerk - folder + filming 2
  "co/041780"

  # La Fondiaria Vita - filming 1 + filming 2
  "co/014709"

  # General Motors - multiple entries filming 1, unkwon filming 2
  "co/009737"

  # Abbe - person without film
  "pe/000012"

  # Putin - metadata only
  "pe/013927"
)

for folder in "${docs[@]}" ; do 
  echo https://purl.org/pressemappe20/folder/$folder ...
  perl create_folder_pages.pl $folder ##> /dev/null
  make -C ../web SET=$folder > /dev/null
done
