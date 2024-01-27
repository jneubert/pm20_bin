#!/bin/sh
# nbt, 10.8.2018

# use results from rebuild_all_data.sh and extract additional
# data from wikidata to rebuild the pm20 sparql endpoint

set -e

ENDPOINT=http://localhost:3030/pm20
WD_GRAPH=http://zbw.eu/beta/wikidata/ng
QUERY_DIR=/opt/sparql-queries/pm20
RDF_DIR=/opt/pm20x/var/rdf
MAPPING_ROOT=/opt/pm20x/var/mapping/

cd /opt/pm20x/bin

# drop all graphs
curl --silent -X POST -H "Content-type: application/sparql-update" \
    --data-binary "DROP ALL" $ENDPOINT/update


# load vocabulary graphs
for vocab in gk na pr sk geo subject ware ; do
  vocab_graph=http://zbw.eu/beta/$vocab/ng

  # load vocab
  file=$RDF_DIR/${vocab}.skos.ttl
  curl --silent --show-error -X POST -H "Content-type: text/turtle" \
    --data-binary @$file $ENDPOINT/data?graph=$vocab_graph > /dev/null
  ## load zbwext vocab to provide field labels for Skosmos
  curl --silent --show-error -X POST -H "Content-type: application/rdf+xml" \
    --data-binary @/opt/thes/var/stw/zbw-extensions/zbw-extensions.rdf $ENDPOINT/data?graph=$vocab_graph > /dev/null
done

# drop and reload default graph with pm20 rdf
##curl --silent --show-error -X DELETE $ENDPOINT/data?default
curl --silent --show-error -X POST -H "Content-type: text/turtle" \
  --data-binary @$RDF_DIR/pm20.ttl $ENDPOINT/data > /dev/null

# load categories (now part of the default graph!)
# TODO Re-think, if categories should be integrated into the default graph.
# If so, the default graph becomes too complex to transform into framed jsonld.
# On the other hand, integrating would allow querying categories from Wikidata
# (without GRAPH clause).
# For now, deactivated
#for category_type in geo subject ware ; do
#  file=$RDF_DIR/${category_type}.skos.ttl
#  curl --silent --show-error -X POST -H "Content-type: text/turtle" \
#    --data-binary @$file $ENDPOINT/data > /dev/null
#done

# add rdfs:labels for text indexing
curl --silent --show-error -X POST -H "Content-type: application/sparql-update" \
    --data-binary @/opt/sparql-queries/add_rdfs_labels.ru $ENDPOINT/update > /dev/null

# add top concepts
# TODO additionally on default graph
curl --silent --show-error -X POST -H "Content-type: application/sparql-update" \
    --data-binary @$QUERY_DIR/insert_top_concepts.ru $ENDPOINT/update > /dev/null

# add external links from vocab graphs redundantly to default graph for WD
# TODO still necessary?
curl --silent --show-error -X POST -H "Content-type: application/sparql-update" \
    --data-binary @$QUERY_DIR/insert_vocab_links.ru $ENDPOINT/update > /dev/null


# insert folder counts - requieres loaded pm20 dataset
# TODO refactor
curl --silent -X POST -H "Content-type: application/sparql-update" \
    --data-binary @$QUERY_DIR/insert_folder_count_per_concept.ru $ENDPOINT/update #> /dev/null


# create WD graph for easy access to an extract of WD

# get wikidata extract for linked folders (splitted to avoid timeout)
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_links_extract.rq https://query.wikidata.org/sparql \
  > $RDF_DIR/wd_links_extract.ttl
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_geo_subject_codes.rq https://query.wikidata.org/sparql \
  > $RDF_DIR/wd_geo_subject_code.ttl
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_info_extract.rq https://query.wikidata.org/sparql \
  > $RDF_DIR/wd_info_extract.ttl

# get category mappings as SKOS
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_category_mappings.rq $ENDPOINT/query \
  > $RDF_DIR/wd_category_mappings.ttl

# get wikidata folder mapping as SKOS
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_folder_mapping.rq $ENDPOINT/query \
  > $RDF_DIR/wd_folder_mapping.ttl

# get wd page counts
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_page_count.rq https://query.wikidata.org/sparql \
  > $RDF_DIR/wd_page_count.ttl

# get persons life data
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$QUERY_DIR/construct_wd_life.rq https://query.wikidata.org/sparql \
  > $RDF_DIR/wd_life.ttl

# complex way to get all WD labels for mapped concepts
# (federated query to WD endpoint does not work because
# it would have to use a graph clause, which is forbidden)

# create list of all QIDs
# (skip first heading line (?qid)
curl --silent -X POST \
  -H "Content-type: application/sparql-query" \
  -H "Accept: text/tab-separated-values; charset=utf-8" \
  --data-binary @$QUERY_DIR/voc_wd_qid.rq \
  http://zbw.eu/beta/sparql/pm20/query \
  | sed "1d" \
  > $RDF_DIR/voc_wd_qid.tsv

# create query
extended_query=/tmp/construct_wd_voc_mapping_labels.rq
perl replace_values_list.pl \
  $QUERY_DIR/construct_wd_voc_mapping_labels.rq \
  $RDF_DIR/voc_wd_qid.tsv \
  > $extended_query

# get wd labels
curl --silent --show-error -X POST -H "Content-type: application/sparql-query" -H "Accept: text/turtle" \
  --data-binary @$extended_query https://query.wikidata.org/sparql \
  > $RDF_DIR/wd_voc_mapping_labels.ttl


# load wikidata graph
for file in wd_links_extract.ttl wd_info_extract.ttl wd_page_count.ttl wd_life.ttl wd_category_mappings.ttl wd_folder_mapping.ttl wd_voc_mapping_labels.ttl wd_geo_subject_code.ttl ; do
 curl --silent --show-error -X POST -H "Content-type: text/turtle" \
    --data-binary @$RDF_DIR/$file $ENDPOINT/data?graph=$WD_GRAPH > /dev/null
done

# insert Wikidata folder mapping into default graph
curl --silent --show-error -X POST -H "Content-type: application/sparql-update" \
    --data-binary @$QUERY_DIR/insert_wd_mapping.ru $ENDPOINT/update #> /dev/null

# insert Wikidata category mapping into vocab graphs and default graph
curl --silent --show-error -X POST -H "Content-type: application/sparql-update" \
    --data-binary @$QUERY_DIR/insert_wd_mapping_categories.ru $ENDPOINT/update #> /dev/null

# insert subject category notations into default graph

# TODO q&d Workarround: load SK mapping data to WD into default graph
# in order to allow federaed queries from WD without graph clauses
curl --silent --show-error -X POST -H "Content-type: text/turtle" \
  --data-binary @$RDF_DIR/sk.skos.ttl $ENDPOINT/data?graph=default > /dev/null
curl --silent --show-error -X POST -H "Content-type: text/turtle" \
  --data-binary @$MAPPING_ROOT/sk_wd/sk_wd.ttl $ENDPOINT/data?graph=default > /dev/null

# load mnm catalogs
##for catalog in 622 623 ; do
##  /usr/bin/perl /opt/sparql-queries/bin/mnm2graph.pl pm20 $catalog > /dev/null
##done

