#!/bin/bash

# examples for folder pages (particulary re. film sections)

docs=(
  # Bergedorfer Eisenwerk - folder + filming 2
  "co/041780"

  # La Fondiaria Vita - filming 1 + filming 2
  "co/014709"

  # General Motors - multiple entries filming 1, unkwon filming 2
  "co/009737"

  # 20th Century Fox (material 1944 - 2005) - perhaps filming 1, perhaps
  # filming 2, perhaps microfiche
  "co/025488"

  # United States Borax and Chemical (material 1956-1996) - perhaps
  # filming 2, perhaps microfiche
  "co/069327"

  # 600 Group Ltd. (material from 1975 on) - perhaps microfiche
  "co/022329"

  # Google (material from 2001 on) - only metadata
  "co/010206"

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
