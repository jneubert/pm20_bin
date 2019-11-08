#!/bin/bash
# nbt, 08.11.2019

# Generate file from .md

input_file="$1"
if [ ! -f "$input_file" ]; then
  echo input file $input_file missing
  exit
fi

output_file=$(dirname $input_file)/$(basename $input_file .md).html

pandoc -s --data-dir /disc1/pm20/web.public/pandoc --css /styles/simple.css -t html+pipe_tables $input_file -o $output_file
