#!/bin/sh
# nbt, 28.2.2018

# recreate all PM20 METS and doc count beacon data

# stop at error
set -e

cd /opt/pm20x/bin
##echo "`date "+%F %T"` start"

### SKIP on ite-srv24
### OBSOLETE - authoritative version of the file system on pm20.zbw.eu
if false; then

# Traverse filesystem for image files
# EXPENSIVE
./get_image_lists.sh

# Parse for filenames and paths
/usr/bin/perl parse_imagelists.pl

# Read .txt files and extract document data
# (created beacons with document counts, too)
# EXPENSIVE
###/usr/bin/perl parse_docdata.pl

# Copy IFIS .dat files and parse them
cp -p /mnt/pm20/4Do/???.dat ../var/dat/src/
chmod 664 ../var/dat/src/*
/usr/bin/perl parse_dat.pl

# Create all mets files
# (uses all of the former)
## OBSOLETE - replace by version on pm20

### END SKIP
fi

# get most current docdata files from pm20 server
scp -pq nbt@213.183.195.106:/pm20/data/docdata/??_docdata.json ../var/docdata
scp -pq nbt@213.183.195.106:/pm20/data/docdata/??_stats.json ../var/docdata


# create rdf output
# TODO temporarily, concatenate results from old and new script
##/usr/bin/perl create_rdf.pl > /tmp/pm20a.ttl 2> /dev/null
##/usr/bin/perl create_rdf1.pl > /tmp/pm20b.ttl 2> /dev/null
##cat /tmp/pm20a.ttl /tmp/pm20b.ttl > ../var/rdf/pm20.ttl
/usr/bin/perl create_rdf1.pl > ../var/rdf/pm20.ttl 2> /dev/null
##echo "`date "+%F %T"` done create pm20 rdf"

# create skos vocabularies
# (rebuild_exception_lists.sh already runs hourly)
/usr/bin/perl create_skos.pl
##echo "`date "+%F %T"` done create skos"

# copy vocabulary map files for apache to pm20 server
scp -pq ../var/klassdata/ag_map.txt nbt@pm20:/disc1/pm20/data/url_map/geo_sig2id.txt
scp -pq ../var/klassdata/je_map.txt nbt@pm20:/disc1/pm20/data/url_map/subject_sig2id.txt
scp -pq ../var/klassdata/ip_map.txt nbt@pm20:/disc1/pm20/data/url_map/ware_sig2id.txt
##echo "`date "+%F %T"` done copy map files"

# copy rdf content to sparql server
for file in pm20.ttl geo.skos.ttl subject.skos.ttl ware.skos.ttl ; do
  scp -pq ../var/rdf/$file nbt@ite-srv26:/opt/pm20x/var/rdf
done
##echo "`date "+%F %T"` done copy rdf"

# recreate sparql endpoint (and extend data)
ssh nbt@ite-srv26 "cd /opt/pm20x/bin ; ./recreate_pm20_endpoint.sh"
# TODO reset git-controlled var data
##echo "`date "+%F %T"` done recreate endpoint"


# dump all RDF from endpoint (with all extensions)
# (must be executed on remote machine, to have endpoint directly accessible)
ssh ite-srv26 'curl --silent -X GET -H "Accept: text/turtle" http://localhost:3030/pm20/get?graph=default' > ../var/rdf/pm20.extended.ttl
# TODO remvoe ag je ip (which work on stale copies)
for vocab in geo subject ware ; do
  vocab_graph=http://zbw.eu/beta/$vocab/ng
  ssh ite-srv26 "curl --silent -X GET -H \"Accept: text/turtle\" http://localhost:3030/pm20/get?graph=$vocab_graph" > ../var/rdf/${vocab}.skos.extended.ttl
done
##echo "`date "+%F %T"` done dump rdf"

# convert to jsonld
# TODO remvoe ag je ip (which work on stale copies)
for vocab in geo subject ware ; do
  input=../var/rdf/${vocab}.skos.extended.ttl
  # prepend with defined prefixes for control of jsonld conversion
  sed -i '1s;^;@prefix zbwext: <http://zbw.eu/namespaces/zbw-extensions/> \.\n;' $input
  sed -i '1s;^;@prefix skos: <http://www.w3.org/2004/02/skos/core#> \.\n;' $input
  /opt/jena/bin/riot --output=jsonld $input > ../var/rdf/${vocab}.skos.extended.jsonld
done
##echo "`date "+%F %T"` done riot convert skos.extended.ttl to .jsonld"

# GET as jsonld is much faster than transformation with riot
##JVM_ARGS="-Xms4g" /opt/jena/bin/riot --output=jsonld ../var/rdf/pm20.extended.ttl > ../var/rdf/pm20.interim.jsonld
ssh ite-srv26 'curl --silent -X GET -H "Accept: application/ld+json" http://localhost:3030/pm20/get?graph=default' > ../var/rdf/pm20.interim.jsonld
##echo "`date "+%F %T"` done get pm20.interim.jsonld"

# transformation via PyLD (instead of php jsonld) extends subordinated nodes
##/usr/bin/php -d memory_limit=6G -f transform_jsonld.php > ../var/rdf/pm20.extended.jsonld
# PyLD needs at least Python 3.6. rh scl environment has to be started
scl enable rh-python36 - << \EOF
source /home/nbt/pydev/py36-venv/bin/activate
cd /opt/pm20x/bin
python3 transform_jsonld.py frame_folder > ../var/rdf/pm20.extended.jsonld
##python3 transform_jsonld.py frame_category > ../var/rdf/category.extended.jsonld
EOF
##echo "`date "+%F %T"` transform_jsonld.py done "


# copy extended rdf content to pm20 server
for file in pm20.extended.ttl pm20.extended.jsonld geo.skos.extended.ttl subject.skos.extended.ttl ware.skos.extended.ttl geo.skos.extended.jsonld subject.skos.extended.jsonld ware.skos.extended.jsonld ; do
  scp -pq ../var/rdf/$file nbt@pm20:/disc1/pm20/data/rdf
done
##echo "`date "+%F %T"` done copy extended rdf"


# create and copy sparql results to pm20 server
# (both scripts based on sparql_results.yaml)
/usr/bin/perl mk_sparql_results.pl
/usr/bin/perl cp_reports.pl
# copy configuration to pm20 server
scp -pq sparql_results.yaml nbt@213.183.195.106:/pm20/bin
##echo "`date "+%F %T"` done make+copy sparql results"


##echo "`date "+%F %T"` end"


