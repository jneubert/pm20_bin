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

my $web_root = path('../web.public/category');
my $klassdata_root    = path('../data/klassdata');

my %prov = (
  hwwa => {
    name => {
      en => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
      de => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
    }
  },
);

my %page = (
  h => {
    name       => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
    column_ids => [
      qw/ film_id start_sig start_date end_sig end_date img_count online comment /
    ],
    info =>
'Das Material der Filme mit den [hellgrün unterlegten Links]{.is-online} ist in der [Pressemappe 20. Jahrhundert](http://webopac.hwwa.de/pressemappe20) erschlossen und online auf Mappen- und Dokumentebene zugreifbar, soweit rechtlich möglich auch im Web.',
    head =>
'Filmnummer|Signatur des jeweils ersten Bildes|Datum des jeweils ersten Bilder|Signatur des jeweils letzten Bildes|Datum des jeweils letzten Bildes|Anzahl Doppelseiten|Online gestellt|Bemerkungen',
    delim => '-|---|-|---|-|-|-|-',
    list  => {
      'h1_sh' => {
        title => 'Länder-Sacharchiv 1. Verfilmung',
      },
      'h2_sh' => {
        title => 'Länder-Sacharchiv 2. Verfilmung',
      },
      'h1_co' => {
        title => 'Firmen- und Institutionenarchiv 1. Verfilmung',
      },
      'h2_co' => {
        title => 'Firmen- und Institutionenarchiv 2. Verfilmung',
      },
      'h1_wa' => {
        title => 'Warenarchiv 1. Verfilmung',
      },
      'h2_wa' => {
        title => 'Warenarchiv 2. Verfilmung',
      },
    },
  },
);


my @languages = qw/ de en /;

my $definitions_ref = YAML::Load(<<'EOF');
geo:
  title:
    en: Country Category System
    de: Ländersystematik
  result_file: data/klassdata/geo_by_signature.json
  output_dir: ../category/geo
  prov: hwwa
EOF

foreach my $lang (@languages) {
  foreach my $category_type (keys %{$definitions_ref}) {
    my @lines;
    my $typedef_ref = $definitions_ref->{$category_type};
    my $title = $typedef_ref->{title}{$lang};

    # some header information for the page
    push( @lines,
      '---',
      "title: \"$title\"",
      "etr: category_overview/$category_type",
      '---', '' );
    my $provenance = $prov{$typedef_ref->{prov}}{name}{$lang};
    push(@lines, "## $provenance");
    push(@lines, "# $typedef_ref->{title}{$lang}",'');
    my $backlinktitle = $lang eq 'en' ? 'Back to Category systems' : 'Zurück zu Systematiken';
    push(@lines, "[$backlinktitle](..)", '');
  
    my $out = $web_root->child($category_type)->child( "about.$lang.md" );
    $out->spew_utf8( join( "\n", @lines ) );
  }

}

__DATA__
    # read json input
    my @film_sections =
      @{ decode_json( $klassdata_root->child( $page_name . '.json' )->slurp ) };

    # iterate through the list of film sections (from the excel file)
    foreach my $film_section (@film_sections) {
      my @columns;

      # add count via lookup
      my $film = "$set/$coll/$film_section->{film_id}";
      $film_section->{img_count} = $img_cnt{$film};

      foreach my $column_id ( @{ $page{$prov}->{column_ids} } ) {
        my $cell = $film_section->{$column_id} || '';

        # add film id anchor
        # (don't use film_id column, otherwise linking fails)
        if ( $column_id eq 'start_sig' ) {
          $cell = "<a name='". $film_section->{film_id} . "'></a>$cell";
        }

        # add class and link to "online" cell
        if ( $column_id eq 'online' ) {
          $cell = "[[$cell]{.is-online}](https://pm20.zbw.eu/folder/$coll)";
        }
        push( @columns, $cell );
      }
      push( @lines, join( '|', @columns ) );

      if ( $#columns ne $#{ $page{$prov}->{column_ids} } ) {
        warn "Number of columns: $#columns\n$columns[$#columns]\n";
      }
    }

    # close table div
    push( @lines, '', ':::', '' );
    push( @lines, "[zurück zum Film-Überblick](.)", '', $ip_hints );

    # write output to public
    my $out = $web_root->child( $page_name . '.de.md' );
    $out->spew_utf8( join( "\n", @lines ) );

  }
}

#######################

