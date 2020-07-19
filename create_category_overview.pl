#!/bin/env perl
# nbt, 15.7.2020

# create category overview pages from data/klassdata/*.json

use strict;
use warnings;
use utf8;
binmode( STDOUT, ":utf8" );

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number);
use YAML;

my $web_root        = path('../web.public/category');
my $klassdata_root  = path('../data/klassdata');
my $folderdata_root = path('../data/folderdata');

my %prov = (
  hwwa => {
    name => {
      en => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
      de => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
    }
  },
);

my %subheading = (
  A => {
    de => 'Europa',
    en => 'Europe',
  },
  B => {
    de => 'Asien',
    en => 'Asia',
  },
  C => {
    de => 'Afrika',
    en => 'Africa',
  },
  D => {
    de => 'Australien und Ozeanien',
    en => 'Australia and Oceania',
  },

  E => {
    de => 'Amerika',
    en => 'America',
  },

  F => {
    de => 'Polargebiete',
    en => 'Polar regions',
  },

  G => {
    de => 'Meere',
    en => 'Seas',
  },

  H => {
    de => 'Welt',
    en => 'World',
  },
);

my @languages = qw/ de en /;

# TODO create and load external yaml
my $definitions_ref = YAML::Load(<<'EOF');
geo:
  overview:
    title:
      en: Folder Overview by Country Category System
      de: Mappen-Übersicht nach Ländersystematik
    result_file: geo_by_signature
    output_dir: ../category/geo
    prov: hwwa
    languages:
      - de
      - en
  single:
    result_file: subject_folders
    output_dir: ../category/geo/i
    prov: hwwa
    languages:
      - de
EOF

# category overview pages
foreach my $category_type ( keys %{$definitions_ref} ) {
  my $typedef_ref = $definitions_ref->{$category_type}->{overview};
  foreach my $lang ( @{ $typedef_ref->{languages} } ) {
    my @lines;
    my $title = $typedef_ref->{title}{$lang};

    # some header information for the page
    push( @lines,
      '---',
      "title: \"$title\"",
      "etr: category_overview/$category_type",
      '---', '' );
    my $provenance = $prov{ $typedef_ref->{prov} }{name}{$lang};
    push( @lines, "## $provenance" );
    push( @lines, "# $typedef_ref->{title}{$lang}", '' );
    my $backlinktitle =
      $lang eq 'en' ? 'Back to Category systems' : 'Zurück zu Systematiken';
    push( @lines, "[$backlinktitle](..)", '' );

    # read json input
    my $file =
      $klassdata_root->child( $typedef_ref->{result_file} . ".$lang.json" );
    my @categories =
      @{ decode_json( $file->slurp )->{results}->{bindings} };

    # main loop
    my $firstletter_old = '';
    foreach my $category (@categories) {

      # skip result if no subject folders exist
      next unless exists $category->{shCountLabel};

      # control break?
      my $firstletter = substr( $category->{signature}->{value}, 0, 1 );
      if ( $firstletter ne $firstletter_old ) {
        push( @lines, '', "### $subheading{$firstletter}{$lang}", '' );
        $firstletter_old = $firstletter;
      }

      ##print Dumper $category; exit;
      my $line =
        "- [$category->{signature}->{value} $category->{countryLabel}->{value}]"
        . "($category->{country}->{value}) ($category->{shCountLabel}->{value})";
      push( @lines, $line );

    }

    push( @lines, '', "[$backlinktitle](..)", '' );

    my $out = $web_root->child($category_type)->child("about.$lang.md");
    $out->spew_utf8( join( "\n", @lines ) );
  }
}

# individual category pages
foreach my $category_type ( keys %{$definitions_ref} ) {
  my $typedef_ref = $definitions_ref->{$category_type}->{single};
  foreach my $lang ( @{ $typedef_ref->{languages} } ) {

    # read json input (all folders for all categories)
    my $file =
      $folderdata_root->child( $typedef_ref->{result_file} . ".$lang.json" );
    my @entries =
      @{ decode_json( $file->slurp )->{results}->{bindings} };

    # main loop
    my @lines;
    my $id1_old         = '';
    my $firstletter_old = '';
    foreach my $entry (@entries) {
      ##print Dumper $entry;exit;

      # TODO improve query to get values more directly
      $entry->{pm20}->{value} =~ m/(\d{6}),(\d{6})$/;
      my $id1 = $1;
      my $id2 = $2;
      ## TODO look up signature form hash %signature (with ID as key)
      my $signature = $entry->{subjectNta}->{value};
      ( my $title, my $label ) = split( / : /, $entry->{pm20Label}->{value} );

      # first level control break - new category page
      if ( $id1_old ne '' and $id1 ne $id1_old ) {
        my @output;
        push( @output,
          '---',
          "title: \"$title\"",
          "etr: category/$category_type/xxx",
          '---', '' );
        my $provenance = $prov{ $typedef_ref->{prov} }{name}{$lang};
        push( @output, "## $provenance", '' );
        push( @output, "# $title",       '' );
        my $backlinktitle =
          $lang eq 'en'
          ? 'Back to Category Overview'
          : 'Zurück zur Systematik-Übersicht';
        push( @output, "[$backlinktitle](../..)", '' );
        push( @output, @lines );
        @lines = ();

        push( @output, '', "[$backlinktitle](..)", '' );

        my $out_dir = $web_root->child($category_type)->child('i')->child($id1);
        $out_dir->mkpath;
        my $out = $out_dir->child("about.$lang.md");
        $out->spew_utf8( join( "\n", @output ) );
        print join( "\n", @output, "\n" );
      }
      $id1_old = $id1;

      # second level control break
      my $firstletter = substr( $signature, 0, 1 );
      if ( $firstletter ne $firstletter_old ) {
        push( @lines, '', "### $label", '' );
        $firstletter_old = $firstletter;
      }

      # main entry
      my $line =
          "- [$signature $label]"
        . "($entry->{pm20}->{value}) ($entry->{docs}->{value})";
      push( @lines, $line );
    }
  }
}

