#!/bin/sh
# nbt, 2024-05-17

# Load prepared data files into the PM20 endpoint
# (contains also "historically related" graphs from economics)

# has to be executed on ite-srv36 (? - the machine which is running the endpoint)

ENDPOINT=http://127.0.0.1:3030/pm20
RDF_DIR=/pm20/data/rdf

# TODO stop fuseki, remove directory, start fuseki

# load default graph with pm20 and film rdf
curl --silent --show-error -X POST -H "Content-type: application/ld+json" \
  --data-binary @$RDF_DIR/pm20.extended.jsonld $ENDPOINT/data > /dev/null
curl --silent --show-error -X POST -H "Content-type: application/ld+json" \
  --data-binary @$RDF_DIR/film.jsonld $ENDPOINT/data > /dev/null

# load vocabulary graphs for pm20 categories
for vocab in geo subject ware ; do
  vocab_graph=http://zbw.eu/beta/$vocab/ng

  # load vocab
  file=$RDF_DIR/${vocab}.skos.extended.jsonld
  curl --silent --show-error -X POST -H "Content-type: application/ld+json" \
    --data-binary @$file $ENDPOINT/data?graph=$vocab_graph > /dev/null
done

# load static "historical" data
for vocab in gk na pr sk ; do
  vocab_graph=http://zbw.eu/beta/$vocab/ng

  # load vocab
  file=$RDF_DIR/static_from_ifis/${vocab}.skos.ttl
  curl --silent --show-error -X POST -H "Content-type: text/turtle" \
    --data-binary @$file $ENDPOINT/data?graph=$vocab_graph > /dev/null
  ## load zbwext vocab to provide field labels for Skosmos
  curl --silent --show-error -X POST -H "Content-type: application/rdf+xml" \
    --data-binary @/opt/thes/var/stw/zbw-extensions/zbw-extensions.rdf $ENDPOINT/data?graph=$vocab_graph > /dev/null
done


