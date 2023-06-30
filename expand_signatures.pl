#!/bin/env perl
# nbt, 26.6.2023

# cleans up and expands signatures

# Normally should be part of parse_findbuch.pl on ite-srv24 - which does not
# work currently. So all expanded signatures from ite-srv24 are completely
# reset and an extended expansion is applied here.

# Adds start_sig_expanded, end_sig_expaended instead of overwriting

use strict;
use warnings;
use utf8;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number);

binmode( STDOUT, ":utf8" );

my $klassdata_root = path('../data/klassdata');
my $filmdata_root  = path('../data/filmdata');
my $film_web_root  = path('../web/film');

# notation to country name mapping for signature extension
my %country =
  %{ decode_json( $klassdata_root->child('ag_lookup.json')->slurp ) };

my %sh =
  %{ decode_json( $klassdata_root->child('je_lookup.json')->slurp ) };

my %page = (
  h => {
    name      => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
    list => {
      'h1_sh' => {
        title  => 'Länder-Sacharchiv',
        covers => 'von 1908 (z.T. früher) bis ca. 1949',
      },
      'h2_sh' => {
        title  => 'Länder-Sacharchiv',
        covers => 'von ca. 1949 bis ca. 1960',
      },
      'h1_co' => {
        title  => 'Firmen- und Institutionenarchiv',
        covers => 'von 1908 (z.T. früher) bis ca. 1949',
      },
      'h2_co' => {
        title  => 'Firmen- und Institutionenarchiv',
        covers => 'von ca. 1949 bis ca. 1960',
      },
      'h1_wa' => {
        title  => 'Warenarchiv',
        covers => 'von 1908 (z.T. früher) bis ca. 1946',
      },
      'h2_wa' => {
        title  => 'Warenarchiv',
        covers => 'von ca. 1947 bis ca. 1960',
      },
    },
  },
  k => {
    name => 'Wirtschaftsarchiv des Instituts für Weltwirtschaft (WiA)',
    list => {
      k1_sh => {
        title => 'Sacharchiv',
      },
      k2_sh => {
        title => 'Sacharchiv',
      },
    },
  },
);

foreach my $prov (qw/ h /) {

  ##foreach my $page_name ( sort keys %{ $page{$prov}{list} } ) {
  foreach my $page_name (qw/ h1_sh h2_sh /) {

    my $coll = substr( $page_name, 3, 2 );
    my $set  = substr( $page_name, 0, 2 );

    # read json input
    my @film_sections =
      @{ decode_json( $filmdata_root->child( $page_name . '.json' )->slurp ) };

    # iterate through the list of film sections (from the excel file)
    foreach my $film_section (@film_sections) {
      my $film_id = $film_section->{film_id};

      # skip film if it has no content (is only a line in the list)
      next unless -d "$film_web_root/$set/$coll/$film_id";

      my $id = "film/$set/$coll/$film_id";

      # save already expanded signatures
      my $old_start_sig = $film_section->{start_sig};
      my $old_end_sig   = $film_section->{end_sig};

      # reset signatures to the part in square brackets
      my $start_sig = "$film_section->{start_sig}";
      if ( $start_sig =~ m/\[(.+)\]/ ) {
        $start_sig = $1;
      }
      my $end_sig = "$film_section->{end_sig}";
      if ( $end_sig =~ m/\[(.+)\]/ ) {
        $end_sig = $1;
      }

      # replace expanded signatures
      if ( $coll eq 'sh' ) {
        $film_section->{start_sig} =
          expand_sh_signature( $start_sig, $film_id );
        $film_section->{end_sig} = expand_sh_signature( $end_sig, $film_id );
      }

      # output old/new differences for debugging
      $old_start_sig =~ s/\s+/ /g;
      if ( $film_section->{start_sig} ne $old_start_sig ) {
        ##print "$old_start_sig ==> $film_section->{start_sig}\n";
      }
      $old_end_sig =~ s/\s+/ /g;
      if ( $film_section->{end_sig} ne $old_end_sig ) {
        print "$old_end_sig} ==> $film_section->{end_sig}\n";
      }
    }

    # write output (replace file)
    my $out = $filmdata_root->child( $page_name . '.expanded.json' );
    $out->spew_utf8( encode_json( \@film_sections ) );
  }
}

