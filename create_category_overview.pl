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

my %geo_lookup;
my %subject_nta_lookup;

# category overview pages
foreach my $category_type ( keys %{$definitions_ref} ) {
  my $typedef_ref = $definitions_ref->{$category_type}->{overview};
  foreach my $lang ( @{ $typedef_ref->{languages} } ) {
    my @lines;
    my $title      = $typedef_ref->{title}{$lang};
    my $provenance = $prov{ $typedef_ref->{prov} }{name}{$lang};

    # some header information for the page
    push( @lines,
      '---',
      "title: \"$title\"",
      "etr: category_overview/$category_type",
      '---', '' );
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
      ## TODO improve query with explicit id
      $category->{country}->{value} =~ m/(\d{6})$/;
      my $id        = $1;
      my $signature = $category->{signature}->{value};
      my $label     = $category->{countryLabel}->{value};
      my $counter   = $category->{shCountLabel}->{value}
        . ( $lang eq 'en' ? ' subject folders' : ' Sach-Mappen' );

      # main entry
      my $line =
        "- [$signature $label]" . "(i/$id/about.$lang.html) ($counter)";
      push( @lines, $line );

      # lookup
      $geo_lookup{$id}{signature} = $signature;
      $geo_lookup{$id}{label}{$lang} = $label;
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
    my $provenance = $prov{ $typedef_ref->{prov} }{name}{$lang};

    # read json input (all folders for all categories)
    my $file =
      $folderdata_root->child( $typedef_ref->{result_file} . ".$lang.json" );
    my @entries =
      @{ decode_json( $file->slurp )->{results}->{bindings} };

    # read subject categories and create lookup file
    $file = $klassdata_root->child("subject_by_signature.$lang.json");
    my @subject_categories =
      @{ decode_json( $file->slurp )->{results}->{bindings} };
    foreach my $subject_category (@subject_categories) {
      $subject_nta_lookup{ $subject_category->{signature}->{value} } =
        $subject_category->{categoryLabel}->{value};
    }

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
        push( @output, "## $provenance", '' );
        push( @output,
"# $geo_lookup{$id1_old}{signature} $geo_lookup{$id1_old}{label}{$lang}",
          '' );
        my $backlinktitle =
          $lang eq 'en'
          ? 'Back to Category Overview'
          : 'Zurück zur Systematik-Übersicht';
        push( @output, "[$backlinktitle](../..)", '' );
        push( @output, @lines );
        @lines = ();

        push( @output, '', "[$backlinktitle](..)", '' );

        my $out_dir =
          $web_root->child($category_type)->child('i')->child($id1_old);
        $out_dir->mkpath;
        my $out = $out_dir->child("about.$lang.md");
        $out->spew_utf8( join( "\n", @output ) );
        ## print join( "\n", @output, "\n" );
      }
      $id1_old = $id1;

      # second level control break
      my $firstletter = substr( $signature, 0, 1 );
      if ( $firstletter ne $firstletter_old ) {

        # mainheading
        my $main_heading = $subject_nta_lookup{$firstletter};
        $main_heading =~ s/, Allgemein//;
        push( @lines, '', "### $main_heading", '' );
        $firstletter_old = $firstletter;
      }

      # main entry
      my $counter = $entry->{docs}->{value}
        . ( $lang eq 'en' ? ' documents' : ' Dokumente' );
      my $line =
        "- [$signature $label]" . "($entry->{pm20}->{value}) ($counter)";
      push( @lines, $line );
    }
  }
}

