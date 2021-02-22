#!/bin/env perl
# nbt, 2021-02-22

# create markdown tables (for conversion to static html) from sparql results in
# json

use strict;
use warnings;
use utf8;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number);

binmode( STDOUT, ":utf8" );

my $input_file = path('/tmp/persons_with_metadata.de.json');

my $input = decode_json( $input_file->slurp );

# collect output lines, starting with page head
my @lines;
push( @lines,
  '---', "title: \"x | ZBW Pressearchive\"",
  "etr: report",
  "backlink: ./about.de.html",
  "backlink-title: Auswertungen",
  '---', '' );
push( @lines, "# titel", '' );

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
print join( "\n", @lines );

