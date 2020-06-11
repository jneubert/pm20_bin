#!/bin/env perl
# nbt, 2020-04-20

# Create symlinks for ranges of film images in web.public
# plus an overview page
# (requires a checked.yaml file in the film directory)

# TODO
# - rename {image_name}.locked.txt {image_name}.access_locked.txt
# - implement separate procedure with
#   - evaluate {image_name}.access_locked.txt and meta.yaml with author_(name|id|qid), date, death_year
#   - (re-)create {image_name}.lock files based on both
# - check only the latter here
# - update meta.en.md

use strict;
use warnings;
use utf8;

use Data::Dumper;
use JSON;
use Path::Tiny;
use YAML::Tiny;

binmode( STDOUT, ":utf8" );

my $film_root      = path('/disc1/pm20/film/');
my $pub_film_root  = path('/disc1/pm20/web.public/film/');
my $klassdata_root = path('/disc1/pm20/data/klassdata/');

my ( $holding, $film_id, $dir );

# datastructure for overview page with links
#
# {country_signature}
#   {film_id}
#     title_de
#     title_en
#     link
#     page_count
#
my %pub_film_sect;

# arguments
if ( scalar(@ARGV) < 1 ) {
  &usage;
  exit;
} else {
  $holding = $ARGV[0];
  $film_id = $ARGV[1] || undef;
  if ( not $holding =~ m/h(1|2)\/(sh|wa|co)/ ) {
    &usage;
    exit;
  }
}

# lookup file
# (currently, only in German)
my $lookup = decode_json( $klassdata_root->child('ag_lookup.json')->slurp );

# processing
if ( defined $film_id ) {

  # one single film directory
  $film_id =~ m/(S|W|A|F)(\d{4})(H|K)/ or die "Film id $film_id not valid\n";
  $dir = $film_root->child($holding)->child($film_id);
  link_film($dir);
} else {

  # all directories of the holding
  $film_root->child($holding)->visit( \&link_film );
}

create_overview_page( $holding, \%pub_film_sect );

################

sub usage {
  print "usage: (h1|h2)/(sh|wa|co) {film-id}\n";
}

sub link_film {
  my $dir = shift or die "param missing";
  return unless -d $dir;

  # iterate over checked sections
  my $checked_fn = $dir->child('checked.yaml');
  return unless -f $checked_fn;

  # prepare target dir
  my $target_dir = get_target_dir($dir);
  prepare_target_dir($target_dir);

  my $checked = YAML::Tiny->read($checked_fn);
  foreach my $section ( @{$checked} ) {

    # skip empty "undef" section at the end
    next if not $section;

    print Dumper $section;
    parse_section( $checked_fn, $section );
    my $count = link_section( $dir, $section );

    # fill data structure for overview page
    $section->{count} = $count;
    my ( $holding, $film_id ) = parse_dirname( $checked_fn->parent );
    push( @{ $pub_film_sect{ $section->{country} }{$film_id} }, $section );
  }
}

sub prepare_target_dir {
  my $target_dir = shift or die "param missing";

  # create empty public film directory or purge symlinks from it
  if ( !-d $target_dir ) {
    $target_dir->mkpath;
  } else {
    foreach my $symlink ( $target_dir->children ) {
      next unless -l $symlink;
      $symlink->remove;
    }
  }
  return $dir;
}

sub link_section {
  my $dir     = shift or die "param missing";
  my $section = shift or die "param missing";

  # TODO extend for half films
  my $count = 0;
  for ( my $i = $section->{start} ; $i <= $section->{end} ; $i++ ) {

    $dir =~ m/(S|W|A|F)(\d{4})(H|K)/ or die "Film id in $dir not valid\n";
    my $start_chr = $1;
    my $film_no   = $2;
    my $end_chr   = $3;

    # build and check source file name
    my $img_fn =
      $start_chr . "$film_no" . sprintf( "%04d", $i ) . $end_chr . '.jpg';
    my $src = $dir->child($img_fn);
    die "File $src missing: $!\n" if not $src->is_file;

    # check if a the source file is locked
    next if is_locked($src);
    $count++;

    # build target file name and create as symlink
    my $target_dir = get_target_dir($dir);
    my $target     = $target_dir->child($img_fn);
    symlink( $src, $target ) or die "Could not create symlink $target: $!\n";

    print "$i: $src\n";
  }
  return $count;
}

sub get_target_dir {
  my $dir = shift or die "param missing";

  return $pub_film_root->child( $dir->relative($film_root) );
}

sub is_locked {
  my $src = shift or die "param missing";

  ( my $lock = $src ) =~ s/(.*?)\.jpg/$1.locked.txt/;

  # TODO extend with date/qid from file contents for moving wall

  if ( -f $lock ) {
    return 1;
  } else {
    return 0,;
  }
}

sub parse_section {
  my $checked_fn = shift or die "param missing";
  my $section    = shift or die "param missing";

  # verify section data structure
  my @required_fields =
    qw/ title_de title_en start end checked_by checked_date country /;

  foreach my $field (@required_fields) {
    if ( not defined $section->{$field} ) {
      die "missing $field field in $checked_fn\n";
    }
  }

  # amend with start link name
  my $link =
    $checked_fn->parent->relative($film_root)->child( $section->{start} );
  $section->{link} = "$link";
}

sub parse_dirname {
  my $dir = shift or die "param missing";

  $dir =~ m;film/(h(?:1|2)/(?:co|sh|wa))/((?:S|A|F|W)\d{4}(?:H|K}));
    or die "Could not parse dir name $dir\n";
  my $holding = $1;
  my $film_id = $2;

  return ( $holding, $film_id );
}

sub create_overview_page {
  my $holding       = shift or die "param missing";
  my $pub_film_sect = shift or die "param missing";

  my %page_title = (
    de => 'Veröffentlichte Abschnitte aus digitalisierten Rollfilmen',
    en => 'Published sections from digitized roll films',
  );

  foreach my $lang (qw/ de en/) {
    my $head = <<"EOF";
---
title: $page_title{$lang}
---

# $page_title{$lang}

EOF

    my @page;
    foreach my $country ( sort keys %{$pub_film_sect} ) {
      if ( $lang eq 'de' ) {
        push( @page, "## " . $lookup->{$country} );
      } else {
        push( @page, "## $country" );
      }
      foreach my $film_id ( sort keys %{ $pub_film_sect->{$country} } ) {
        push( @page, "### $film_id" );
        foreach my $section ( @{ $pub_film_sect->{$country}->{$film_id} } ) {
          my $line = '- ['
            . $section->{ 'title_' . $lang } . ']('
            . $section->{link} . ') ('
            . $section->{count} . ')';
          push( @page, $line );
        }
      }
    }
    ( my $holding_flat = $holding ) =~ s;/;_;;
    my $fn = $pub_film_root->child("public_section.$holding_flat.$lang.md");
    $fn->spew_utf8( $head . join( "\n\n", @page ) );
    print "\n$fn\n";
  }
}
