#!/bin/perl
# nbt, 2021-01-12

# read information about film sections from Zotero and look up signatures

use strict;
use warnings;
use utf8;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use REST::Client;
use WWW::Zotero;

binmode( STDOUT, ":utf8" );
binmode( STDERR, ":utf8" );
$Data::Dumper::Sortkeys = 1;

Readonly my $USER => '224220';
Readonly my %PM20_GROUP => (
  1 => {
    name => 'PM20',
    id   => '4548009',
  },
  2 => {
    name => 'PM20-2',
    id   => '5342079',
  },
);
Readonly my $FILMDATA_STUB  => '/pm20/data/filmdata/zotero.';
Readonly my $FILM_IMG_COUNT => path('/pm20/data/filmdata/img_count.json');

# TODO extend to other holdings beyond Hamburg and sh or co
# (currently set is not restricted to a certain filming (1/2))
Readonly my @VALID_SUBSETS => qw/ h1_sh h1_co h1_wa h2_co h2_sh h2_wa /;
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
    wa => {
      film_qr => qr{W\d{4}H(_[12])?},
      parser  => \&parse_wa_signature,
    },
  },
);

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

my ( %qid, %type_count, $film_count, %qid_without_pm20id );
my $good_count  = 0;
my $error_count = 0;

# get image counts for all films
my $img_count_ref = decode_json( $FILM_IMG_COUNT->slurp() );

# initialize a lookup table for short notations and a supporting translate
# table from long to short notations (from web)
my ( $translate_geo, $lookup_geo, $reverse_geo ) = get_lookup_tables('geo');
my ( $translate_subject, $lookup_subject, $reverse_subject ) =
  get_lookup_tables('subject');
my ( $translate_ware, $lookup_ware, $reverse_ware ) = get_lookup_tables('ware');
my ( $translate_company, $lookup_company ) = get_company_lookup_tables();
my $lookup_qid = get_wikidata_lookup_table();

# save company lookup table for use in filmlists.
# For duplicate signatures, resulting label is arbitrary
my %lookup_tmp;
foreach my $nta ( keys %{$lookup_company} ) {
  $nta =~ s/^A10\/19/A10(19)/;
  $lookup_tmp{$nta} = $lookup_company->{$nta}{label};
}
my $fn_tmp = path('/pm20/data/filmdata/co_lookup.json');
$fn_tmp->spew( encode_json( \%lookup_tmp ) );

# all Zotero information is read from the web
my $zclient = WWW::Zotero->new();

# top level in Zotero are films
# (undivided film numbers - no S0123H_1/2 here!)
my ( %collection, %film );

# read in slices, due to limit in Zotero API
my $limit = 100;
my $start = 0;
my $more  = 1;
while ($more) {

  my $data = $zclient->listCollectionsTop(
    group => $PM20_GROUP{$filming}{id},
    limit => $limit,
    start => $start,
  ) or die "error reading top: $!\n";

  # hash of films in the current slice
  foreach my $entry ( @{ $data->{results} } ) {
    $collection{ $entry->{data}{key} } = $entry->{data}{name};
    ##$film{ $entry->{data}{name} }{key} = $entry->{data}{key};
  }

  # is there more data?
  if ( $data->{total} - ( $start + $limit ) gt 0 ) {
    $start = $start + $limit;
  } else {
    $more = 0;
  }
}

