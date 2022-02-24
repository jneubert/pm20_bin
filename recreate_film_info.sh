#!/bin/sh
# nbt, 2020-02-17

# to be invoked from ite-srv24
# now includes zotero eval and creation of filmviewer links

BASE_DIR=/pm20
LOG_DIR=$BASE_DIR/web/tmp/film_meta

export PERL5LIB=/opt/perllib:/opt/perl5/lib/perl5

cd $BASE_DIR/bin
perl create_filmlists.pl > $LOG_DIR/create_filmlists.log 2>&1

SUBSET=h1_sh
perl read_zotero.pl $SUBSET  > $LOG_DIR/read_zotero.$SUBSET.log 2>&1
perl create_filmviewer_links.pl $SUBSET > $LOG_DIR/create_filmviewer_links.$SUBSET.log 2>&1

cd $BASE_DIR/web
make > /dev/null

