#!/bin/perl
# nbt, 2021-01-12

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use REST::Client;
use WWW::Zotero;

Readonly my $USER       => '224220';
Readonly my $PM20_GROUP => '4548009';

binmode( STDOUT, ":utf8" );

my ( %type_count, $good_count, $error_count );

# initialize a lookup table for short notations and a supporting translate
# table from long to short notations (from web)
my ( $translate_geo,     $lookup_geo )     = get_lookup_tables('ag');
my ( $translate_subject, $lookup_subject ) = get_lookup_tables('je');

# all Zotero information is read from the web
my $zclient = WWW::Zotero->new();

# top level in Zotero are films
my %film;
my $data = $zclient->listCollectionsTop( group => $PM20_GROUP )
  or die "error reading top: $!\n";
foreach my $entry ( @{ $data->{results} } ) {
  $film{ $entry->{data}{name} }{key} = $entry->{data}{key};
}

# second level are items (sections) within the films
foreach my $film_id ( sort keys %film ) {

  # for now, only use "Sach" films
  next unless $film_id =~ m/^S/;

  # read film data
  my $film_data = $zclient->listCollectionItemsTop(
    collectionKey => $film{$film_id}{key},
    group         => $PM20_GROUP,
    limit         => 100,
  ) or die "error reading $film_id; $!\n";

  my %item_film;
  foreach my $entry ( @{ $film_data->{results} } ) {

    # skip entries for single publications
    my $type = $entry->{data}{itemType};
    if ( $type =~ m/^Document$/i ) {
      $type_count{Document}++;
    } else {
      $type_count{$type}++;
      next;
    }

    my %item;
    my $location = $entry->{data}{archiveLocation};
    if ( $location =~ m;film/(.+\d)(/(L|R))?$; ) {

      $item{signature} = $entry->{data}{callNumber};
      $item{date}      = $entry->{data}{date};
      $item{id}        = $1;
      $item{lr}        = $3 || 'L';

      if ( parse_signature( $location, \%item ) ) {
        $item_film{$location} = \%item;
        $good_count++;
      }
    } else {
      warn "$location: strange location\n";
      $error_count++;
      next;
    }
  }

  # save complete film
  $film{$film_id}{item} = \%item_film;
}

# output for debugging
foreach my $film_id ( sort keys %film ) {
  next unless $film_id =~ m/^S/;

  my @items = sort keys %{ $film{$film_id}{item} };
  print "\n$film_id (" . scalar(@items) . " items)\n";

  foreach my $location (@items) {
    my %data = %{ $film{$film_id}{item}{$location} };
    print
"\t$data{id}\t$data{lr}\t$data{geo_sig} $data{subject_sig}";
    if ($data{keyword}) {
      print " - $data{keyword}";
    }
    print "\t$data{geo} : $data{subject}\n";
  }
}

print Dumper \%type_count;
print "$good_count good document items, $error_count errors\n";

##############################

sub parse_signature {
  my $location = shift or die "param missing";
  my $item_ref = shift or die "param missing";

  # split into geo and subject part (plus optional keyword)
  my $signature = $item_ref->{signature};
  my ( $geo_sig, $subject_sig, $keyword );
  if ( $signature =~ m/^(\S+)\s(.+?)(?: (?:\-|\|) (.+))?$/ ) {
    $geo_sig     = $1;
    $subject_sig = $2;
    $keyword     = $3;
  } else {
    warn "$location: strange signature $signature\n";
    $error_count++;
    return;
  }
  #
  # lookup geo
  my ( $geo, $subject );
  if ( defined $lookup_geo->{$geo_sig} ) {
    $geo = $lookup_geo->{$geo_sig}{de};
  } elsif ( defined $translate_geo->{$geo_sig} ) {
    $geo_sig = $translate_geo->{$geo_sig};
    $geo     = $lookup_geo->{$geo_sig}{de};
  } else {
    warn "$location: $geo_sig not recognized\n";
  }

  # lookup subject
  if ( defined $lookup_subject->{$subject_sig} ) {
    $subject = $lookup_subject->{$subject_sig}{de};
  } elsif ( defined $translate_subject->{$subject_sig} ) {
    $subject_sig = $translate_subject->{$subject_sig};
    $subject     = $lookup_subject->{$subject_sig}{de};
  } else {
    warn "$location: $subject_sig not recognized\n";
  }

  # both parts must be valid
  if ( defined $geo and defined $subject ) {
    $item_ref->{geo_sig}     = $geo_sig;
    $item_ref->{geo}         = $geo;
    $item_ref->{subject_sig} = $subject_sig;
    $item_ref->{subject}     = $subject;
    if ($keyword) {
      $item_ref->{keyword} = $keyword;
    }
    return 1;
  } else {
    $error_count++;
    return;
  }
}