# second level are items (sections) within the films
FILM_KEY:
foreach my $key (
  sort { $collection{$a} cmp $collection{$b} }
  keys %collection
  )
{
  my $film_name = $collection{$key};

  # only work on films of a specific set
  next unless $film_name =~ $conf{film_qr};

  my %item_film;

  # second level loop (to cover films with more than $limit entries)
  my $start2 = 0;
  my $more2  = 1;
  while ($more2) {

    # read film data
    my $film_data = $zclient->listCollectionItemsTop(
      collectionKey => $key,
      group         => $PM20_GROUP{$filming}{id},
      limit         => $limit,
      start         => $start2,
    ) or die "error reading $film_name: $!\n";

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

      # is the filming of the subset correct? otherwise skip this film entirely
      next FILM_KEY unless $location =~ m;film/$provenance$filming/;;

      ##print Dumper $entry;
      if ( $location =~ m;film/(.+\d{4})(/(L|R))?$; ) {

        $item{signature_string} = $entry->{data}{callNumber};
        $item{id}               = $1;
        $item{lr}               = $3 || 'L';

        # get string version of the subject or company name
        if ( $entry->{data}{title} =~ m/^.+? : (.+)$/ and $collection eq 'sh' )
        {
          $item{subject_string} = $1;
        }
        if ( $collection eq 'co' ) {
          $item{company_string} = $entry->{data}{title};
          if ( $item{signature_string} ) {
            $item{company_string} .= " ($item{signature_string})";
          }
        }
        if ( $collection eq 'wa' or $collection eq 'sh' ) {
          $item{title} = $entry->{data}{title};
        }

        if ( defined $entry->{data}{date} ) {
          $item{start_date} = $entry->{data}{date};
        }

        if ( defined $entry->{data}{libraryCatalog} ) {
          $item{qid} = $entry->{data}{libraryCatalog};
        }

        if ( defined $entry->{data}{archive} ) {
          ## TODO parse id
          $item{direct_pm20id} = $entry->{data}{archive};
        }

        $conf{parser}->( $location, \%item );
        $item_film{$location} = \%item;
      } elsif ( not $location ) {
        warn "location missing: ", Dumper $entry->{data};
        $error_count++;
        next;
      } else {
        warn "$location: strange location\n";
        $error_count++;
        next;
      }
    }

    # is there more data (within the film)?
    if ( $film_data->{total} - ( $start2 + $limit ) gt 0 ) {
      ##warn "FILM $film_name: $film_data->{total} entries - CONTINUING\n";
      $start2 = $start2 + $limit;
    } else {
      $more2 = 0;
    }
  }

  # save complete film
  $film{$film_name}{item} = \%item_film;

  $film_count++;
}

