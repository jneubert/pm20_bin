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

# general introduction text
my %about_text = (
  de => q{
Nur grob geschätzt ein Fünftel des digitalisierten Bestandes des
Länder-/Sacharchivs bis 1949 ist in Mappen erschlossen und über diese
Systematik zugänglich. Die entsprechenden Länder und Regionen - z.B. der Nahe
Osten, Japan, die ehemaligen deutschen Kolonien oder Hamburg - sind unten mit
"komplett" gekennzeichnet. Viele kleine und große Länder wie Großbritannien,
China, Indien, Frankreich oder die USA fehlen jedoch ganz oder sind nur mit
einzelnen, aus der "Forschungsstelle für das Übersee-Deutschtum" übernommenen
Mappen vertreten.

Alles nicht aufbereitete Material ist unter [digitalisierte
Filme](/film/h1_sh.de.html) zugänglich, auch solches aus der [2. Verfilmung
(bis 1960)](/film/h2_sh.de.html) - aus urheberrechtlichen Gründen allerdings
leider nur im ZBW-Lesesaal. Die
[vollständige Ländersystematik](https://pm20.zbw.eu/report/pm20_result.de.html?jsonFile=vocab/geo_by_signature.json&main_title=L%C3%A4ndersystematik)
ist online verfügbar.
  },
  en => q{
Of the PM20 Länder-/Sacharchiv up to 1949, only a rough estimate of one-fifth
of the digitized holdings are indexed in folders and accessible via this
category system. The corresponding countries and regions - e.g. the Middle
East, Japan, the former German colonies or Hamburg - are marked "complete" in
the list below. However, many small and large countries such as Great Britain,
China, India, France or the USA are missing at all or are only represented by a
few folders originating from the "Forschungsstelle für das Übersee-Deutschum".

All unprocessed material is accessible under [digitized
films](/film/h1_sh.de.html) (in German), including material from the [second
filming (until 1960)](/film/h2_sh.de.html) - for copyright reasons, however,
unfortunately only in the ZBW reading room. The [complete country category
system](https://pm20.zbw.eu/report/pm20_result.de.html?jsonFile=vocab/geo_by_signature.json&main_title=L%C3%A4ndersystematik)
is available online.
  },
);

# vocabulary data
my %modified;
my %geo                = get_vocab('ag');
my %subject            = get_vocab('je');
my %subheading_subject = get_subheadings( \%subject );

# last modification of any vocbulary
$modified{_last} =
  $modified{ag} ge $modified{je} ? $modified{ag} : $modified{je};

# count folders and add to %geo
my ( $geo_category_count, $total_sh_folder_count ) =
  count_folders_per_category( 'sh', \%geo );

# category overview pages
foreach my $category_type ( keys %{$definitions_ref} ) {
  my $typedef_ref = $definitions_ref->{$category_type}->{overview};
  foreach my $lang (@languages) {
    my @lines;
    my $title      = $typedef_ref->{title}{$lang};
    my $provenance = $prov{ $typedef_ref->{prov} }{name}{$lang};

    # some header information for the page
    my $backlinktitle =
      $lang eq 'en'
      ? 'Folders by Category system'
      : 'Mappen nach Systematik';
    push( @lines,
      '---',
      "title: \"$title\"",
      "etr: category_overview/$category_type",
      "modified: $modified{_last}",
      "backlink: ../about.$lang.html",
      "backlink-title: \"$backlinktitle\"",
      '---',
      '' );
    push( @lines, "## $provenance" );
    push( @lines, "# $typedef_ref->{title}{$lang}", '' );

    # read json input
    my $file =
      $klassdata_root->child( $typedef_ref->{result_file} . ".$lang.json" );
    my @categories =
      @{ decode_json( $file->slurp )->{results}->{bindings} };

    # statistics collecting and output
    my $category_count = $geo_category_count;
    push(
      @lines,
      (
        $lang eq 'en'
        ? "In total $category_count categories, $total_sh_folder_count subject folders."
        : "Insgesamt $category_count Systematikstellen, $total_sh_folder_count Sach-Mappen."
      ),
      ''
    );

    if ( defined $about_text{$lang} ) {
      push( @lines, $about_text{$lang}, '' );
    }

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
      my $id         = $1;
      my $signature  = $category->{signature}->{value};
      my $label      = $category->{countryLabel}->{value};
      my $entry_note = (
        defined $geo{$id}{geoCategoryType}
        ? "$geo{$id}{geoCategoryType} "
        : ''
        )
        . '('
        . (
        defined $geo{$id}{foldersComplete}
          and $geo{$id}{foldersComplete} eq 'Y'
        ? ( $lang eq 'en' ? 'complete, ' : 'komplett, ' )
        : ''
        )
        . $geo{$id}{shFolderCount}
        . ( $lang eq 'en' ? ' subject folders' : ' Sach-Mappen' ) . ')';

      # main entry
      my $line =
        "- [$signature $label]" . "(i/$id/about.$lang.html) $entry_note";
      push( @lines, $line );
    }

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
      my $uri = $entry->{pm20}->{value};
      my $entry_note =
          '(<a href="'
        . view_url($uri)
        . '" target="_blank">'
        . $entry->{docs}->{value}
        . ( $lang eq 'en' ? ' documents' : ' Dokumente' ) . '</a>)';
      my $line = "- [$label]($uri) $entry_note";
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

        # map optional simple jsonld fields to hash entries
        my @fields =
          qw / notation notationLong foldersComplete geoCategoryType /;
        foreach my $field (@fields) {
          $cat{$id}{$field} = $category->{$field};
        }

        # map optional language-specifc jsonld fields to hash entries
        @fields = qw / prefLabel scopeNote /;
        foreach my $field (@fields) {
          foreach my $ref ( as_array( $category->{$field} ) ) {
            $cat{$id}{$field}{ $ref->{'@language'} } = $ref->{'@value'};
          }
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
  my $backlinktitle =
    $lang eq 'en'
    ? 'Category Overview'
    : 'Systematik-Übersicht';
  push( @output,
    '---',
    "title: \"$title\"",
    "etr: category/$cat_meta{category_type}/$geo{$id}{notation}",
    "modified: $modified{_last}",
    "backlink: ../../about.$lang.html",
    "backlink-title: \"$backlinktitle\"",
    '---',
    '' );
  push( @output, "## $cat_meta{provenance}", '' );
  push( @output, "# $title", '' );

  if ( $geo{$id}{scopeNote}{$lang} ) {
    push( @output, "> Scope Note: $geo{$id}{scopeNote}{$lang}", '' );
  }

  # output statistics
  push(
    @output,
    (
      $lang eq 'en'
      ? "In total $cat_meta{folder_count_first} subject folders,"
        . " $cat_meta{document_count_first} documents"
      : "Insgesamt $cat_meta{folder_count_first} Sach-Mappen,"
        . " $cat_meta{document_count_first} Dokumente"
    ),
    (
      defined $geo{$id}{foldersComplete}
        and $geo{$id}{foldersComplete} eq 'Y'
      ? ( $lang eq 'en' ? ' - folders complete.' : ' - Mappen komplett.' )
      : (
        $lang eq 'en' ? ' - folders incomplete.' : ' - Mappen unvollständig.' )
    ),
    '',
    (
      not defined $geo{$id}{foldersComplete}
        or $geo{$id}{foldersComplete} ne 'Y'
      ? (
        $lang eq 'en'
        ? 'For material not published as folders, please check the [digitized films](/film/h1_sh) (in German).'
        : 'Nicht als Mappe aufbereitetes Material finden Sie unter [digitalisierte Filme](/film/h1_sh).'
        )
      : ''
    ),
    ''
  );
  $cat_meta_ref->{folder_count_first}   = 0;
  $cat_meta_ref->{document_count_first} = 0;

  # the actual page content
  push( @output, @{$lines_ref} );

  if ( $lang eq 'en' ) {
    push( @output,
      '',
      '_The translation of the German subject category labels is incomplete,'
        . ' therefore some labels (in italics) are given in German._' );
  }

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

sub count_folders_per_category {
  my $type    = shift or die "param missing";
  my $cat_ref = shift or die "param missing";

  my %count_data;
  my $total_folder_count;

  # subject folder data
  # read json input (all folders for all categories)
  my $file = $folderdata_root->child("subject_folders.de.json");
  my @folders =
    @{ decode_json( $file->slurp )->{results}->{bindings} };

  foreach my $folder (@folders) {
    $folder->{pm20}->{value} =~ m/(\d{6}),(\d{6})$/;
    my $id1 = $1;
    my $id2 = $2;
    $count_data{$id1}{$id2}++;
  }
  foreach my $entry ( keys %count_data ) {
    my $count = scalar( keys %{ $count_data{$entry} } );
    $cat_ref->{$entry}{"${type}FolderCount"} = $count;
    $total_folder_count += $count;
  }
  my $category_count = scalar( keys %count_data );
  return $category_count, $total_folder_count;
}

sub view_url {
  my $folder_uri = shift or die "param missing";

  # TODO use mets file from pm20 with pm20 image links
  my $viewer_stub =
    'https://dfg-viewer.de/show/?tx_dlf[id]=http://zbw.eu/beta/pm20mets';

  $folder_uri =~ m;/(pe|co|sh|wa)/(\d{6}),?(\d{6})?;;
  my $type = $1;
  my $id1  = $2;
  my $id2  = $3;

  my $view_url;
  my $num_stub1 = substr( $id1, 0, 4 );
  if ($id2) {
    my $num_stub2 = substr( $id2, 0, 4 );
    $view_url =
      "$viewer_stub/$type/${num_stub1}xx/$id1/${num_stub2}xx/$id1,$id2.xml";
  } else {
    $view_url = "$viewer_stub/$type/${num_stub1}xx/$id1.xml";
  }
  return $view_url;
}
