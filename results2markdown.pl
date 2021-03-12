#!/bin/env perl
# nbt, 2021-02-22

# create markdown tables (for conversion to static html) from sparql results in
# transmitted as json files
# plus:
# - recreate report directory symlink structure
# - recreate about page

use strict;
use warnings;
use utf8;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use YAML;

binmode( STDOUT, ":utf8" );

Readonly my $DEFINITIONS_FILE   => 'sparql_results.yaml';
Readonly my $CONFIGURATION_FILE => 'reports.yaml';
Readonly my $REPORT_ROOT        => path('/pm20/web/report');

# read report definitions
my %definition = %{ YAML::LoadFile($DEFINITIONS_FILE) };
my %conf       = %{ YAML::LoadFile($CONFIGURATION_FILE) };

# iterate over reports
foreach my $report ( keys %definition ) {

  # iterate over languages
  foreach my $lang ( keys %{ $definition{$report}{title} } ) {

    # read input
    ( my $input_dir = $definition{$report}{output_dir} ) =~ s|/var/|/data/|;
    my $input_file = path("$input_dir/$report.$lang.json");
    my $input      = decode_json( $input_file->slurp );

    # collect output lines, starting with page head
    my @lines;
    my $title = $definition{$report}{title}{$lang};

    push( @lines,
      '---',
      "title: \"$conf{rep}{$lang}: $title | $conf{archive}{$lang}\"",
      "etr: report",
      "backlink: ../about.$lang.html",
      "backlink-title: $conf{backlink_title}{$lang}",
      '---',
      '' );
    push( @lines, "## $conf{subtitle}{$lang}", '' );
    push( @lines, "# $title", '' );

    # read table head with field names
    my @fields;
    foreach my $field ( @{ $input->{head}{vars} } ) {

      # skip Labels for URI fields
      next if $field =~ m/Label$/;

      push( @fields, $field );
    }

    # print table head
    push( @lines, '::: {.wikitable}', '' );
    push( @lines, join( '|', @fields ) );
    my @delims = map( '-', @fields );
    push( @lines, join( '|', @delims ) );

    # iteratre over data entries
    my $data_ref = $input->{results}{bindings};
    foreach my $entry ( @{$data_ref} ) {

      # iterate over fields
      my @row;
      foreach my $field (@fields) {

        # handle empty fields
        if ( not $entry->{$field} or $entry->{$field}{value} eq '' ) {
          push( @row, ' ' );
          next;
        }

        if ( $entry->{$field}{type} eq 'uri' ) {

          # handle URI fields
          if ( my $text = $entry->{"${field}Label"}{value} ) {
            push( @row, '[' . $text . '](' . $entry->{$field}{value} . ')' );
          } else {
            push( @row,
                  '['
                . $entry->{$field}{value} . ']('
                . $entry->{$field}{value}
                . ')' );
          }
        } else {

          # handle other (literal) fields
          push( @row, $entry->{$field}{value} );
        }
      }
      push( @lines, join( '|', @row ) );
    }

    push( @lines, '', ':::', '' );

    # output report in markdown
    my $report_dir = $REPORT_ROOT->child( $definition{$report}{report_dir} );
    my $md_file    = $report_dir->child("$report.$lang.md");
    $md_file->spew_utf8( join( "\n", @lines ) );

    # symlink json file from report dir (compute relative path)
    my $json_file = $report_dir->child("$report.$lang.json");
    $json_file->remove;
    my $relpath = $input_file->realpath->relative($report_dir);
    symlink( $relpath, $json_file );
  }
}

# recreate about page

# iterate over languages
foreach my $lang (qw/de en/) {

  my @lines;
  my $title = $conf{backlink_title}{$lang};
  push( @lines,
    '---',
    "title: \"$title | $conf{archive}{$lang}\"",
    "etr: report",
    "backlink: ../about.$lang.html",
    "backlink-title: Home",
    'fn-stub: about',
    '---',
    '',
    "# $title",
    '' );
  push( @lines,
    $lang eq 'de'
    ? 'Ergebnisse von Abfragen der Pressearchiv-Datenbank (Metadaten über das ehemalige HWWA-Archiv).'
    : 'Query results from the press archives database (metadata about the former HWWW archives).',
    '' );

  # iterate over page sections
  foreach my $section ( @{ $conf{sections} } ) {

    push( @lines, "## $conf{section}{$section}{$lang}", '' );

    # iterate over reports
    for my $report ( keys %definition ) {

      next unless $definition{$report}{report_dir} eq $section;

      if ( $definition{$report}{title}{$lang} ) {
        my $title = $definition{$report}{title}{$lang};
        ( my $main_title = $title ) =~ s/ /+/g;
        my $json_file = "$section/$report.$lang.json";
        my $report_link =
            "https://pm20.zbw.eu/report/pm20_result.$lang.html?"
          . "jsonFile=$json_file&main_title=$main_title";
        my $html_file = "$section/$report.$lang.html";
        push( @lines,
          "* [$title]($report_link) "
            . "<small>([html]($html_file), [json]($json_file))</small>",
          '' );
      }
    }
  }
  my $note = $lang eq 'de'
  ? 'Diese Daten sind auch über einen [SPARQL-Endpoint](http://zbw.eu/beta/sparql-lab/about#pm20) abfragbar. ' 
  . 'Die Quelltexte der Abfragen sind über [Github](https://github.com/zbw/sparql-queries/tree/master/pm20) zugänglich.'
  : 'This data is also queryable via a [SPARQL endpoint](http://zbw.eu/beta/sparql-lab/about#pm20).. ' 
  . 'The source code of the queries is accessible on [Github](https://github.com/zbw/sparql-queries/tree/master/pm20).';
  push(@lines, "<small>$note</small>");

  # write output
  $REPORT_ROOT->child("about.$lang.md")->spew_utf8( join( "\n", @lines ) );
}

