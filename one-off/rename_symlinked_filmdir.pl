#!/bin/env perl
# nbt, 14.1.2023

# rename "duplicate" film dirs with symlinks for both half films

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Path::Tiny;

my $filmroot = path('/disc1/pm20/film');
my @sets     = qw/ h1 /;
my @colls    = qw/ co sh wa /;

foreach my $set ( sort @sets ) {
  foreach my $coll ( sort @colls ) {
    next unless $filmroot->child("$set/$coll")->is_dir;
    print "$set $coll\n";
    my @dirs = $filmroot->child("$set/$coll")->children;

    # walk trough all film directories

    # create lookup table
    my %dir_name;
    foreach my $dir ( sort @dirs ) {
      $dir_name{$dir} = 1;
    }

    foreach my $dir ( sort @dirs ) {
      next if not $dir->basename =~ m/^[SF]\d+[HK]$/;
      ##next if $dir =~ m/_[12]$/;
      if ( -d "${dir}_1" ) {
        if ( -d "${dir}_2" ) {
          $dir->move("${dir}.bak");
          print "  renamed $dir\n";
        } else {
          print "  ${dir}_1 exists, but ${dir}_2 is missing\n";
        }
      } elsif ( -d "${dir}_2" ) {
        print "  ${dir}_2 exists, but ${dir}_1 is missing\n";
      }
    }
  }
}