########

sub clean_sh_signature {
  my $signature = shift || die "param missing";

  # replace individual typos
  $signature =~ s/^C85 q m32$/C85 q Sm32/;
  $signature =~ s/^A1 n4 sm40$/A1 n4 Sm40/;

  # geo

  # blank after continent
  if ( $signature =~ m/^([A-H]) (\d.*)$/ ) {
    $signature = "$1$2";
  }

  # geo sig including small letter
  if ( $signature =~ /^([A-G]\d+) ([a-z] [a-q].*)$/ ) {
    ## don't replace buggy signatures
    if ( not( $signature =~ m/A22 i h/ or $signature =~ m/A30 q n/ ) ) {
      $signature = "$1$2";
    }
  }

  # subject

  # blank after first level
  if ( $signature =~ m/^([A-H]\S+\s[a-q]) (\d.*)$/ ) {
    ## don't replace buggy signatures with missing "Sm"
    if ( not $signature =~ m/q 50[123]/ ) {
      $signature = "$1$2";
    }
  }

  # extension character (e.g., m4a)
  if ( $signature =~ m/^(\S+ [a-q]\d+) ([a-c].*)$/ ) {
    $signature = "$1$2";
  }

  # blank before Sm
  if ( $signature =~ m/^(.+)SM (\d.*)/i ) {
    $signature = "$1Sm$2";
  }

  # dot before roman Sm number extension
  if ( $signature =~ m/^(.+Sm\d+)([IVX].*)$/ ) {
    $signature = "$1.$2";
  }

  return $signature;
}

sub expand_sh_signature {
  my $signature = shift || die "param missing";
  my $film_id   = shift || die "param missing";

  return $signature if ( $signature eq 'x' );

  # squeeze multiple blanks
  $signature =~ s/\s+/ /g;

  my $old_signature = $signature;
  $signature = clean_sh_signature($signature);

  if ( $signature ne $old_signature ) {
    ##print "$old_signature\t->\t$signature\n";
  }

  $signature =~ m/^(\S+)(\s(.*))?$/;
  my $geo   = $1;
  my $topic = $3;

  if ( not $geo ) {
    warn "Unmatching signature: $signature\n";
  }

  # expand geo
  my $expanded_signature;
  if ( $country{$geo} ) {
    $expanded_signature = $country{$geo};
  } else {
    $expanded_signature = '???';
  }

  # expand topic
  if ($topic) {

    # cleanup Sm entries
    $topic =~ s/ [Ss][Mm]/ Sm/;
    $topic =~ s/ Sm\s+/ Sm/;

    # check backwards to recognize the longest possible substring
    my @parts = split( / /, $topic );
    my @unrecognized;
    my $topic_expanded = '';

    my $i = @parts;
    PART: while ( $i > 0 ) {

      # if matched
      if ( $sh{ join( ' ', @parts ) } ) {

        # append the unrecognized parts to the expanded recognized
        $topic_expanded =
          $sh{ join( ' ', @parts ) } . ' ' . join( ' ', @unrecognized );
        last PART;
      }
      if ( $i == 1 ) {
        ##print "$film_id not found:\t$topic\n";
        $topic_expanded = $topic;
      }
      my $last = pop(@parts);
      unshift( @unrecognized, $last );
      $i--;
    }
    $expanded_signature = "$expanded_signature : $topic_expanded";
  }

  $expanded_signature = "$expanded_signature [$signature]";

  # squeeze multiple blanks
  $expanded_signature =~ s/\s+/ /g;

  return $expanded_signature;
}