sub get_lookup_tables {
  my $graph = shift or die "param missing";

  # retrieve info by SPARQL query
  my $query = <<EOF;
PREFIX zbwext: <http://zbw.eu/namespaces/zbw-extensions/>
PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
#
SELECT ?notation ?long ?labelEn ?labelDe
WHERE {
  graph <http://zbw.eu/beta/GRAPH/ng> {
    ?pm20ag skos:notation ?notation ;
            zbwext:notationLong ?long ;
            skos:prefLabel ?labelLangEn ;
            skos:prefLabel ?labelLangDe .
    filter(lang(?labelLangDe) = 'de')
    filter(lang(?labelLangEn) = 'en')
    bind(str(?labelLangDe) as ?labelDe)
    bind(str(?labelLangEn) as ?labelEn)
  }
}
EOF

  $query =~ s/GRAPH/$graph/;

  my $endpoint = 'http://zbw.eu/beta/sparql/pm20/query';
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
    warn "Could not execute query for $graph: ", $client->responseCode, "\n";
    return;
  }
  my $result_data = decode_json( $client->responseContent() );

  my ( %translate, %lookup );
  foreach my $entry ( @{ $result_data->{results}{bindings} } ) {
    $lookup{ $entry->{notation}{value} }{de} = $entry->{labelDe}{value};
    $lookup{ $entry->{notation}{value} }{en} = $entry->{labelEn}{value};
    $translate{ $entry->{long}{value} }      = $entry->{notation}{value};
  }
  return \%translate, \%lookup;
}

# from set_ifis_short_notation.pl
# for reference, not used!
sub get_short_notation {
  my $notation = shift or die "param missing";

  # replace multiple whitespace (just in case)
  $notation =~ s/(\s)+/$1/;

  # remove leading zeros and all whitespace
  # (for AG)
  $notation =~ s/^([A-Z])\s00/$1/;
  $notation =~ s/^([A-Z])\s0/$1/;
  ## remove leading zeros and whitespace from second country notaton
  $notation =~ s/\(([A-Z])\s00(\d+)\)/($1$2)/;
  $notation =~ s/\(([A-Z])\s0(\d+)\)/($1$2)/;
  $notation =~ s/\(([A-Z])\s(\d+)\)/($1$2)/;
  ## remove leading zeros within parenthesis
  $notation =~ s/\(0(\d+)\)/($1)/;

  # remove all remaining whitespace
  $notation =~ s/^([A-Z]\S*)\s(\S+)/$1$2/;
  $notation =~ s/^([A-Z]\S*)\s(\S+)/$1$2/;

  # remove first whitespace and leadings zeros
  # (for JE)
  $notation =~ s/([a-z])\s(.*)/$1$2/;
  $notation =~ s/([a-z])0(\d.*)/$1$2/;

  # remove leading zeros after dot (may occur twice)
  $notation =~ s/\.0+([1-9].*)/\.$1/;
  $notation =~ s/\.0+([1-9].*)/\.$1/;

  ## remove whitespace and leading zeros within country notation in parenthesis
  $notation =~ s/\(([A-Z])\s0+([1-9].*?)\)/($1$2)/;

  # normalization of SM entries
  $notation =~ s/^qSM/q Sm/;
  $notation =~ s/ [Ss][Mm]/ Sm/;
  $notation =~ s/ Sm (\d.*)/ Sm$1/;
  $notation =~ s/ Sm0+(\d.*)/ Sm$1/;

  # remove artificial level for top SM entries (in JE)
  $notation =~ s/^([a-p])0 Sm/$1 Sm/;

  # set subsections of SM entries to roman numerals
  if ( $notation =~ m/(.*? Sm\d+\.)(\d+)(.*)/ ) {
    $notation = $1 . Roman($2) . $3;
  }

  # remove whitespace in front of "(alt) Sm"
  $notation =~ s/\s+\(alt\) /(alt)/;

  return $notation;
}

