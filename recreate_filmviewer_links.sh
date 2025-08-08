#!/bin/sh
# nbt, 2020-02-17

# create all link snippets for filmviewer

BASE_DIR=/pm20
LOG_DIR=$BASE_DIR/web/tmp/film_meta

cd $BASE_DIR/bin

for subset in h1_sh h1_co h1_wa h2_co h2_sh h2_wa ; do
  perl create_filmviewer_links.pl $subset > $LOG_DIR/create_filmviewer_links.$subset.log 2>&1
done

