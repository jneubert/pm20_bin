#!/bin/env perl
# nbt, 2020-06-12

# Parse DocAttribute files from pm-opac sources, and save as a json
# datatructure

use strict;
use warnings;
use utf8;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use YAML::Tiny;

binmode( STDIN,  ":encoding(iso-8859-1)" );
binmode( STDOUT, ":utf8" );
$Data::Dumper::Sortkeys = 1;

Readonly my $DOCATTRIB_ROOT => path('/disc1/pm20/data/DocAttribute/');
Readonly my $DOCDATA_ROOT   => path('/disc1/pm20/data/docdata/');

my %input = (
  pe => [qw/ DocAttribute_P.txt /],
  co => [qw/ DocAttribute_FI.txt DocAttribute_A.txt /],
  sh => [qw/ DocAttribute_S.txt /],
  wa => [qw/ DocAttribute_W.txt /],
);

foreach my $collection ( keys %input ) {

  my %data;

  foreach my $fn ( @{ $input{$collection} } ) {

    print "$fn\n";
    my @lines = split( /\r\n/, $DOCATTRIB_ROOT->child($fn)->slurp );

    foreach my $line (@lines) {
      next if $line eq '';
      my %entry;

      # cleanup messy lines
      $line = fix_line($line);

      my @parts = split( / \[\] */, $line );
      warn "Wrong format1: $line\n" if scalar(@parts) eq 0;

      # check first part
      my ( $folder_id, $doc_id, $date ) = split( / +/, $parts[0] );
      if ( not $doc_id or $doc_id eq '' ) {
        warn "Wrong format2: $line\n";
        next;
      }
      if ( $date and $date ne '' ) {
        $entry{d} = $date;
      } else {
        next if not( $parts[1] );
      }

      # check second (optional) part
      if ( $parts[1] ) {
        my @fields = split( /\|/, $parts[1] );
        warn "Wrong format3: $line\n" if scalar(@fields) eq 0;

        foreach my $field (@fields) {
          my ( $code, $content );
          if ( $field =~ m/([a-z])=(.+)/ ) {
            $code         = $1;
            $content      = $2;
            $entry{$code} = $content;
          } else {
            warn "Wrong format4: '$line'\n";
          }
        }
      }

      # add entry for the document
      $data{$folder_id}{$doc_id} = \%entry;

    }
  }

  #print Dumper \%data;

  my %code_stat;
  foreach my $fid ( keys %data ) {
    foreach my $did ( keys %{ $data{$fid} } ) {
      foreach my $code ( keys %{ $data{$fid}{$did} } ) {
        $code_stat{$code}++;
      }
    }
  }
  print Dumper \%code_stat;
}

##################

sub fix_line {
  my $line = shift or die "param missing";

  # missing first field code - assume t=
  $line =~ s/(.+) \[\] (.[^=].+)/$1 \[\] t=$2/;

  # missing last field code with "Tabelle"
  $line =~ s/(.+ \[\] .+;) (Tabelle)$/$1 i=$2/;
  $line =~ s/(.+ \[\] .+;) i(Tabelle)$/$1 i=$2/;

  # replace field delimiter '; ' with '|', because semicolon occurs in texts
  # (repeat for multiple occurances)
  $line =~ s/(.+ \[\] .+?); ([a-z]=.+)/$1|$2/;
  $line =~ s/(.+ \[\] .+?); ([a-z]=.+)/$1|$2/;
  $line =~ s/(.+ \[\] .+?); ([a-z]=.+)/$1|$2/;
  $line =~ s/(.+ \[\] .+?); ([a-z]=.+)/$1|$2/;

  # individual errors
  # uppercase code
  $line =~ s/(.+ \[\] )T=(.+)/$1t=$2/;

  # missing code
  $line =~ s/(.+ \[\])=(.+)/$1 t=$2/;

  return $line;
}
