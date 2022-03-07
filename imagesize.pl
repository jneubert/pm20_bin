#!/usr/bin/perl
# nbt, 10.5.2019

# Get sizes lists of PM20 image files

use strict;
use warnings;

use Data::Dumper;
use Image::Size;
use JSON;
use Path::Tiny;

$Data::Dumper::Sortkeys = 1;

my $imagedata_root = path('../var/imagedata');

# iterate through all collections
#foreach my $collection (qw/ co pe sh wa /) {
foreach my $collection (qw/ pe sh /) {

  my $lst   = $imagedata_root->child("${collection}_image.lst");
  my $files = $lst->slurp;

  my %img;
  foreach my $path ( sort split( /\n/, $files ) ) {

    print "$path\n";

    # iterate over all resolutions
    foreach my $res (qw/ A B C /) {
      ( my $file = $path ) =~ s/_A\.JPG/_$res\.JPG/;
      my ( $w, $h ) = imgsize($file);
      $img{$path}{$res}{w} = $w;
      $img{$path}{$res}{h} = $h;
    }
  }

  # save as json
  my $out_fn = $collection . '_size.json';
  $imagedata_root->child($out_fn)->spew( encode_json( \%img ) );
  print "$out_fn saved\n";
}
