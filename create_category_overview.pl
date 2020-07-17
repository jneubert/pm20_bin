#!/bin/env perl
# nbt, 15.7.2020

# create category overview pages from data/klassdata/*.json

use strict;
use warnings;
use utf8;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number);
use YAML;

my $web_root       = path('../web.public/category');
my $klassdata_root = path('../data/klassdata');

my %prov = (
  hwwa => {
    name => {
      en => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
      de => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
    }
  },
);

my @languages = qw/ de en /;

# TODO create and load external yaml
my $definitions_ref = YAML::Load(<<'EOF');
geo:
  title:
    en: Country Category System
    de: Ländersystematik
  result_file: geo_by_signature
  output_dir: ../category/geo
  prov: hwwa
EOF

foreach my $lang (@languages) {
  foreach my $category_type ( keys %{$definitions_ref} ) {
    my @lines;
    my $typedef_ref = $definitions_ref->{$category_type};
    my $title       = $typedef_ref->{title}{$lang};

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
    foreach my $category (@categories) {

      # skip result if no subject folders exist
      next unless exists $category->{shCountLabel};

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
