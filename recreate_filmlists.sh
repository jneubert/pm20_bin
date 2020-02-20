#!/bin/sh
# nbt, 2020-02-17

# to be invoked from ite-srv24

BASE_DIR=/disc1/pm20

export PERL5LIB=/opt/perllib:/opt/perl5/lib/perl5

cd $BASE_DIR/bin
perl create_filmlists.pl 2>&1 /dev/null

cd $BASE_DIR/web.intern
make > /dev/null

cd $BASE_DIR/web.public
make > /dev/null

