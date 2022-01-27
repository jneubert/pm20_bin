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

Readonly my $USER          => '224220';
Readonly my $PM20_GROUP    => '4548009';
Readonly my $FILMDATA_STUB => '/pm20/data/filmdata/zotero.';
Readonly my @VALID_SUBSETS => qw/ h1_sh h1_co /;

# TODO extend to other holdings beyond Hamburg and sh or co
Readonly my %CONF => (
  'h' => {
    co => {
      film_qr => qr{[AF]\d{4}H(_[12])?},
      parser  => \&parse_co_signature,
    },
    sh => {
      film_qr => qr{S\d{4}H(_[12])?},
      parser  => \&parse_sh_signature,
    },
  },
);

binmode( STDOUT, ":utf8" );
$Data::Dumper::Sortkeys = 1;

my ( $provenance, $filming, $collection, $subset, %conf );
if ( $ARGV[0] and $ARGV[0] =~ m/(h|k)(1|2)_(co|sh|wa)/ ) {
  $provenance = $1;
  $filming    = $2;
  $collection = $3;
  $subset     = "$provenance${filming}_$collection";
  if ( not grep( /^$subset$/, @VALID_SUBSETS ) ) {
    usage();
    exit 1;
  }
  %conf = %{ $CONF{$provenance}{$collection} };
} else {
  usage();
  exit 1;
}

my ( %qid, %type_count, $good_count, $error_count, $film_count );

# initialize a lookup table for short notations and a supporting translate
# table from long to short notations (from web)
my ( $translate_geo,     $lookup_geo )     = get_lookup_tables('ag');
my ( $translate_subject, $lookup_subject ) = get_lookup_tables('je');
my ( $translate_company, $lookup_company ) = get_company_lookup_tables();

# all Zotero information is read from the web
my $zclient = WWW::Zotero->new();

# top level in Zotero are films
my %film;
my $data = $zclient->listCollectionsTop(
  group => $PM20_GROUP,
  limit => 100,
) or die "error reading top: $!\n";
foreach my $entry ( @{ $data->{results} } ) {
  $film{ $entry->{data}{name} }{key} = $entry->{data}{key};
}

# second level are items (sections) within the films
foreach my $film_id ( sort keys %film ) {

  # restrict to example A12/Polen
  next if ( $film_id lt 'S0220H_2' );
  next if ( $film_id gt 'S0236H_1' );

  # only work on films of a specific set
  next unless $film_id =~ $conf{film_qr};
  $film_count++;

  # read film data
  my $film_data = $zclient->listCollectionItemsTop(
    collectionKey => $film{$film_id}{key},
    group         => $PM20_GROUP,
    limit         => 100,
  ) or die "error reading $film_id; $!\n";

  my %item_film;
  my @entries = @{ $film_data->{results} };
  foreach my $entry (
    sort { $a->{data}{archiveLocation} cmp $b->{data}{archiveLocation} }
    @entries )
  {

    # skip entries for single publications
    my $type = $entry->{data}{itemType};
    if ( $type =~ m/^Document$/i ) {
      $type_count{document}++;
    } else {
      $type_count{$type}++;
      next;
    }

    my %item;
    my $location = $entry->{data}{archiveLocation};
    if ( $location =~ m;film/(.+\d)(/(L|R))?$; ) {

      $item{signature_string} = $entry->{data}{callNumber};
      $item{date}             = $entry->{data}{date};
      $item{id}               = $1;
      $item{lr}               = $3 || 'L';

      # get string version of the subject
      if ( $entry->{data}{title} =~ m/^.+? : (.+)$/ ) {
        $item{subject_string} = $1;
      }

      if ( defined $entry->{data}{libraryCatalog} ) {
        $item{qid} = $entry->{data}{libraryCatalog};
      }

      $conf{parser}->( $location, \%item );
      $item_film{$location} = \%item;
    } else {
      warn "$location: strange location\n";
      $error_count++;
      next;
    }
  }

  # save complete film
  $film{$film_id}{item} = \%item_film;
}

# save data (only if output dir exists)
my $output = path("$FILMDATA_STUB$subset.json");
if ( -d $output->parent ) {
  $output->spew( encode_json( \%film ) );
}

# output for debugging
foreach my $film_id ( sort keys %film ) {
  next unless $film_id =~ $conf{film_qr};

  my @items = sort keys %{ $film{$film_id}{item} };
  print "\n$film_id (" . scalar(@items) . " items)\n";

  foreach my $location (@items) {
    my %data = %{ $film{$film_id}{item}{$location} };

    next unless $data->{valid_sig};

    if ( $collection eq 'sh' ) {
      print
"\t$data{id}\t$data{lr}\t$data{geo}{signature} $data{subject}{signature}";
      if ( $data{keyword} ) {
        print " - $data{keyword}";
      }
      print "\t$data{geo}{label}{de} : $data{subject}{label}{de}\n";
    } elsif ( $collection eq 'co' ) {
      print "\t$data{id}\t$data{lr}\t$data{signature}";
      if ( $data{pm20Id} ) {
        print "\t$data{pm20Id}\t$data{company_name}\n";
      } else {
        print "\t$data{qid}\n";
      }
    }
  }
}

