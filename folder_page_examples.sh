#!/bin/bash

# examples for folder pages (particulary re. film sections)

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

  # Einzelne Krankheiten : Deutschland
  "sh/126128,144265"

  # Kohle : Chile
  "wa/143120,141691"
)

for folder in "${docs[@]}" ; do 
  echo https://pm20.zbw.eu/folder/$folder
  perl create_folder_pages.pl $folder ##> /dev/null
  make -C ../web SET=$folder > /dev/null
done
