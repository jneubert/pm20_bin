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

my $filmdata_root = path('../data/filmdata');

my %page = (
  h => {
    name      => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
    desc_tmpl =>
'des ehemaligen Hamburgischen Welt-Wirtschafts-Archivs. Themenbezogene Mappen mit Ausschnitten aus über 1500 Zeitungen und Zeitschriften des In- und Auslands (weltweit), Firmenschriften u.ä. aus der Zeit $covers$. Archiviert als digitalisierter Rollfilm, hier:',
    list => {
      'h1_sh' => {
        title  => 'Länder-Sacharchiv',
        covers => 'von 1908 (z.T. früher) bis ca. 1949',
      },
      'h2_sh' => {
        title  => 'Länder-Sacharchiv',
        covers => 'von ca. 1949 bis ca. 1960',
      },
      'h1_co' => {
        title  => 'Firmen- und Institutionenarchiv',
        covers => 'von 1908 (z.T. früher) bis ca. 1949',
      },
      'h2_co' => {
        title  => 'Firmen- und Institutionenarchiv',
        covers => 'von ca. 1949 bis ca. 1960',
      },
      'h1_wa' => {
        title  => 'Warenarchiv',
        covers => 'von 1908 (z.T. früher) bis ca. 1946',
      },
      'h2_wa' => {
        title  => 'Warenarchiv',
        covers => 'von ca. 1947 bis ca. 1960',
      },
    },
  },
  k => {
    name       => 'Wirtschaftsarchiv des Instituts für Weltwirtschaft (WiA)',
    list  => {
      k1_sh => {
        title => 'Sacharchiv',
      },
      k2_sh => {
        title => 'Sacharchiv',
      },
    },
  },
);

foreach my $prov (qw/ h /) {
  foreach my $page_name ( sort keys %{ $page{$prov}{list} } ) {

    my $title = $page{$prov}{list}{$page_name}{title};
    my $coll  = substr( $page_name, 3, 2 );
    my $set   = substr( $page_name, 0, 2 );
    my $desc_stub =
      "$page{$prov}{list}{$page_name}{title} $page{$prov}{desc_tmpl}";
    $desc_stub =~ s/\$covers\$/$page{$prov}{list}{$page_name}{covers}/;
    my @lines;

    # read json input
    my @film_sections =
      @{ decode_json( $filmdata_root->child( $page_name . '.json' )->slurp ) };

    # iterate through the list of film sections (from the excel file)
    my $i = 0;
    foreach my $film_section (@film_sections) {
      $i++;

      my $film = "$set/$coll/$film_section->{film_id}";
      my $from = "$film_section->{start_sig} ($film_section->{start_date})";
      my $to   = "$film_section->{end_sig} ($film_section->{end_date})";

      my $description = "$desc_stub $film, enthaltend: $from bis $to";

      push( @lines, "$film\t$description" );
    }

    # write output to public
    my $out = $filmdata_root->child( 'euipo.' . $page_name . '.txt' );
    $out->spew_utf8( join( "\n", @lines ) );

    print "$page_name: $i films written\n";
  }
}

