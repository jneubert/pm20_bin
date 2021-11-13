#!/bin/sh

# extract example records from complete jsonld file

jq '{
    "@context": {"@context"},
    "@graph":[
      ."@graph"[] | select(.identifier as $a | ["pe/005823", "co/041389", "sh/126128,144265", "wa/143120,141691" ] | index($a) )
    ]
  }' ../data/rdf/pm20.extended.jsonld

