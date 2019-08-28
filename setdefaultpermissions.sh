#!/bin/sh
# nbt, 21.8.2019

# Set default file and directory protection to 
#   drwxrwxr-x 1 {user} zbw    {directory}
#   -rw-rw-r-- 1 {user} zbw    {file}

set -e

USER=`whoami`
GROUP=zbw

chown -R $USER:$GROUP .

find . -type d -exec chmod 0775 {} \;
find . -type f -exec chmod 0664 {} \;

