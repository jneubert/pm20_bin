#!/bin/env perl
# nbt, 8.11.2019

# create lists of films from filmdata/*.json

use strict;
use warnings;
use utf8;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number);

# filmdata publicly available now
my $film_intern_root = path('../web.intern/film');
my $film_public_root = path('../web.public/film');
my $filmdata_root    = path('../data/filmdata');
##my $filmdata_root    = $film_public_root;
my $img_file         = $filmdata_root->child('img_count.json');
my $ip_hints         = path('../web.public/templates/fragments/ip_hints.de.md.frag')->slurp_utf8;

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
  k => {
    name       => 'Wirtschaftsarchiv des Instituts für Weltwirtschaft (WiA)',
    column_ids => [
      qw/ film_id img_id country geo_sig topic_sig from to no_material comment /
    ],
    info => 'Vorläufige Übersicht',
    head =>
'Film|Aufnahme|Land|Ländersign.|Sachsignatur|Von|Bis|Kein Material|Bemerkungen',
    delim => '--|--|---|--|--|-|-|-|---',
    list  => {
      k1_sh => {
        title => 'Sacharchiv 1. Verfilmung',
      },
      k2_sh => {
        title => 'Sacharchiv 2. Verfilmung',
      },
    },
  },
);


# TEMPORARY: remove path
my $img_count = decode_json( $img_file->slurp );
my %img_cnt;
foreach my $key ( keys %{$img_count} ) {
  my $shortkey = substr( $key, 18 );
  $img_cnt{$shortkey} = $img_count->{$key};
}

foreach my $prov ( keys %page ) {
  foreach my $page_name ( sort keys %{ $page{$prov}{list} } ) {
    print "$page_name\n";

    my $title = $page{$prov}{list}{$page_name}{title};
    my $coll  = substr( $page_name, 3, 2 );
    my $set   = substr( $page_name, 0, 2 );

    # some header information for the page
    my @lines;
    push( @lines,
      '---',
      "title: \"$page_name: $title | ZBW Pressearchive\"",
      "etr: filmlist/$coll",
      '---', '' );
    push( @lines, "## $page{$prov}{name}",                   '' );
    push( @lines, "# $page{$prov}{list}{$page_name}{title}", '' );
    push( @lines, "[zurück zum Film-Überblick](.)",        '' );
    push( @lines,
'Aus urheberrechtlichen Gründen sind die digitalisierten Filme nur im ZBW-Lesesaal zugänglich. *Bitte überprüfen Sie eigenverantwortlich vor einer Vervielfältigung oder Veröffentlichung einzelner Artikel deren urheberrechtlichen Status* ([Hinweise](#urheberrechte)) und holen Sie ggf. die Rechte bei den Rechteinhabern ein.',
      '' );
    if ( $page{$prov}{info} ) {
      push( @lines, $page{$prov}{info}, '' );
    }
    push( @lines, '::: {.wikitable}', '' );
    push( @lines, $page{$prov}{head}, $page{$prov}{delim} );

    # read json input
    my @film_sections =
      @{ decode_json( $filmdata_root->child( $page_name . '.json' )->slurp ) };

    # iterate through the list of film sections (from the excel file)
    foreach my $film_section (@film_sections) {
      my @columns;

      # add count via lookup
      my $film = "$set/$coll/$film_section->{film_id}";
      $film_section->{img_count} = $img_cnt{$film};

      foreach my $column_id ( @{ $page{$prov}->{column_ids} } ) {
        my $cell = $film_section->{$column_id} || '';

        # add class and link to "online" cell
        if ( $column_id eq 'online' ) {
          $cell = "[[$cell]{.is-online}](https://pm20.zbw.eu/folder/$coll)";
        }
        push( @columns, $cell );
      }
      push( @lines, join( '|', @columns ) );

      if ($#columns ne $#{ $page{$prov}->{column_ids} }) {
        warn "Number of columns: $#columns\n$columns[$#columns]\n";
      }
    }

    # close table div
    push( @lines, '', ':::', '' );
    push( @lines, "[zurück zum Film-Überblick](.)", '', $ip_hints );

    # write output to public
    my $out = $film_public_root->child( $page_name . '.de.md' );
    $out->spew_utf8( join( "\n", @lines ) );

    # insert links into @lines
    my $lines_intern_ref = insert_links( $page_name, \@lines );

    # write output to intern
    $out = $film_intern_root->child( $page_name . '.de.md' );
    $out->spew_utf8( join( "\n", @{$lines_intern_ref} ) );
  }
}

#######################

sub insert_links {
  my $page_name = shift or die "param missing";
  my $lines_ref = shift or die "param missing";

  my $prov = substr( $page_name, 0, 1 );
  my @lines_intern;
  my $prev_film_id = '';
  foreach my $line ( @{$lines_ref} ) {

    # only for table lines which include some number(s)
    # (skip head and delim)
    if ( $line =~ m/\d\d/ and $line =~ m/^(.+?)\|(.*?)\|(.*)$/ ) {
      my $film_id      = $1;
      my $second_match = $2;
      my $rest         = $3;

      # for film ids from Kiel
      if ( $film_id =~ m/^[0-9]+$/ ) {
        $film_id = sprintf( "%04d", $film_id );
      }

      my $dir = join( '/', split( /_/, $page_name ) );

      # link only if there's content for the cell with the first image
      my $film_link;
      if ( $second_match ne '' ) {
        $film_link = "[$film_id]($dir/$film_id)";
      } else {
        $film_link = $film_id;
      }

      # Kiel entries have an image link, Hamburg entries don't
      if ( $prov eq 'k' ) {
        my $img_id = $second_match;
        my $img_link;
        if ( looks_like_number($img_id) ) {
          $img_id = sprintf( "%04d", $img_id );
          $img_link = "[$img_id]($dir/$film_id/$img_id)";
        } else {
          warn "    No img number: $film_id $img_id\n";
          $img_link = $img_id;
        }

        # for every new film, create a link to the first image
        if ( $film_id ne $prev_film_id ) {
          push( @lines_intern, "$film_link|$img_link|$rest" );
        } else {
          push( @lines_intern, "$film_id|$img_link|$rest" );
        }
      } else {
        push( @lines_intern, "$film_link|$second_match|$rest" );
      }
      $prev_film_id = $film_id;
    } else {
      push( @lines_intern, $line );
    }
  }
  return \@lines_intern;
}