# complete ids and
# print output for debugging and count images/item
foreach my $film_name ( sort keys %film ) {
  next unless $film_name =~ $conf{film_qr};

  my @items = sort keys %{ $film{$film_name}{item} };
  print "\n$film_name (" . scalar(@items) . " items)\n";

  my ( $old_location, $location );
  foreach $location (@items) {
    my %data = %{ $film{$film_name}{item}{$location} };

    # compute and add the number of images to the *previous* film
    add_number_of_images( $location, $old_location );
    $old_location = $location;

    # do not require valid signature
    ##next unless $data{valid_sig};

    # output for sh
    if ( $collection eq 'sh' ) {
      my $signature = $data{geo}{signature};
      print "\t$data{id}\t$signature";
      if ( $data{subject}{signature} ) {
        print " $data{subject}{signature}";
      }
      if ( $data{keyword} ) {
        print " - $data{keyword}";
      }
      print "\t$data{geo}{label}{de}";
      if ( defined $data{subject}{label}{de} ) {
        print " : $data{subject}{label}{de}";
      }
      print "\n";
    }

    # output for co
    elsif ( $collection eq 'co' ) {
      if ( $data{signature} ) {
        print "\t$data{id}\t$data{signature}";
      } else {
        print "\t$data{id}\t", Dumper \%data;
      }
      if ( not $data{signature} or length( $data{signature} ) < 8 ) {
        print "\t";
      }

      # normally, qid exists
      if ( $data{qid} ) {
        print "\t$data{qid}";
        $type_count{identified_by_qid}++;
      } else {
        print "\t--------";
      }
      if ( length( $data{qid} ) < 8 ) {
        print "\t";
      }

      # pm20Id entered directly in the Zotero record takes precedence
      if ( my $pm20Id = $data{direct_pm20id} ) {
        $film{$film_name}{item}{$location}{pm20Id} = $pm20Id;
        print "\t$pm20Id #";
        $type_count{identified_by_direct_pm20id}++;
      }

      # pm20Id derived from signature
      # (that's the default, because implemented first)
      elsif ( $data{pm20Id} ) {
        print "\t$data{pm20Id}";
        $type_count{identified_by_signature_to_pm20id}++;
      }

      # try to derive pm20Id from qid
      else {
        if ( my $pm20Id = $lookup_qid->{ $data{qid} } ) {
          $film{$film_name}{item}{$location}{pm20Id} =
            $lookup_qid->{ $data{qid} };
          print "\t$pm20Id *";
          $type_count{identified_by_qid_to_pm20id}++;
        } else {
          $qid_without_pm20id{ $data{qid} }++;
          print "\t\t";
        }
      }
      if ( $data{company_string} ) {
        print "\t$data{company_string}";
      }
      print "\n";
    }

    # output for wa
    elsif ( $collection eq 'wa' ) {
      print "\t$data{ware_string}";
      my $title_length = length( $data{ware_string} );
      if ( $data{geo_string} ) {
        print " : $data{geo_string}";
        $title_length += length( $data{geo_string} ) + 3;
      }
      if ( $title_length < 8 ) {
        print "\t\t\t\t";
      } elsif ( $title_length < 16 ) {
        print "\t\t\t";
      } elsif ( $title_length < 24 ) {
        print "\t\t";
      } elsif ( $title_length < 32 ) {
        print "\t";
      }
      print "\t\t";
      if ( $data{ware} ) {
        print "$data{ware}{id}";
      } else {
        print '?';
      }
      if ( $data{geo} ) {
        print ", $data{geo}{id}";
      } elsif ( $data{geo_string} ) {
        print ', ?';
      }

      print "\n";
    }
  }
  add_number_of_images( 'last', $old_location );
}
if ( $collection eq 'co' ) {
  print
"# means pm20Id directly from Zotero, * means indirectly via wikidata, otherweise derived from signature\n";
}

# save film data
my $output = path("$FILMDATA_STUB$subset.json");
$output->spew( encode_json( \%film ) );

# build and save category_by_id data for company (!)
# (applies now only to co, wa and sh are now covered by merge_film_ids.pl)G
if ( $collection eq 'co' ) {
  build_category_by_id_list( \%film, 'company' );
}

# save qids without pm20ids as input for wikidata query
if ( $collection eq 'co' ) {
  my @qidlist = keys %qid_without_pm20id;
  my $txt     = "'" . join( "' '", @qidlist ) . "'";
  path("/tmp/qid_without_pm20id.$subset.txt")->spew($txt);
}

# overall statistics
print Dumper \%type_count;
print
"$good_count good document items, $error_count errors in $film_count films from $subset\n";

##############################

