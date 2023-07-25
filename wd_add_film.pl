#!/bin/perl
# nbt, 2023-07-21

# create quickstatements for adding film section properties to Wikidata items

# for now (companies), we assume that all items already exist

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use REST::Client;
use WWW::Zotero;

binmode( STDOUT, ":utf8" );
$Data::Dumper::Sortkeys = 1;

Readonly my $FILMDATA_STUB  => '/pm20/data/filmdata/zotero.';
Readonly my $FILM_IMG_COUNT => path('/pm20/data/filmdata/img_count.json');

# TODO extend to other holdings beyond Hamburg and sh or co
# (currently set is not restricted to a certain filming (1/2))
Readonly my @VALID_SUBSETS => qw/ h1_sh h1_co h1_wa h2_co /;

my ( $provenance, $filming, $collection, $subset, %conf );
if ( $ARGV[0] and $ARGV[0] =~ m/(h|k)(1|2)_(co|sh|wa)/ ) {
  $provenance = $1;
  $filming    = $2;
  $collection = $3;
  $subset     = "$provenance${filming}_$collection";
}
if ( not( $subset and grep( /^$subset$/, @VALID_SUBSETS ) ) ) {
  usage();
  exit 1;
}

# items, keyed by qid
my $wd_item_ref = parse_zotero($subset);

# create and execute query, load wikidata qid list
my ( $wd_folder_ref, $wd_film_section_ref, $wd_label_ref ) =
  get_wikidata_items($wd_item_ref);

# iterate over
foreach my $qid ( sort keys %{$wd_item_ref} ) {

  # TODO remove restriction to test dataset
  ##if ( not grep( /$qid/, qw/ Q6392758 Q113577381 Q107102711 Q111719803 / ) ) {
  ##  next;
  ##}

  SECTION:
  foreach my $section_id ( sort keys %{ $wd_item_ref->{$qid} } ) {
    my $entry = $wd_item_ref->{$qid}->{$section_id};

    # TODO check if entry for $section_id already exists
    if ( $entry->{lr} ) {
      $section_id .= "/$entry->{lr}";
    }

    # skip already existing entries to avoid duplicates
    foreach my $existing_section ( @{ $wd_film_section_ref->{$qid} } ) {
      if ( $section_id eq $existing_section ) {
        next SECTION;
      }
    }

    print "$qid|P11822|\"$section_id\"|P1104|$entry->{number_of_images}";
    if ( $entry->{start_date} =~ m/^(\d{4}(-\d{2}(-\d{2})?)?)$/ ) {
      my $date;
      if ($3) {
        $date = "$1T00:00:00Z/11";
      } elsif ($2) {
        $date = "$1-00T00:00:00Z/10";
      } else {
        $date = "$1-00-00T00:00:00Z/9";
      }
      print "|P580|+$date";
    }
    print "|P528|\"$entry->{signature}\"";
    ##print "\n",  Dumper $wd_label_ref->{qid}, $entry;
    if ( not $wd_label_ref->{$qid}
      or ( lc( $entry->{company_string} ) ne lc( $wd_label_ref->{$qid} ) ) )
    {
      print "|P1810|\"$entry->{company_string}\"";
    }
    if ( $entry->{pm20Id} ) {
      print "|P4293|\"$entry->{pm20Id}\"";
    }
    print "\n";
  }
}

# ################################

sub parse_zotero {
  my $subset = shift or die "param mssing";

  my %film =
    %{ decode_json( path( $FILMDATA_STUB . "$subset.json" )->slurp ) };

  # Use qid as key for %wd_item
  my %wd_item;
  foreach my $film ( sort keys %film ) {
    foreach my $film_item_key ( sort keys %{ $film{$film}{item} } ) {
      my $film_item = $film{$film}{item}{$film_item_key};
      my $qid       = $film_item->{qid};
      $wd_item{$qid}{ $film_item->{id} } = $film_item;
    }
  }
  return \%wd_item;
}

sub get_wikidata_items {
  my $wd_item_ref = shift or die "param mssing";

  # retrieve info by SPARQL query
  my $query = <<EOF;
PREFIX wd: <http://www.wikidata.org/entity/>
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
PREFIX rdfs: <http://www.w3.org/2000/01/rdf-schema#>
#
SELECT ?wd ?qid ?pm20Id  ?pm20FilmSectionId ?label
WHERE {
  values (?wd) {
    #VALUES#
  }
  optional {
    ?wd rdfs:label ?labelDe .
    filter (lang(?labelDe) = 'de')
    ?wd rdfs:label ?labelEn .
    filter (lang(?labelEn) = 'en')
    bind (if(bound(?labelDe), str(?labelDe), str(?labelEn)) as ?label)
  }
  optional {
    ?wd wdt:P4293 ?pm20Id .
  }
  optional {
    ?wd wdt:P11822 ?pm20FilmSectionId .
  }
  bind(strafter(str(?wd), str(wd:)) as ?qid)
}
EOF
  my $qids;
  foreach my $qid ( keys %{$wd_item_ref} ) {
    $qids .= " (wd:$qid)";
  }
  $query =~ s/#VALUES#/$qids/ms;
  ##print $query; exit;

  my $endpoint = 'https://query.wikidata.org/sparql';
  my $client   = REST::Client->new;
  $client->POST(
    $endpoint,
    $query,
    {
      'Content-type' => 'application/sparql-query; charset=utf8',
      Accept         => 'application/sparql-results+json',
    }
  );

  if ( $client->responseCode ne '200' ) {
    warn "Could not execute query: ", $client->responseCode, "\n";
    return;
  }
  my $result_data = decode_json( $client->responseContent() );

  my ( $wd_folder_ref, $wd_film_section_ref, $wd_label_ref );
  foreach my $entry ( @{ $result_data->{results}{bindings} } ) {
    my $qid = $entry->{qid}{value};
    if ( $entry->{pm20Id} ) {
      $wd_folder_ref->{$qid} = $entry->{pm20Id}{value};
    }
    if ( $entry->{pm20FilmSectionId} ) {
      push @{ $wd_film_section_ref->{$qid} },
        $entry->{pm20FilmSectionId}{value};
    }
    if ( $entry->{label} ) {
      $wd_label_ref->{$qid} = $entry->{label}{value};
    }
  }

  ##print Dumper $wd_label_ref;exit;
  return $wd_folder_ref, $wd_film_section_ref, $wd_label_ref;
}

sub usage {
  print "usage: $0 { " . join( ' | ', @VALID_SUBSETS ) . " }\n";
}
