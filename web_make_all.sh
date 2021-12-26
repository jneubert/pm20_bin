#!/bin/sh

# make all .md files of the PM20 web site
# (execute different find command for parts of the website - find everything
# from root is too large)

make -C /pm20/web
make -C /pm20/web SET=category
make -C /pm20/web SET=pe
make -C /pm20/web SET=co
make -C /pm20/web SET=sh
make -C /pm20/web SET=wa