sub add_number_of_images {
  my $location     = shift or die "param missing";
  my $old_location = shift;

  # skip first section of a film
  return unless $old_location;

  my $film_name = ( split( '/', $old_location ) )[3];
  my $old_pos   = ( split( '/', $old_location ) )[4];
  my $pos       = ( split( '/', $location ) )[4];

  # take care of last section of a film - read last image number from file
  if ( $location eq 'last' ) {
    my $film_id  = join( '/', ( split( /\//, $old_location ) )[ 0 .. 3 ] );
    my $film_dir = path('/pm20')->child($film_id);
    my @files    = sort $film_dir->children(qr/\.jpg\z/);
    my $fn       = $files[-1]->relative($film_dir);
    if ( $fn =~ m/^[A-Z]\d{4}(\d{4})/ ) {
      $pos = $1;
    } else {
      die "Could not parse $fn\n";
    }
  }

  my $number_of_images = int($pos) - int($old_pos);

  # zotero uses film names w/o _1, _2
  ( my $zotero_film_name = $film_name ) =~ s/(.+)?_[12]$/$1/;

  # number of images per film
  $film{$zotero_film_name}{item}{$old_location}{number_of_images} =
    $number_of_images;
}

sub parse_sh_signature {
  my $location = shift or die "param missing";
  my $item_ref = shift or die "param missing";

  # split into geo and subject part (plus optional keyword)
  # (allow for geo only, too)
  my $signature = $item_ref->{signature_string};
  my ( $geo_sig, $subject_sig, $keyword );
  if ( $signature =~ m/^(\S+)(?:\s+(.+?))?(?: (?:\-|\|) (.+))?$/ ) {
    $geo_sig     = $1;
    $subject_sig = $2;
    $keyword     = $3;
  } else {
    warn "$location: strange signature $signature\n";
    $error_count++;
    return;
  }

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
  if ( not $subject_sig ) {
    ## only geo signature is now valid
    $item_ref->{subject} = undef;
    ##warn "$location: $signature - only geo, no subject signature\n";
  } elsif ( defined $lookup_subject->{$subject_sig} ) {
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

sub parse_wa_signature {
  my $location = shift or die "param missing";
  my $item_ref = shift or die "param missing";

  # split into ware and geo part
  # (allow for ware only, too)
  my ( $ware_string, $geo_string );
  if ( $item_ref->{title} =~ m/^(.+?)( : (.+))?$/ ) {
    $item_ref->{ware_string} = $1;
    $ware_string = $1;
    if ($3) {
      $item_ref->{geo_string} = $3;
      $geo_string = $3;
    }
  }

  # supplement reverse geo lookup list with additional entry points
  # used for wares in zotero
  supplement_ware_geo();

  # map to categories
  if ( defined $reverse_ware->{$ware_string} ) {
    $item_ref->{ware} = $lookup_ware->{ $reverse_ware->{$ware_string} };
  } else {
    warn "$location: ware  $ware_string  not recognized\n";
  }
  if ($geo_string) {
    if ( defined $reverse_geo->{$geo_string} ) {
      $item_ref->{geo} = $lookup_geo->{ $reverse_geo->{$geo_string} };
    } else {
      warn "$location: geo  $geo_string  not recognized\n";
    }
  }
}

sub parse_co_signature {
  my $location = shift or die "param missing";
  my $item_ref = shift or die "param missing";

  my $signature = $item_ref->{signature_string};
  if ( defined $lookup_company->{$signature} ) {
    ##$item_ref->{company_string} = $lookup_company->{$signature}{label};
    $item_ref->{pm20Id}    = $lookup_company->{$signature}{pm20Id};
    $item_ref->{signature} = $signature;
    $item_ref->{valid_sig} = 1;
    $good_count++;
  } elsif ( $item_ref->{qid} ) {
    $qid{ $item_ref->{qid} } = 1;
    $item_ref->{signature}   = $signature;
    $item_ref->{valid_sig}   = 1;
    $good_count++;
  } else {
    warn "$location: $signature not recognized\n";
    $item_ref->{valid_sig} = 0;
    $error_count++;
  }

  my $geo_sig;

  # regex from check_film_notation.pl
  if (
    $signature =~ m/ ^ ( [A-Z]    # Continent
        ( \d{0,3}             # optional numerical code for country
          [a-z]?              # optional extension of country code
          ( (              # optional subdivision in brackets
            ( \(\d\d?\) )     # either numerical
            | \((alt|Wn|Bln)\)# or special codes (old|Wien|Berlin)
          ) ){0,1}
        )? ) \s /x
    )
  {
    $geo_sig = $1;
  } else {
    warn "$location: missing geo: $signature\n";
    return;
  }

  # lookup geo
  if ( defined $lookup_geo->{$geo_sig} ) {
    $item_ref->{geo} = $lookup_geo->{$geo_sig};
  } elsif ( defined $translate_geo->{$geo_sig} ) {
    $geo_sig = $translate_geo->{$geo_sig};
    $item_ref->{geo} = $lookup_geo->{$geo_sig};
  } else {
    warn "$location: $geo_sig not recognized\n";
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

  my $endpoint = 'https://zbw.eu/beta/sparql/pm20/query';
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
    warn "Could not execute query for $graph: ", $client->responseCode, "\n",
      $client->responseContent, "\n";
    return;
  }
  my $result_data = decode_json( $client->responseContent() );

  my ( %translate, %lookup, %reverse );
  foreach my $entry ( @{ $result_data->{results}{bindings} } ) {
    $lookup{ $entry->{notation}{value} }{label}{de} = $entry->{labelDe}{value};
    $lookup{ $entry->{notation}{value} }{label}{en} = $entry->{labelEn}{value};
    $lookup{ $entry->{notation}{value} }{signature} = $entry->{notation}{value};
    $lookup{ $entry->{notation}{value} }{id}        = $entry->{id}{value};
    $translate{ $entry->{long}{value} }             = $entry->{notation}{value};
    $reverse{ $entry->{labelDe}{value} }            = $entry->{notation}{value};
  }
  return \%translate, \%lookup, \%reverse;
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

  my $endpoint = 'https://zbw.eu/beta/sparql/pm20/query';
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

sub get_wikidata_lookup_table {

  # retrieve info by SPARQL query
  # (assume that the lowest id entry is the main entry when multiple exist)
  my $query = <<EOF;
PREFIX wd: <http://www.wikidata.org/entity/>
PREFIX wdt: <http://www.wikidata.org/prop/direct/>
#
select (strafter(str(?wd), str(wd:)) as ?qid ) (min(?pm20IdX) as ?pm20Id)
where {
  ?wd wdt:P4293 ?pm20IdX .
  filter(strstarts(?pm20IdX, 'co/'))
}
group by ?wd
EOF

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
    warn "Could not execute query for wikidata company: ",
      $client->responseCode, "\n";
    return;
  }
  my $result_data = decode_json( $client->responseContent() );

  my %lookup;
  foreach my $entry ( @{ $result_data->{results}{bindings} } ) {
    $lookup{ $entry->{qid}{value} } = $entry->{pm20Id}{value};
  }

  return \%lookup;
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

sub supplement_ware_geo {

  my $list_str = << 'EOF';
E9 Neufundland
C60 Nigeria
A43 Osmanisches Reich
A10(19) Protektorat
A10d Saarland
A50 Sowjetunion
E15 Vereinigte Staaten
A40e Jugoslawien
B24a Palästina
B21 Türkei
C87 Südwestafrika
H Welt, Austellungen, Kongresse
H Welt, Handel und Industrie
H Welt, Industrie
H Welt, Produktionstechnik
A10k Danzig
EOF

  my @list = split( "\n", $list_str );
  foreach my $line (@list) {
    $line =~ m/^(\S+) (.+)$/;
    $reverse_geo->{$2} = $1;
  }
}

# category is meant to be "company" here!
sub build_category_by_id_list {
  my $film_ref         = shift or die "param missing";
  my $by_category_type = shift or die "param missing";

  my %film = %{$film_ref};
  my %category;

  # collect film sections
  foreach my $film_name ( sort keys %film ) {
    next unless $film_name =~ $conf{film_qr};

    my @items = sort keys %{ $film{$film_name}{item} };

    foreach my $location (@items) {
      my %data = %{ $film{$film_name}{item}{$location} };

      next
        unless $data{$by_category_type}
        or ( defined $data{pm20Id} and $data{pm20Id} ne '' );

      # title for the marker (not validated, not guaranteed
      # to cover the whole stretch of images up to the next marker
      my $first_img   = $data{company_string};
      my $category_id = $data{pm20Id};

      my $entry_ref = {
        location  => $location,
        first_img => $first_img,
      };

      push( @{ $category{$category_id}{sections} }, $entry_ref );

      # compute totals
      $category{$category_id}{total_number_of_images} +=
        $data{number_of_images};
    }
  }

  my $output = path("$FILMDATA_STUB$subset.by_${by_category_type}_id.json");
  print "\n$output\n";
  $output->spew( encode_json( \%category ) );
}

