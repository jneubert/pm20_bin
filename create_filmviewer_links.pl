#!/bin/env perl
# nbt, 2022-01--24

# creates html fragments with image links for filmviewer

# can be invoked either by
# - an extended folder id (e.g., pe/000012)
# - a collection id (e.g., pe)
# - 'ALL' (to (re-) create all collections)

use strict;
use warnings;
use utf8;

use lib './lib';

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use ZBW::PM20x::Vocab;

$Data::Dumper::Sortkeys = 1;

##Readonly my $FOLDER_ROOT    => $ZBW::PM20x::Folder::FOLDER_ROOT;
Readonly my $FILM_ROOT     => path('/pm20/web/film');
Readonly my $FILMDATA_ROOT => path('/pm20/data/filmdata');
Readonly my @COLLECTIONS   => qw/ co sh wa /;
Readonly my @LANGUAGES     => qw/ en de /;
Readonly my @VALID_SUBSETS => qw/ h1_sh h1_co /;

my ( $provenance, $filming, $collection, $set, $subset, $subset_root );
if ( $ARGV[0] and $ARGV[0] =~ m/(h|k)(1|2)_(co|sh|wa)/ ) {
  $provenance = $1;
  $filming    = $2;
  $collection = $3;
  $set        = "$provenance$filming";
  $subset     = "${set}_$collection";
  if ( not grep( /^$subset$/, @VALID_SUBSETS ) ) {
    usage();
    exit 1;
  }
  $subset_root = $FILM_ROOT->child($set)->child($collection);
  ##%conf = %{ $CONF{$provenance}{$collection} };
} else {
  usage();
  exit 1;
}

my %vocab;
$vocab{geo}     = ZBW::PM20x::Vocab->new('ag');
$vocab{subject} = ZBW::PM20x::Vocab->new('je');

my %position;
parse_filmlist($subset);

####################

sub parse_filmlist {
  my $subset = shift or die "param mssing";

  my @filmlist =
    @{ decode_json( $FILMDATA_ROOT->child("$subset.json")->slurp ) };

  foreach my $entry (@filmlist) {
    next if ( $entry->{online} ne '' );

    # restrict to example A12/Polen
    next if ( $entry->{film_id} lt 'S0220H_2' );
    next if ( $entry->{film_id} gt 'S0236H_1' );

    POS:
    foreach my $pos ( 'start', 'end' ) {
      my $ord = $pos eq 'start' ? 0 : 9999;

      my %sig;
      if ( $entry->{"${pos}_sig"} =~ m/\[(\S+)\s+(.+?)(?: - (.+))?\]$/ ) {
        $sig{geo}     = $1;
        $sig{subject} = $2;
        ## save optional keyword for later use
        $position{$ord}{keyword} = $3;
      } else {
        warn "cannot parse signatur of ", Dumper $entry;
      }

      # substitute known variants in signatures
      $sig{subject} =~ s/q sm/q Sm/;
      $sig{subject} =~ s/q Nr /q Sm/;

      foreach my $voc ( sort keys %sig ) {

        my $id = $vocab{$voc}->lookup_signature( $sig{$voc} );
        if ( not $id ) {
          warn "$entry->{film_id}: $pos signature $sig{$voc} not found\n";
          if ( $voc eq 'geo' ) {
            die;
          }
          next POS;
        }
        $position{$ord}{$voc}{signature} = $sig{$voc};
        $position{$ord}{$voc}{id}        = $id;

        foreach my $lang (@LANGUAGES) {
          $position{$ord}{$voc}{label}{$lang} =
            $vocab{$voc}->label( $lang, $id );
        }
      }
    }
  }
}

sub usage {
  print "usage: $0 { " . join( ' | ', @VALID_SUBSETS ) . " }\n";
}

