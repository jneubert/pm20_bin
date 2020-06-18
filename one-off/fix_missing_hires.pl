#!/bin/env perl
# nbt, 2020-06-18

# in the folder for Adolf Hitler, some hires images are missing, but mediumres
# images are present. Therefore, create a symlink for the hires to the
# mediumres file

use strict;
use warnings;

use Path::Tiny;

my $root = path('/disc1/pm20/folder/pe/0079xx/007921');

foreach my $hashed ( '011xx', '012xx' ) {
  foreach my $path ( $root->child($hashed)->children() ) {
    foreach my $file ( $path->child('PIC')->children() ) {
      next unless $file =~ m/_B\.JPG$/;
      ( my $hires_name = $file ) =~ s/_B\.JPG$/_A.JPG/;
      next if -e $hires_name;
      symlink($file, $hires_name) or die "Could not create $hires_name: $!\n";
      print "$hires_name\n";
    }
  }
}
