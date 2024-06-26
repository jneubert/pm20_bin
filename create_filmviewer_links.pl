#!/bin/env perl
# nbt, 2022-01-24

# creates html fragments with image links for filmviewer

# TODO extend to proper tags in English
# perhaps link to primary group or (company) folder

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

# TODO fix dev dir
Readonly my $FILM_ROOT     => path('/pm20/web/film');
##Readonly my $FILM_ROOT     => path('/tmp/film');
Readonly my $FILMDATA_ROOT => path('/pm20/data/filmdata');
Readonly my @COLLECTIONS   => qw/ co sh wa /;
Readonly my @LANGUAGES     => qw/ en de /;
Readonly my @VALID_SUBSETS => qw/ h1_sh h1_co h1_wa h2_co h2_sh h2_wa /;
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

print "\nsubset $subset\n";

my %vocab;
$vocab{geo}     = ZBW::PM20x::Vocab->new('geo');
$vocab{subject} = ZBW::PM20x::Vocab->new('subject');
$vocab{ware}    = ZBW::PM20x::Vocab->new('ware');

# all start positions of sections, from zotero and film lists
my %position;

# TODO remove obsolete methods and variables
my %has_zotero;
##parse_zotero($subset);
my %is_online;
##parse_filmlist($subset);

my $olditem_ref = {};
my @films       = ZBW::PM20x::Film->films($subset);

