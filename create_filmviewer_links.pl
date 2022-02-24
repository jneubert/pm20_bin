#!/bin/env perl
# nbt, 2022-01--24

# creates html fragments with image links for filmviewer

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

Readonly my $FILM_ROOT     => path('/pm20/web/film');
Readonly my $FILMDATA_ROOT => path('/pm20/data/filmdata');
Readonly my @COLLECTIONS   => qw/ co sh wa /;
Readonly my @LANGUAGES     => qw/ en de /;
Readonly my @VALID_SUBSETS => qw/ h1_sh h1_co /;
## films in film lists, but not on disk
Readonly my @MISSING_FILMS =>
  qw/ S0005H S0010H S0371H S0843H S1009H S1010H S9393 S9398 /;

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

# debug info
##path('/tmp/ein.json')->spew( encode_json(\%position) );

my $olditem_ref = {};
foreach my $film ( sort keys %position ) {
  ##next unless ( $film eq 'S0204H' or $film eq 'S0205H' );

  # compute image numbers and link paths
  my %image;
  my $film_dir = $subset_root->child($film);
  my @files    = $film_dir->children(qr/\.jpg\z/);
  foreach my $file (@files) {
    my $img_nr = $file->basename('.jpg');
    $img_nr =~ s/[SAF]\d{4}(\d{4})[HK]/$1/;
    $image{$img_nr} =
      $file->relative('/pm20/web')->parent->child($img_nr)->absolute('/');
  }
  $image{'0000'} = undef;
  $image{'9999'} = undef;

  # merge
  my @postions = sort keys %{ $position{$film}{items} };
  my $current_olditem_ref;
  foreach my $lang (@LANGUAGES) {
    $current_olditem_ref = $olditem_ref;
    my @links;
    foreach my $img_nr ( sort keys %image ) {
      if ( defined $position{$film}{$img_nr} ) {
        my %item = %{ $position{$film}{$img_nr} };
        ## skip items without identified geo (should not occur)
        next if not defined $item{geo};
        push( @links,
          '<br />',
          get_item_tag( $lang, $img_nr, \%item, $current_olditem_ref ) );

        $current_olditem_ref = \%item;
      }
      if ( defined $image{$img_nr} ) {
        push( @links,
          "<a id='img_$img_nr' href='$image{$img_nr}'>$img_nr</a> &#160;" );
      }
    }

    # save links
    $film_dir->child("links.$lang.html.frag")
      ->spew_utf8( join( "\n", @links ) );
  }
  $olditem_ref = $current_olditem_ref;
}

####################

sub parse_zotero {
  my $subset = shift or die "param mssing";

  my %film =
    %{ decode_json( $FILMDATA_ROOT->child("zotero.$subset.json")->slurp ) };

  # Zotero film collections may contain part _1 and _2 of a film, so
  # we have to parse the id for the actual film directory
  foreach my $film ( sort keys %film ) {
    foreach my $item_key ( sort keys %{ $film{$film}{item} } ) {
      my $item = $film{$film}{item}{$item_key};
      my $page = $item->{id};
      $page =~ s/.*?\/(\d{4})$/$1/;
      my $film_part = $item->{id};
      $film_part =~ s/.+?\/([AFS].+?)\/\d{4}$/$1/;
      $position{$film_part}{$page} = $item;
    }
  }
}

sub parse_filmlist {
  my $subset = shift or die "param mssing";

  my @filmlist =
    @{ decode_json( $FILMDATA_ROOT->child("$subset.json")->slurp ) };

  foreach my $entry (@filmlist) {
    my $film = $entry->{film_id};

    # skip non-existing film numbers
    next if grep( /^$film$/, @MISSING_FILMS );

    POS:
    foreach my $pos ( 'start', 'end' ) {
      my $ord = $pos eq 'start' ? '0000' : '9999';

      my %sig;
      my $signature_string = $entry->{"${pos}_sig"};
      $position{$film}{$ord}{signature_string} = $signature_string;
      my $date = $entry->{"${pos}_date"};
      $position{$film}{$ord}{date} = $date;
      if ( $signature_string =~ m/(?: : (.+?) )?\[(\S+)(?:\s+(.+?))?(?: - (.+))?\]$/ ) {
        ## string version of the subject
        $position{$film}{$ord}{subject_string} = $1;
        $sig{geo}                              = $2;
        $sig{subject}                          = $3;
        ## save optional keyword for later use
        $position{$film}{$ord}{keyword} = $4;
      } else {
        warn "cannot parse signature of ", Dumper $entry;
      }

      # substitute known variants in signatures
      if ( $sig{subject} ) {
        $sig{subject} =~ s/q sm/q Sm/;
        $sig{subject} =~ s/q Nr /q Sm/;
      }
      ## q&d fix "Osmanisches Reich/Türkei" signature (already online)
      $sig{geo} =~ s/A43\/B21/A43/;

      foreach my $voc ( sort keys %sig ) {
        next unless $sig{$voc};

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
            die "FATAL $film: $pos geo signature $sig{geo} not recognized\n";
          } else {
            warn "$film: $pos signature $sig{$voc} not found\n";
          }
        }
      }
    }
  }
}

sub get_item_tag {
  my $lang        = shift or die "param missing";
  my $img_nr      = shift or die "param missing";
  my $item_ref    = shift or die "param missing";
  my $olditem_ref = shift or die "param missing";
  my %item        = %{$item_ref};

  # label for new geo in bold
  my $geolabel = $item{geo}{label}{$lang};
  if (
    not defined $olditem_ref->{geo}
    or ( $item_ref->{geo}{id} ne $olditem_ref->{geo}{id} and $img_nr ne '9999' )
    )
  {
    ## debug
    ##if ( defined $olditem_ref->{geo} and $item_ref->{id} =~ /0205/ and $lang eq 'en' ) {
    ##  print Dumper $olditem_ref, $item_ref
    ##}
    $geolabel = "<b>$geolabel</b>";
  }

  my ( $label, $title );
  if ( defined $item{subject} ) {
    $label = "$geolabel : $item{subject}{label}{$lang}";
    $title = "$item{geo}{signature} $item{subject}{signature}";
    if ( defined $item{keyword} ) {
      $label .= " - $item{keyword}";
      $title .= " - $item{keyword}";
    }
  } else {
    $label = "$geolabel";
    if ( $item{subject_string} ) {
      $label .= " : <span class='unrecognized'>$item{subject_string}</span>";
    }
    $title = "$item{signature_string}";
  }

  # add date to start and end tags
  if ( $img_nr eq '0000' and $item{date} ) {
    ## if continued
    if ( defined $olditem_ref->{subject_string} and $item{subject_string} eq $olditem_ref->{subject_string} ) {
      $label .= " <span class='date-limit'>($item{date} - )</span>";
    }
  }
  if ( $img_nr eq '9999' and $item{date} ) {
    $label .= " <span class='date-limit'>( - $item{date})</span>";
  }

  my $tag = "<a id='tag_$img_nr' title='$title'>$label</a> &#160;";

  return $tag;
}

sub usage {
  print "usage: $0 { " . join( ' | ', @VALID_SUBSETS ) . " }\n";
}

