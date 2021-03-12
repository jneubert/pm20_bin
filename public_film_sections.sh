#!/bin/sh
# nbt, 11.6.2020

# create markdown and html files for public film sections
# (run after any update in the film directory)

set -e

DIR=/pm20

# recreate symlinks and markdown overview files
cd $DIR/bin
perl img_to_public.pl h1/sh

# update html
cd $DIR/web
make

