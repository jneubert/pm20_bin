#!/bin/bash
# nbt, 2024-06-07

# Remove the Fuseki TDB database directory for pm20

set -eo pipefail

DATASET=pm20
TDB_DIR=/var/lib/fuseki/databases/$DATASET
BAK_DIR=${TDB_DIR}.bak

# stop fuseki (calls sudo)
fuseki_service.sh stop

if [ -d $BAK_DIR ]; then
  echo "  remove $BAK_DIR"
  sudo rm -rf $TDB_DIR.bak
fi
if [ -d $TDB_DIR ]; then
  echo "  move $TDB_DIR to $BAK_DIR"
  sudo mv $TDB_DIR $BAK_DIR
fi

# new directory is created by fuseki
fuseki_service.sh start
