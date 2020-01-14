#!/bin/env perl
# nbt, 8.11.2019

# create lists of films from filmdata/*.json

use strict;
use warnings;
use utf8;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number);

# filmdata publicly available now
my $film_intern_root = path('../web.intern/film');
my $film_public_root = path('../web.public/film');
my $filmdata_root    = path('../data/filmdata');
##my $filmdata_root    = $film_public_root;
my $img_file         = $filmdata_root->child('img_count.json');
my $ip_hints         = path('../web.public/templates/fragments/ip_hints.de.md.frag')->slurp_utf8;

my %page = (
  h => {
    column_ids => [
      qw/ film_id start_sig start_date end_sig end_date img_count online comment /
    ],
    list  => {
      'h1_sh' => {
        title => 'Länder-Sacharchiv 1. Verfilmung',
      },
      'h2_sh' => {
        title => 'Länder-Sacharchiv 2. Verfilmung',
      },
      'h1_co' => {
        title => 'Firmen- und Institutionenarchiv 1. Verfilmung',
      },
      'h2_co' => {
        title => 'Firmen- und Institutionenarchiv 2. Verfilmung',
      },
      'h1_wa' => {
        title => 'Warenarchiv 1. Verfilmung',
      },
      'h2_wa' => {
        title => 'Warenarchiv 2. Verfilmung',
      },
    },
  },
  k => {
    column_ids => [
      qw/ film_id img_id country geo_sig topic_sig from to no_material comment /
    ],
    list  => {
      k1_sh => {
        title => 'Sacharchiv 1. Verfilmung',
      },
      k2_sh => {
        title => 'Sacharchiv 2. Verfilmung',
      },
    },
  },
);

# notation regex
# (this is a variation of the notation regex in check_ifis_notation.pl)
my %nta_regex = (
  ge => {
    title   => 'Historische Länderklassifikation',
    pattern => qr/ ^ [A-Z]    # Continent
        ( \d{0,3}             # optional numerical code for country
          [a-z]?              # optional extension of country code
          ( (              # optional subdivision in brackets
            ( \(\d\d?\) )     # either numerical
            | \((alt|Wn|Bln)\)# or special codes (old|Wien|Berlin)
          ) ){0,1}
        )? $ /x
  },
  sh => {
    title   => 'Alte Hamburger Systematik',
    pattern => qr/ ^
      [A-Z] |                 # ignore for now
      [a-z]                   # main class
        ( \s \d\d             # optional subclass
          [a-z]?              # optional subclass extension
        ){0,1}
        (                     # optional special folder
          \s SM \s .+
        ){0,1} $ /x

  },
);


##foreach my $prov ( keys %page ) {
foreach my $prov ( 'h' ) {
##  foreach my $page_name ( sort keys %{ $page{$prov}{list} } ) {
  foreach my $page_name ( 'h2_sh' ) {
    print "$page_name\n";

    my $coll  = substr( $page_name, 3, 2 );
    my $set   = substr( $page_name, 0, 2 );

    # read json input
    my @film_sections =
      @{ decode_json( $filmdata_root->child( $page_name . '.json' )->slurp ) };

    # iterate through the list of film sections (from the excel file)
    foreach my $film_section (@film_sections) {
      ##print Dumper $film_section;
			foreach my $sig ( 'start_sig', 'end_sig' ) {
        next unless $film_section->{$sig};

        # skip if special signature indicates empty film
        next if $film_section->{$sig} eq 'x';

        # remove the text part, reduce to notation
        my $nta;
        if ( $film_section->{$sig} =~ m/^.+? \/ (.+)$/ ) {
          $nta = $1;
        } else {
          $nta = $film_section->{$sig};
        }
				warn ("  Missing signature in ", Dumper $film_section) unless $nta;

        # split into geographical and subject notation (the latter may be omitted)
        my ($ge_nta, $sh_nta) = $nta =~ m/^(\S+)\s(.+)$/;
        if ( not $ge_nta ) {
          $ge_nta = $nta;
        }
        
        # check geo notation
        if (not $ge_nta =~ m/$nta_regex{ge}{pattern}/x) {
          warn "  Error in $ge_nta - $sig part of ", Dumper $film_section;
        }
        ##print Dumper $nta, $ge_nta, $sh_nta; exit;
			}
    }
  }
}

#######################