foreach my $film (@films) {

  # TODO fix dev restriction
  ##next
  ##  unless ( $film->name eq 'W2001H'
  ##  or $film->name eq 'S2806H'
  ##  or $film->name eq 'F2008H' );

  my $film_name = $film->name;
  print "  $film_name\n";

  # read file info from disk
  my %image;
  my $film_dir = $subset_root->child($film_name);
  my @files    = $film_dir->children(qr/\.jpg\z/);
  foreach my $file (@files) {
    my $img_nr = $file->basename('.jpg');
    $img_nr =~ s/[SAFW]\d{4}(\d{4})[HK]/$1/;
    $image{$img_nr} =
      $file->relative('/pm20/web')->parent->child($img_nr)->absolute('/');
  }
  $image{'0000'} = undef;
  $image{'9999'} = undef;

  my %position;
  foreach my $section ( $film->sections ) {
    my $section_uri = $section->{'@id'};
    ( my $img_nr = $section_uri ) =~ s;^(?:.+)/$film_name/(\d{4})(?:/.+)?;$1;;

    # TODO workaround for first image from filmlist
    if ( $section_uri =~ m/$film_name\/1$/ ) {
      $img_nr = '0001';
    }
    $position{$img_nr} = $section;
  }

  # merge
  my $current_olditem_ref;
  foreach my $lang (@LANGUAGES) {
    $current_olditem_ref = $olditem_ref;
    my @links;
    foreach my $img_nr ( sort keys %image ) {
      if ( defined $position{$img_nr} ) {

        my %item = %{ $position{$img_nr} };
        ## skip items without identified geo (should not occur)
        ## often occurs within wa - TODO check
        ## next if not defined $item{geo};

        # TODO replace dumbed-down version of item tags (only based on title,
        # with optional geo enhancement)
        push( @links,
          '<br />',
          get_item_tag_dumb( $lang, $img_nr, \%item, $current_olditem_ref ) );

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

##print Dumper \%has_zotero;

# count films which were not processed via Zotero
my $cnt_open = 0;

#foreach my $film ( sort keys %position ) {
#  next if defined $has_zotero{$film_name} or $is_online{$film};
#  ##print "Film $film without zotero\n";
#  $cnt_open++;
#}

# output statistics
# TODO fix counting
##print "$subset films: ", scalar( keys %is_online ), " online, ",
##  scalar( keys %has_zotero ), " with zotero, $cnt_open open\n";

####################

# OBSOLETE
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
      $film_part =~ s/.+?\/([AFSW].+?)\/\d{4}$/$1/;
      $position{$film_part}{$page} = $item;
      $has_zotero{$film_part}++;
    }
  }
}

# OBSOLETE
sub parse_filmlist {
  my $subset = shift or die "param mssing";

  my @films = ZBW::PM20x::Film->films($subset);

  foreach my $entry (@films) {
    my $film = $entry->{film_id};
    print Dumper $entry;
    exit;

    POS:
    foreach my $pos ( 'start', 'end' ) {
      my $ord = $pos eq 'start' ? '0000' : '9999';

      my %sig;
      my $signature_string = $entry->{"${pos}_sig"};

      $position{$film}{$ord}{signature_string} = $signature_string;
      my $date = $entry->{"${pos}_date"};
      $position{$film}{$ord}{date} = $date;

      # parse signature according to film type
      if ( $film =~ m/^S/ ) {
        if ( $signature_string =~
          m/(?: : (.+?) )?\[(\S+)(?:\s+(.+?))?(?: - (.+))?\]$/ )
        {
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
      } elsif ( $film =~ m/^[AF]/ ) {
        if ( $signature_string =~ m/^([A-H]) ?(\d{1,3}[a-z]?) (.+)$/ ) {

          # fix sloppy signature string
          $signature_string = "$1$2 $3";
          $sig{geo} = "$1$2";
        } else {
          warn "cannot parse signature of ", Dumper $entry;
        }
      } elsif ( $film =~ m/^W/ ) {

        # TODO include real translations
      }

      ## q&d fix "Osmanisches Reich/Türkei" signature (already online)
      if ( $sig{geo} ) {
        $sig{geo} =~ s/A43\/B21/A43/;
        ## unknown E87 is probably Argentina
        ## TODO remove when fixed in filmlist
        $sig{geo} =~ s/E87/E86/;
      }

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

sub get_item_tag_dumb {
  my $lang        = shift or die "param missing";
  my $img_nr      = shift or die "param missing";
  my $item_ref    = shift or die "param missing";
  my $olditem_ref = shift or die "param missing";

  my %item = %{$item_ref};

  # TODO extend film dataset to collection
  my $collection;
  if ( not $item{collection} ) {
    ( $collection = $item{'@id'} ) =~ s;^.+?/film/h[12]/(co|sh|wa)/.+$;$1;;
  }

  # TODO replace q&d signature lookup with proper geo in item
  my $geo_label;
  if ( $collection eq 'co' or $collection eq 'sh' ) {
    if ( $item{notation} ) {
      ( my $geo_sig ) = split( / /, $item{notation} );
      my $geo_id = $vocab{geo}->lookup_signature($geo_sig);
      $geo_label = $vocab{geo}->label( $lang, $geo_id );
      $item_ref->{geo}{'@id'} = $vocab{geo}->category_uri($geo_id);
    }
  }

  my $new_geo = 0;
  if (
    ## not relevant for ware!
    not defined $item_ref->{ware}
    and (
      not defined $olditem_ref->{geo}
      or (  $item_ref->{geo}{'@id'} ne $olditem_ref->{geo}{'@id'}
        and $img_nr ne '9999' )
    )
    )
  {
    $new_geo = 1;
  }

  # title is used to display the notation
  my ( $label, $linktitle );
  $label     = $item{title};
  $linktitle = $label;

  # extend with bold country for sh and co on first occurence
  if ($new_geo) {
    if ( $collection eq 'co' ) {
      if ($geo_label) {
        $label = "<b>$geo_label</b> $label";
      }

    } elsif ( $collection eq 'sh' ) {

      # label not necessarily represents a folder!
      if ( $label =~ m/^(.+)?( : .+)$/ ) {
        $label = "<b>$1</b>$2";
      } else {
        $label = "<b>$label</b>";
      }
    }
  }

  my $tag = "<a id='tag_$img_nr' title='$linktitle'>$label</a> &#160;";

  return $tag;
}

sub usage {
  print "usage: $0 { " . join( ' | ', @VALID_SUBSETS ) . " }\n";
}

## outdated version
sub get_item_tag {
  my $lang        = shift or die "param missing";
  my $img_nr      = shift or die "param missing";
  my $item_ref    = shift or die "param missing";
  my $olditem_ref = shift or die "param missing";
  my %item        = %{$item_ref};

  # label for geo - sometimes not existing for wares
  my $geolabel = $item{geo}{label}{$lang} || '';

  my $new_geo = 0;
  if (
    ## not relevant for ware!
    not defined $item_ref->{ware_string}
    and (
      not defined $olditem_ref->{geo}
      or (  $item_ref->{geo}{id} ne $olditem_ref->{geo}{id}
        and $img_nr ne '9999' )
    )
    )
  {
    $new_geo = 1;
  }

  # title is used to display the notation
  my ( $label, $title );
  if ( defined $item{company_string} ) {
    if ($new_geo) {
      $label = "<b>$geolabel</b> : $item{company_string}";
    } else {
      $label = $item{company_string};
    }
    if ( $item{signature} ) {
      $title = "$item{signature}";
    } else {
      $title = "$item{signature_string}";
    }
  } elsif ( defined $item{ware_string} ) {
    $label = $item{ware_string};
    ##if ($geolabel) {
    ##  $label .= " : $geolabel";
    ##}
    if ( $item{geo_string} ) {
      $label .= " : $item{geo_string}";
    }
    $title = $label;
  } elsif ( defined $item{subject} ) {
    if ($new_geo) {
      $geolabel = "<b>$geolabel</b>";
    }
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
    if ( defined $olditem_ref->{subject_string}
      and $item{subject_string} eq $olditem_ref->{subject_string} )
    {
      $label .= " <span class='date-limit'>($item{date} - )</span>";
    }
  }
  if ( $img_nr eq '9999' and $item{date} ) {
    $label .= " <span class='date-limit'>( - $item{date})</span>";
  }

  my $tag = "<a id='tag_$img_nr' title='$title'>$label</a> &#160;";

  $olditem_ref = $item_ref;

  return $tag;
}

