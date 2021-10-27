#!/bin/env perl
# nbt, 2021-10-26

# Create the folder tree for the web directory, and
# create symlinks for actual document directories

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;

Readonly my $FOLDER_DOCROOT => path('/pm20/document');
Readonly my $FOLDER_WEBROOT => path('/pm20/web/folder.new');
Readonly my $IMAGEDATA_ROOT => path('/pm20/data/imagedata');

# get start dir for collection
# TODO extend to folder_no
my ( $collection, $start_dir );
if ( scalar(@ARGV) == 1 ) {
  $collection = $ARGV[0];
  $start_dir  = $FOLDER_DOCROOT->child($collection);
} else {
  die "usage: $0 {collection}\n";
}

# check for existence
if ( not $start_dir->is_dir ) {
  die "start dir $start_dir does not exist\n";
}

# read imagedata (= evaluated file system)
my $imagedata_ref =
  decode_json( $IMAGEDATA_ROOT->child("${collection}_image.json")->slurp );

# for all folders
foreach my $folder_no ( sort keys %{$imagedata_ref} ) {

  # create folder dir (including hashed level)
  my $folder_dir;
  if ( $collection eq 'pe' or $collection eq 'co' ) {
    my $hash_dir = substr( $folder_no, 0, 4 ) . 'xx';
    $folder_dir =
      $FOLDER_WEBROOT->child($collection)->child($hash_dir)->child($folder_no);
  } else {

    # TODO for wa and sh
  }
  $folder_dir->mkpath;
  $folder_dir->child('doc')->mkpath;

  # for all documents
  my $doc_ref = $imagedata_ref->{$folder_no}{docs};
  foreach my $doc_id ( sort keys %{$doc_ref} ) {
    my $rel_path = $doc_ref->{$doc_id}{rp};
    my $phys_path =
      $FOLDER_DOCROOT->child($collection)->child($rel_path)->realpath;

    # simplify/change structure of new path
    # - drop hash level for documents
    # - drop PIC level
    # - add doc level
    my $new_path = $FOLDER_WEBROOT->child($collection)->child($rel_path)
      ->parent->parent->parent->child('doc')->child($doc_id);

    # remove exsting symlink
    if ( $new_path->exists ) {
      unlink $new_path or die "Cannot delete existing symlink $new_path: $!\n";
    }
    symlink( $phys_path, $new_path )
      or die "Cannot create $new_path (from $phys_path): $!\n";
  }
  exit;
}

