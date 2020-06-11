#!/bin/sh
# nbt, 11.6.2020

# create markdown and html files for public film sections
# (run after any update in the film directory)

set -e

DIR=/disc1/pm20

cd $DIR/bin
perl img_to_public.pl h1/sh

cd $DIR/web.intern
make

cd $DIR/web.public
make


