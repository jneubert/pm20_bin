#!/bin/sh
# nbt, 2020-02-17

# to be invoked from ite-srv24

BASE_DIR=/pm20

export PERL5LIB=/opt/perllib:/opt/perl5/lib/perl5

cd $BASE_DIR/bin
perl create_filmlists.pl > /dev/null

cd $BASE_DIR/web
make > /dev/null

