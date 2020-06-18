#!/bin/perl
# nbt, 22.2.2018

# Use data from PM20 image files to read and parse .txt files with document data.
# Produces docdata json file and beacon files with number of free and total
# images.

use strict;
use warnings;

use Data::Dumper;
use JSON;
use Path::Tiny;

$Data::Dumper::Sortkeys = 1;

my $imagedata_root = path('../var/imagedata');
my $docdata_root   = path('../var/docdata');
my $beacon_root    = path('../var/beacon');

my $beacon_header =
  "#FORMAT: BEACON\n#PREFIX: http://purl.org/pressemappe20/folder/\n\n";

my @collections = qw/ co pe sh wa /;

foreach my $collection (@collections) {

  print "Starting $collection\n";

  my %coll;
  $coll{cnt_doc_free} = 0;

  # read image data file
  my $img_ref =
    decode_json( $imagedata_root->child("${collection}_image.json")->slurp );

  my %docdata;
  foreach my $folder ( sort keys %{$img_ref} ) {
    my $root = path( $img_ref->{$folder}{root} );
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
      my @lines;
      my @txt_files = $doc_dir->children(qr/\.txt$/);
      if ( scalar(@txt_files) lt 1 ) {
        warn ".txt file missing in $doc_dir\n";
        $coll{cnt_doc_skipped}++;
        next;
      } elsif ( scalar(@txt_files) > 1 ) {
        warn "Multiple .txt files in $doc_dir\n";
        $coll{cnt_doc_skipped}++;
        next;
      } else {
        @lines = $txt_files[0]->lines_raw;
      }

      my %field = ();
      foreach my $line (@lines) {
        my ( $fieldname, $rest ) = split( /\t/, $line );
        if ( not $rest ) {
          warn "Empty field $fieldname for folder $folder, doc $doc\n";
          next;
        }
        $rest =~ s/\r\n//g;
        $field{$fieldname} = $rest;
      }

      # get code for hidden documents
      if ( not exists $field{HID} ) {
        warn "Missing HID for folder $folder, doc $doc: $field{HID}\n";
        $coll{cnt_doc_skipped}++;
        next;
      }
      my $code = extract_code( $field{HID} );
      if ( not $code ) {
        warn "Strange HID for folder $folder, doc $doc: $field{HID}\n";
        $coll{cnt_doc_skipped}++;
        next;
      }

      # for free documents, add extended document info
      my ( $free_status, $free_after ) = evaluate_code($code);
      if ( $free_status == 1 ) {
        $docdata{$folder}{free}{$doc} = 1;
        $coll{cnt_doc_free}++;
      } else {
        $coll{cnt_doc_hidden}++;
        if ($free_after) {
          $coll{free_after}{$free_after}++;
        }
      }
      $docdata{$folder}{info}{$doc} = \%field;
    }
  }

  # save folder data
  $docdata_root->child("${collection}_docdata.json")
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
    my $fh = $beacon_root->child("${collection}_$beacon_type.txt")->openw;
    print $fh $beacon_header;
    my %beacon = eval( '%' . "$beacon_type" );
    foreach my $fid ( sort keys %beacon ) {
      print $fh "$fid | $beacon{$fid}\n";
    }
    close($fh);
  }

  # save stats data
  $docdata_root->child("${collection}_stats.json")
    ->spew( encode_json( \%coll ) );

}

################

sub extract_code {
  my $hid_field = shift or die "param missing\n";
  my $code;
  my ( $status, $message ) = split( /::/, $hid_field );
  if ( length($status) == 3 and $status =~ m/([A-Za-z](\d\d|xx|XX))|JEU|BEC|000/ ) {
    $code = $status;
  }
  return $code;
}

sub evaluate_code {
  my $code = shift or die "param \$code missing\n";
  my ( $free_status, $free_after );

  if ( $code eq "000" ) {
    $free_status = 1;
  } elsif ( $code eq "BEC" ) {
    $free_status = 1;
  } elsif ( $code eq "JEU" ) {
    $free_status = 0;
  } elsif ( $code =~ m/.(XX|xx)/ ) {
    $free_status = 0;
  } elsif ( $code =~ m/.(\d\d)/ ) {
    my $yy = $1;

    # set proper free year for moving wall
    # (2005 was the last year from which articles were added)
    if ( $yy > 5 ) {
      $free_after = 1900 + 70 + $yy;
    } else {
      $free_after = 2000 + 70 + $yy;
    }

    # compute status from moving wall
    my $current_year = 1900 + (localtime)[5];
    if ( $current_year > $free_after ) {
      $free_status = 1;
    } else {
      $free_status = 0;
    }
  } else {
    print "Strange code $code\n";
  }
  return $free_status, $free_after;
}

