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
parse_zotero($subset);
parse_filmlist($subset);

##print Dumper \%position;

foreach my $film ( sort keys %position ) {

  # compute image numbers and link paths
  my %image;
  my $film_dir = $subset_root->child($film);
  my @files    = $film_dir->children(qr/\.jpg\z/);
  foreach my $file (@files) {
    my $img_nr = $file->basename('.jpg');
    $img_nr =~ s/[SAF]\d{4}(\d{4})[HK]/$1/;
    $image{$img_nr} = $file->relative('/pm20/web')->parent->child($img_nr)->absolute('/');
  }
  $image{'0000'} = undef;
  $image{'9999'} = undef;

  # merge
  my @postions = sort keys %{ $position{$film}{items} };
  foreach my $lang (@LANGUAGES) {
    my @links;
    foreach my $img_nr ( sort keys %image ) {
      if ( defined $position{$film}{$img_nr} ) {
        my %item = %{ $position{$film}{$img_nr} };
        ## skip items without identified geo
        next if not defined $item{geo};
        push( @links, get_item_tag( $lang, $img_nr, \%item ) );
      }
      if ( defined $image{$img_nr} ) {
        push( @links,
          "<a id='img_$img_nr' href='$image{$img_nr}'>$img_nr</a> &#160;" );
      }
    }

    # save links
    $film_dir->child("links.$lang.html.frag")->spew_utf8( join( "\n", @links ) );
  }
}

####################

sub parse_zotero {
  my $subset = shift or die "param mssing";

  my %film =
    %{ decode_json( $FILMDATA_ROOT->child("zotero.$subset.json")->slurp ) };

  foreach my $film ( sort keys %film ) {
    foreach my $item_key ( sort keys %{ $film{$film}{item} } ) {
      my $item = $film{$film}{item}{$item_key};
      my $page = $item->{id};
      $page =~ s/.*?\/(\d{4})$/$1/;
      $position{$film}{$page} = $item;
    }
  }
}

sub parse_filmlist {
  my $subset = shift or die "param mssing";

  my @filmlist =
    @{ decode_json( $FILMDATA_ROOT->child("$subset.json")->slurp ) };

  foreach my $entry (@filmlist) {
    next if ( $entry->{online} ne '' );

    my $film = $entry->{film_id};

    # restrict to example A12/Polen
    next if ( $film lt 'S0220H_2' );
    next if ( $film gt 'S0236H_1' );

    POS:
    foreach my $pos ( 'start', 'end' ) {
      my $ord = $pos eq 'start' ? '0000' : '9999';

      my %sig;
      my $signature_string = $entry->{"${pos}_sig"};
      $position{$film}{$ord}{signature_string} = $signature_string;
      if ( $signature_string =~ m/ : (.+?) \[(\S+)\s+(.+?)(?: - (.+))?\]$/ ) {
        ## string version of the subject
        $position{$film}{$ord}{subject_string} = $1;
        $sig{geo}                              = $2;
        $sig{subject}                          = $3;
        ## save optional keyword for later use
        $position{$film}{$ord}{keyword} = $4;
      } else {
        warn "cannot parse signatur of ", Dumper $entry;
      }

      # substitute known variants in signatures
      $sig{subject} =~ s/q sm/q Sm/;
      $sig{subject} =~ s/q Nr /q Sm/;

      foreach my $voc ( sort keys %sig ) {

        my $id = $vocab{$voc}->lookup_signature( $sig{$voc} );
        if ($id) {
          $position{$film}{$ord}{$voc}{signature} = $sig{$voc};
          $position{$film}{$ord}{$voc}{id}        = $id;

          foreach my $lang (@LANGUAGES) {
            $position{$film}{$ord}{$voc}{label}{$lang} =
              $vocab{$voc}->label( $lang, $id );
          }
        } else {
          if ( $voc eq 'geo' ) {
            die "$film: $pos geo signature $sig{geo} not recognized\n";
          } else {
            warn "$film: $pos signature $sig{$voc} not found\n";
          }
        }
      }
    }
  }
}

sub get_item_tag {
  my $lang     = shift or die "param missing";
  my $img_nr   = shift or die "param missing";
  my $item_ref = shift or die "param missing";
  my %item     = %{$item_ref};

  my $tag = "<a id='tag_$img_nr'";
  my ( $label, $title );
  if ( defined $item{subject} ) {
    $label = "$item{geo}{label}{$lang} : $item{subject}{label}{$lang}";
    $title = "$item{geo}{signature} $item{subject}{signature}";
    if ( defined $item{keyword} ) {
      $label .= " - $item{keyword}";
      $title .= " - $item{keyword}";
    }
  } else {
    $label =
        "$item{geo}{label}{$lang}"
      . " : <span class='unrecognized'>$item{subject_string}</span>";
    $title = "$item{signature_string}";
  }
  $tag .= " title='$title'>$label</a> &#160;";

  return $tag;
}

sub usage {
  print "usage: $0 { " . join( ' | ', @VALID_SUBSETS ) . " }\n";
}

