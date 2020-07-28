#!/bin/env perl
# nbt, 15.7.2020

# create category overview pages from data/rdf/*.jsonld and
# data/klassdata/*.json

use strict;
use warnings;
use utf8;
binmode( STDOUT, ":utf8" );

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number reftype);
use YAML;

my $web_root        = path('../web.public/category');
my $klassdata_root  = path('../data/klassdata');
my $folderdata_root = path('../data/folderdata');
my $rdf_root        = path('../data/rdf');

my %prov = (
  hwwa => {
    name => {
      en => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
      de => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
    }
  },
);

my %subheading_geo = (
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
      en: Folders by Country Category System
      de: Mappen nach Ländersystematik
    result_file: geo_by_signature
    output_dir: ../category/geo
    prov: hwwa
  single:
    result_file: subject_folders
    output_dir: ../category/geo/i
    prov: hwwa
EOF

my %modified;
my %geo                = get_vocab('ag');
my %subject            = get_vocab('je');
my %subheading_subject = get_subheadings( \%subject );

# category overview pages
foreach my $category_type ( keys %{$definitions_ref} ) {
  my $typedef_ref = $definitions_ref->{$category_type}->{overview};
  foreach my $lang (@languages) {
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
    my $backlink = "[$backlinktitle](../about.$lang.html)";
    push( @lines, $backlink, '' );

    # read json input
    my $file =
      $klassdata_root->child( $typedef_ref->{result_file} . ".$lang.json" );
    my @categories =
      @{ decode_json( $file->slurp )->{results}->{bindings} };

    # statistics collecting and output
    my ( $category_count, $sh_folder_count );
    foreach my $category (@categories) {
      if ( $category->{shCountLabel} ) {
        $category_count++;
        $sh_folder_count += $category->{shCountLabel}->{value};
      }
    }
    push(
      @lines,
      (
        $lang eq 'en'
        ? "In total $category_count categories, $sh_folder_count subject folders."
        : "Insgesamt $category_count Systematikstellen, $sh_folder_count Sach-Mappen."
      ),
      ''
    );

    # main loop
    my $firstletter_old = '';
    foreach my $category (@categories) {

      # skip result if no subject folders exist
      next unless exists $category->{shCountLabel};

      # control break?
      my $firstletter = substr( $category->{signature}->{value}, 0, 1 );
      if ( $firstletter ne $firstletter_old ) {
        push( @lines, '', "### $subheading_geo{$firstletter}{$lang}", '' );
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
    }

    push( @lines, '',
      ( $lang eq 'en' ? 'As of ' : 'Stand: ' ) . $modified{ag} );

    push( @lines, '', $backlink, '' );

    my $out = $web_root->child($category_type)->child("about.$lang.md");
    $out->spew_utf8( join( "\n", @lines ) );
  }
}

# individual category pages
foreach my $category_type ( keys %{$definitions_ref} ) {
  my $typedef_ref = $definitions_ref->{$category_type}->{single};
  foreach my $lang (@languages) {

    # read json input (all folders for all categories)
    my $file =
      $folderdata_root->child( $typedef_ref->{result_file} . ".$lang.json" );
    my @entries =
      @{ decode_json( $file->slurp )->{results}->{bindings} };

    # read subject categories and create lookup file
    $file = $klassdata_root->child("subject_by_signature.$lang.json");
    my @subject_categories =
      @{ decode_json( $file->slurp )->{results}->{bindings} };

    # main loop
    my %cat_meta = (
      category_type        => $category_type,
      provenance           => $prov{ $typedef_ref->{prov} }{name}{$lang},
      folder_count_first   => 0,
      document_count_first => 0,
    );
    my @lines;
    my $id1_old         = '';
    my $firstletter_old = '';
    foreach my $entry (@entries) {
      ##print Dumper $entry;exit;

      # TODO improve query to get values more directly?
      $entry->{pm20}->{value} =~ m/(\d{6}),(\d{6})$/;
      my $id1   = $1;
      my $id2   = $2;
      my $label = "$subject{$id2}{notation} ";
      if ( $subject{$id2}{prefLabel}{$lang} ) {
        $label .= $subject{$id2}{prefLabel}{$lang};
      } else {

        # temporary, German label in italics
        $label .= "_$subject{$id2}{prefLabel}{de}_";
      }

      # first level control break - new category page
      if ( $id1_old ne '' and $id1 ne $id1_old ) {
        output_category_page( $lang, \%cat_meta, $id1_old, \@lines );
        @lines = ();
      }
      $id1_old = $id1;

      # second level control break (label starts with signature)
      my $firstletter = substr( $label, 0, 1 );
      if ( $firstletter ne $firstletter_old ) {

        # subheading
        my $subheading = $subheading_subject{$firstletter}{$lang}
          || $subheading_subject{$firstletter}{de};
        $subheading =~ s/, Allgemein$//i;
        $subheading =~ s/, General$//i;
        push( @lines, '', "### $subheading", '' );
        $firstletter_old = $firstletter;
      }

      # main entry
      my $counter = $entry->{docs}->{value}
        . ( $lang eq 'en' ? ' documents' : ' Dokumente' );
      my $line = "- [$label]" . "($entry->{pm20}->{value}) ($counter)";
      push( @lines, $line );

      # statistics
      $cat_meta{folder_count_first}++;
      $cat_meta{document_count_first} += $entry->{docs}{value};
    }

    # output of last category
    output_category_page( $lang, \%cat_meta, $id1_old, \@lines );
  }
}

############

sub get_vocab {
  my $vocab = shift or die "param missing";

  my %cat;
  foreach my $lang (@languages) {
    my $file = $rdf_root->child("$vocab.skos.jsonld");
    my @categories =
      @{ decode_json( $file->slurp )->{'@graph'} };

    # read jsonld graph
    foreach my $category (@categories) {

      my $type = $category->{'@type'};
      if ( $type eq 'skos:ConceptScheme' ) {
        $modified{$vocab} = $category->{modified};
      } elsif ( $type eq 'skos:Concept' ) {

        # skip orphan entries
        next unless exists $category->{broader};

        my $id = $category->{identifier};
        $cat{$id}{notation}     = $category->{notation};
        $cat{$id}{notationLong} = $category->{notationLong};

        foreach my $pref ( as_array( $category->{prefLabel} ) ) {
          $cat{$id}{prefLabel}{ $pref->{'@language'} } = $pref->{'@value'};
        }
        foreach my $note ( as_array( $category->{scopeNote} ) ) {
          $cat{$id}{scopeNote}{ $note->{'@language'} } = $note->{'@value'};
        }
      } else {
        die "Unexpectend type $type\n";
      }
    }
  }
  return %cat;
}

sub as_array {
  my $ref = shift;

  my @list = ();
  if ($ref) {
    if ( reftype($ref) eq 'ARRAY' ) {
      @list = @{$ref};
    } else {
      @list = ($ref);
    }
  }
  return @list;
}

sub output_category_page {
  my $lang         = shift or die "param missing";
  my $cat_meta_ref = shift or die "param missing";
  my $id           = shift or die "param missing";
  my $lines_ref    = shift or die "param missing";
  my %cat_meta     = %{$cat_meta_ref};

  my $title = "$geo{$id}{notation} $geo{$id}{prefLabel}{$lang}";
  my @output;
  push( @output,
    '---',
    "title: \"$title\"",
    "etr: category/$cat_meta{category_type}/$geo{$id}{notation}",
    '---', '' );
  push( @output, "## $cat_meta{provenance}", '' );
  push( @output, "# $title", '' );
  my $backlinktitle =
    $lang eq 'en'
    ? 'Back to Category Overview'
    : 'Zurück zur Systematik-Übersicht';
  my $backlink = "[$backlinktitle](../../about.$lang.html)";
  push( @output, $backlink, '', '' );

  if ( $geo{$id}{scopeNote}{$lang} ) {
    push( @output, "> Scope Note: $geo{$id}{scopeNote}{$lang}", '' );
  }

  # output statistics
  push(
    @output,
    (
      $lang eq 'en'
      ? "In total $cat_meta{folder_count_first} subject folders,"
        . " $cat_meta{document_count_first} documents."
      : "Insgesamt $cat_meta{folder_count_first} Sach-Mappen,"
        . " $cat_meta{document_count_first} Dokumente."
    ),
    ''
  );
  $cat_meta_ref->{folder_count_first}   = 0;
  $cat_meta_ref->{document_count_first} = 0;

  # the actual page content
  push( @output, @{$lines_ref} );

  my $last_modified =
    $modified{ag} ge $modified{je} ? $modified{ag} : $modified{je};
  push( @output,
    '', ( $lang eq 'en' ? 'As of ' : 'Stand: ' ) . $last_modified, '' );
  push( @output, $backlink, '', '' );

  my $out_dir =
    $web_root->child( $cat_meta{category_type} )->child('i')->child($id);
  $out_dir->mkpath;
  my $out = $out_dir->child("about.$lang.md");
  $out->spew_utf8( join( "\n", @output ) );
  ## print join( "\n", @output, "\n" );
}

sub get_subheadings {
  my $hash_ref = shift or die "param missing";

  my %subheading;
  foreach my $cat ( keys %{$hash_ref} ) {
    my $notation = $hash_ref->{$cat}{notation};
    next unless $notation =~ m/^[a-z]$/;
    foreach my $lang (@languages) {
      $subheading{$notation}{$lang} = $hash_ref->{$cat}{prefLabel}{$lang}
        || $hash_ref->{$cat}{prefLabel}{de};
    }
  }
  return %subheading;
}

