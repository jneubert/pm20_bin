#!/bin/sh
# nbt, 2024-01-16

# Dump the content of the PM20 endpoint
# (contains also "historically related" graphs from economics)

ENDPOINT=https://zbw.eu/beta/sparql/pm20/get
DOWNLOAD_DIR=/pm20/web/download

# everything in endpoint
curl --silent -X GET -H "Accept: application/n-quads" $ENDPOINT -o $DOWNLOAD_DIR/pm20_endpoint_all.nq

# default graph
curl --silent -X GET $ENDPOINT -o $DOWNLOAD_DIR/pm20.dump.ttl
curl --silent -X GET -H "Accept: application/ld+json" $ENDPOINT -o $DOWNLOAD_DIR/pm20.dump.jsonld

# pm20 vocab graphs
for vocab in geo ware subject na sk pr wikidata ; do
  curl --silent -X GET $ENDPOINT?graph=http://zbw.eu/beta/$vocab/ng -o $DOWNLOAD_DIR/$vocab.dump.ttl
  curl --silent -X GET -H "Accept: application/ld+json" $ENDPOINT?graph=http://zbw.eu/beta/$vocab/ng -o $DOWNLOAD_DIR/$vocab.dump.jsonld
done

