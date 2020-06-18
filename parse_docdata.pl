#!/bin/perl
# nbt, 22.2.2018

# Use data from PM20 image files to check .htaccess and parse file names.
# (.txt files are ignored) Produces docdata json file and beacon files with
# number of free and total images.

# Run after recreate_document_locks.pl!

# TODO
# - extended filename parsing
# - use doc_attribute files

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;

$Data::Dumper::Sortkeys = 1;

Readonly my $FOLDER_ROOT    => path('../folder');
Readonly my $IMAGEDATA_ROOT => path('../data/imagedata');
Readonly my $DOCDATA_ROOT   => path('../data/docdata');
Readonly my $BEACON_ROOT    => path('../data/beacon');

Readonly my $BEACON_HEADER =>
  "#FORMAT: BEACON\n#PREFIX: http://purl.org/pressemappe20/folder/\n\n";

##Readonly my @COLLECTIONS => qw/ co pe sh wa /;
Readonly my @COLLECTIONS => qw/ pe /;

foreach my $collection (@COLLECTIONS) {

  print "Starting $collection\n";

  my %coll;
  $coll{cnt_doc_free} = 0;

  # read image data file
  my $img_ref =
    decode_json( $IMAGEDATA_ROOT->child("${collection}_image.json")->slurp );

  my %docdata;
  foreach my $folder ( sort keys %{$img_ref} ) {
    my $root = $FOLDER_ROOT->child($collection);
    $coll{cnt_folder}++;

    my %docs = %{ $img_ref->{$folder}{docs} };
    foreach my $doc ( sort keys %docs ) {

      $coll{cnt_doc_total}++;

      # check for and read description file
      my $doc_dir = path( $root . '/' . $docs{$doc}{rp} )->parent;
      if ( not -d $doc_dir ) {
        warn "Directory $doc_dir is missing\n";
        $coll{cnt_doc_skipped}++;
        next;
      }

      if ( is_free($doc_dir) ) {
        $docdata{$folder}{free}{$doc} = 1;
        $coll{cnt_doc_free}++;
      } else {
        $coll{cnt_doc_hidden}++;
      }
    }
  }

  # save folder data
  $DOCDATA_ROOT->child("${collection}_docdata.json")
    ->spew( encode_json( \%docdata ) );

  my ( %beacon_total, %beacon_free );
  foreach my $folder ( keys %docdata ) {
    $beacon_free{"$collection/$folder"} =
      scalar( keys %{ $docdata{$folder}{free} } );
    $beacon_total{"$collection/$folder"} =
      scalar( keys %{ $docdata{$folder}{info} } );
  }

  # write beacon files
  foreach my $beacon_type (qw/ beacon_free beacon_total/) {
    my $fh = $BEACON_ROOT->child("${collection}_$beacon_type.txt")->openw;
    print $fh $BEACON_HEADER;
    my %beacon = eval( '%' . "$beacon_type" );
    foreach my $fid ( sort keys %beacon ) {
      print $fh "$fid | $beacon{$fid}\n";
    }
    close($fh);
  }

  # save stats data
  $DOCDATA_ROOT->child("${collection}_stats.json")
    ->spew( encode_json( \%coll ) );
}

################

sub is_free {
  my $doc_dir = shift or die "param missing";

  my $free_status = path("$doc_dir/.htaccess")->is_file ? 0 : 1;

  return $free_status;
}