print Dumper \%type_count;
print
"$good_count good document items, $error_count errors in $film_count films from $subset\n";

##############################

sub parse_sh_signature {
  my $location = shift or die "param missing";
  my $item_ref = shift or die "param missing";

  # split into geo and subject part (plus optional keyword)
  my $signature = $item_ref->{signature_string};
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
  if ( defined $lookup_geo->{$geo_sig} ) {
    $item_ref->{geo} = $lookup_geo->{$geo_sig};
  } elsif ( defined $translate_geo->{$geo_sig} ) {
    $geo_sig = $translate_geo->{$geo_sig};
    $item_ref->{geo} = $lookup_geo->{$geo_sig};
  } else {
    warn "$location: $geo_sig not recognized\n";
  }

  # lookup subject
  if ( defined $lookup_subject->{$subject_sig} ) {
    $item_ref->{subject} = $lookup_subject->{$subject_sig};
  } elsif ( defined $translate_subject->{$subject_sig} ) {
    $subject_sig = $translate_subject->{$subject_sig};
    $item_ref->{subject} = $lookup_subject->{$subject_sig};
  } else {
    warn "$location: $subject_sig not recognized\n";
  }

  if ($keyword) {
    $item_ref->{keyword} = $keyword;
  }

  # both parts must be valid
  if ( defined $item_ref->{geo} and defined $item_ref->{subject} ) {
    $item_ref->{valid_sig} = 1;
    $good_count++;
  } else {
    $item_ref->{valid_sig} = 0;
    $error_count++;
  }
}

sub parse_co_signature {
  my $location = shift or die "param missing";
  my $item_ref = shift or die "param missing";

  my $signature = $item_ref->{signature};
  if ( defined $lookup_company->{$signature} ) {
    $item_ref->{company_name} = $lookup_company->{$signature}{label};
    $item_ref->{pm20Id}       = $lookup_company->{$signature}{pm20Id};
    $good_count++;
  } elsif ( $item_ref->{qid} ) {
    $qid{ $item_ref->{qid} } = 1;
    $good_count++;
  } else {
    warn "$location: $signature not recognized\n";
    $error_count++;
  }
}

sub get_lookup_tables {
  my $graph = shift or die "param missing";

  # retrieve info by SPARQL query
  my $query = <<EOF;
PREFIX zbwext: <http://zbw.eu/namespaces/zbw-extensions/>
PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
PREFIX dct: <http://purl.org/dc/terms/>
#
SELECT ?notation ?long ?id ?labelEn ?labelDe
WHERE {
  graph <http://zbw.eu/beta/GRAPH/ng> {
    ?pm20ag skos:notation ?notation ;
            dct:identifier ?id ;
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
    $lookup{ $entry->{notation}{value} }{label}{de} = $entry->{labelDe}{value};
    $lookup{ $entry->{notation}{value} }{label}{en} = $entry->{labelEn}{value};
    $lookup{ $entry->{notation}{value} }{signature} = $entry->{notation}{value};
    $lookup{ $entry->{notation}{value} }{id}        = $entry->{id}{value};
    $translate{ $entry->{long}{value} }             = $entry->{notation}{value};
  }
  return \%translate, \%lookup;
}

sub get_company_lookup_tables {

  # retrieve info by SPARQL query
  my $query = <<EOF;
PREFIX dc: <http://purl.org/dc/elements/1.1/>
PREFIX dct: <http://purl.org/dc/terms/>
PREFIX zbwext: <http://zbw.eu/namespaces/zbw-extensions/>
PREFIX skos: <http://www.w3.org/2004/02/skos/core#>
#
SELECT ?pm20Id ?notation ?label
WHERE {
  ?pm20 a zbwext:CompanyFolder ;
        dct:identifier ?pm20Id ;
        skos:notation ?notation ;
        skos:prefLabel ?label .
}
EOF

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
    warn "Could not execute query for company: ", $client->responseCode, "\n";
    return;
  }
  my $result_data = decode_json( $client->responseContent() );

  my ( %translate, %lookup );
  foreach my $entry ( @{ $result_data->{results}{bindings} } ) {
    $lookup{ $entry->{notation}{value} }{label}  = $entry->{label}{value};
    $lookup{ $entry->{notation}{value} }{pm20Id} = $entry->{pm20Id}{value};
  }

  # %translate is currently empty
  return \%translate, \%lookup;
}

sub usage {
  print "usage: $0 { " . join( ' | ', @VALID_SUBSETS ) . " }\n";
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

