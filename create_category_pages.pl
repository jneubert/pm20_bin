#!/bin/env perl
# nbt, 15.7.2020

# create category overview pages from data/rdf/*.jsonld and
# data/klassdata/*.json

use strict;
use warnings;
use utf8;
binmode( STDOUT, ":utf8" );

use lib './lib';

use Data::Dumper;
use HTML::Template;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number reftype);
use YAML;
use ZBW::PM20x::Folder;
use ZBW::PM20x::Vocab;

my $web_root        = path('../web.public/category');
my $klassdata_root  = path('../data/klassdata');
my $folderdata_root = path('../data/folderdata');
my $template_root   = path('../etc/html_tmpl');

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

# vocabulary data
my ( $geo_ref, $geo_siglookup_ref, $geo_modified ) =
  ZBW::PM20x::Vocab::get_vocab('ag');
my ( $subject_ref, $subject_siglookup_ref, $subject_modified ) =
  ZBW::PM20x::Vocab::get_vocab('je');
my %subheading_subject = get_subheadings($subject_ref);

# last modification of any vocbulary
my $last_modified =
  $geo_modified ge $subject_modified ? $geo_modified : $subject_modified;

# count folders and add to %geo
my ( $geo_category_count, $total_sh_folder_count ) =
  count_folders_per_category( 'sh', $geo_ref );

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
    my %tmpl_var = (
      "is_$lang"     => 1,
      title          => $title,
      etr            => "category_overview/$category_type",
      modified       => $last_modified,
      backlink       => "../about.$lang.html",
      backlink_title => $backlinktitle,
      provenance     => $provenance,
      category_count => $geo_category_count,
      folder_count   => $total_sh_folder_count,
    );

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
        push( @lines, '', "### $subheading_geo{$firstletter}{$lang}", '' );
        $firstletter_old = $firstletter;
      }

      ##print Dumper $category; exit;
      $category->{country}->{value} =~ m/(\d{6})$/;
      my $id         = $1;
      my $label      = ZBW::PM20x::Vocab::get_termlabel( $lang, 'ag', $id, 1 );
      my $entry_note = (
        defined $geo_ref->{$id}{geoCategoryType}
        ? "$geo_ref->{$id}{geoCategoryType} "
        : ''
        )
        . '('
        . (
        defined $geo_ref->{$id}{foldersComplete}
          and $geo_ref->{$id}{foldersComplete} eq 'Y'
        ? ( $lang eq 'en' ? 'complete, ' : 'komplett, ' )
        : ''
        )
        . $geo_ref->{$id}{shFolderCount}
        . ( $lang eq 'en' ? ' subject folders' : ' Sach-Mappen' ) . ')';

      # main entry
      my $line = "- [$label](i/$id/about.$lang.html) $entry_note";
      push( @lines, $line );
    }

    my $tmpl = HTML::Template->new(
      filename => $template_root->child('category_overview.md.tmpl'),
      utf8     => 1
    );
    $tmpl->param( \%tmpl_var );
    ## q & d: add lines as large variable
    $tmpl->param( lines => join( "\n", @lines ), );

    my $out = $web_root->child($category_type)->child("about.$lang.md");
    $out->spew_utf8( $tmpl->output );
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

    # read subject categories
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
    my $id2_old         = '';
    my $firstletter_old = '';
    foreach my $entry (@entries) {
      ##print Dumper $entry;exit;

      # TODO improve query to get values more directly?
      $entry->{pm20}->{value} =~ m/(\d{6}),(\d{6})$/;
      my $id1   = $1;
      my $id2   = $2;
      my $label = ZBW::PM20x::Vocab::get_termlabel( $lang, 'je', $id2, 1 );
      $label = mark_unchecked_translation($label);

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
        . view_url( $lang, $uri )
        . '" target="_blank">'
        . $entry->{docs}->{value}
        . ( $lang eq 'en' ? ' documents' : ' Dokumente' ) . '</a>)';
      my $line = "- [$label]($uri) $entry_note";

      # additional indent for Sondermappen
      # (label starts with notation - has also to deal with first element,
      # e.g., n Economy)
      if ( $label =~ m/ Sm\d/ and $firstletter ne 'q' ) {
        if ( get_firstsig( $id2_old, $subject_ref ) ne
          get_firstsig( $id2, $subject_ref ) and not $label =~ m/^[a-z]0/ )
        {
          ## insert non-linked intermediate item
          my $id_broader = $subject_ref->{$id2}{broader};
          my $label      = mark_unchecked_translation(
            $subject_ref->{$id_broader}{prefLabel}{$lang} );
          push( @lines,
            "- [$subject_ref->{$id_broader}{notation} $label]{.gray}" );
        }
        $line = "  $line";
      }
      $id2_old = $id2;
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

sub output_category_page {
  my $lang         = shift or die "param missing";
  my $cat_meta_ref = shift or die "param missing";
  my $id           = shift or die "param missing";
  my $lines_ref    = shift or die "param missing";
  my %cat_meta     = %{$cat_meta_ref};

  my $title = ZBW::PM20x::Vocab::get_termlabel( $lang, 'ag', $id, 1 );
  my @output;
  my $backlinktitle =
    $lang eq 'en'
    ? 'Category Overview'
    : 'Systematik-Übersicht';
  my %tmpl_var = (
    "is_$lang" => 1,
    title      => $title,
    etr        => "category/$cat_meta{category_type}/$geo_ref->{$id}{notation}",
    modified   => $last_modified,
    backlink   => "../../about.$lang.html",
    backlink_title  => $backlinktitle,
    provenance      => $cat_meta{provenance},
    folder_count1   => $cat_meta{folder_count_first},
    document_count1 => $cat_meta{document_count_first},
    scope_note      => $geo_ref->{$id}{scopeNote}{$lang},
  );

  if ( defined $geo_ref->{$id}{foldersComplete}
    and $geo_ref->{$id}{foldersComplete} eq 'Y' )
  {
    $tmpl_var{complete} = 1;
  }
  $cat_meta_ref->{folder_count_first}   = 0;
  $cat_meta_ref->{document_count_first} = 0;

  my $tmpl = HTML::Template->new(
    filename => $template_root->child('category.md.tmpl'),
    utf8     => 1
  );
  $tmpl->param( \%tmpl_var );
  ## q & d: add lines as large variable
  $tmpl->param( lines => join( "\n", @{$lines_ref} ), );

  my $out_dir =
    $web_root->child( $cat_meta{category_type} )->child('i')->child($id);
  $out_dir->mkpath;
  my $out = $out_dir->child("about.$lang.md");
  $out->spew_utf8( $tmpl->output );
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
  my $lang       = shift or die "param missing";
  my $folder_uri = shift or die "param missing";

  my $viewer_stub =
    'https://dfg-viewer.de/show/?tx_dlf[id]=https://pm20.zbw.eu/mets/';

  $folder_uri =~ m;/(pe|co|sh|wa)/(\d{6}(,\d{6})?)$;;
  my $collection = $1;
  my $folder_id  = $2;

  my $view_url =
      $viewer_stub
    . ZBW::PM20x::Folder::get_folder_hashed_path( $collection, $folder_id )
    . "/public.mets.$lang.xml";

  return $view_url;
}

sub get_firstsig {
  my $id         = shift or die "param missing";
  my $lookup_ref = shift or die "param missing";

  my $signature = $lookup_ref->{$id}->{notation};
  my $firstsig  = ( split( / /, $signature ) )[0];

  return $firstsig;
}

sub mark_unchecked_translation {
  my $label = shift or die "param missing";

  # mark unchecked translations
  if ( substr( $label, 0, 2 ) eq '. ' ) {
    $label = substr( $label, 2 ) . '<sup>*</sup>';
  }
  return $label;
}
