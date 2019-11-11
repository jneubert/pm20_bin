#!/bin/env perl
# nbt, 8.11.2019

# copy .jpx "delimiter files" to .jpg

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Path::Tiny;

my $filmroot = path('/disc1/pm20/film');
my @sets     = qw/ h1 h2 k1 k2 /;
my @colls    = qw/ co sh wa /;

foreach my $set ( sort @sets ) {
  foreach my $coll ( sort @colls ) {
    next unless $filmroot->child("$set/$coll")->is_dir;
    my @dirs = $filmroot->child("$set/$coll")->children;

    # walk trough all film directories
    foreach my $dir ( sort @dirs ) {
      next unless $dir->is_dir;
      my @jpxs = $dir->children(qr/\.jpx$/);

      # copy every .jpx file to .jpg
      foreach my $jpx ( sort @jpxs ) {
        ( my $jpg = $jpx ) =~ s/\.jpx$/\.jpg/;
        next if ( -f $jpg );
        print "$jpx -> $jpg\n";
        $jpx->copy($jpg);
      }
    }
  }
}
