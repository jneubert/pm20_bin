#!/bin/env perl
# nbt, 27.8.2019

# evaluate the access status of a pm20 document and create or rewrite an
# .htaccess file, when access is to be denied, otherwise remove any existing
# .htaccess file

use strict;
use warnings;

use Path::Tiny;
use Readonly;

Readonly my $htaccess_content => 'Require env PM20_INTERNAL';

# root directory for documents is required
if ( not @ARGV ) {
  die "Usage: $0 {root}\n";
}
my $docroot = path( $ARGV[0] );
if ( !$docroot->is_dir ) {
  die "docroot '$docroot' is not a directory\n";
}

# recursivly visit all subdirectories
$docroot->visit(
  sub {
    my ( $path, $state ) = @_;
    return if !$path->is_dir;
    return if !$path->child('PIC')->is_dir;
    my $free_status = evalute_doc_path($path);

    # remove existing .htaccess file
    my $htaccess = $path->child('.htaccess');
    my $pre_existing_htaccess = 0;
    if ($htaccess->is_file) {
      $pre_existing_htaccess = 1;
      $htaccess->remove;
    }
    if ($free_status eq 0) {
      $htaccess->spew($htaccess_content);
    }
    
    # logging
    if ($free_status and $pre_existing_htaccess) {
      print "unblocked $path\n";
    }
    if (!$free_status and !$pre_existing_htaccess) {
      print "blocked $path\n";
    }
  },
  { recurse => 1, follow_symlinks => 1 }
);

#########################

sub evalute_doc_path {
  my $path        = shift;
  my $free_status = 0;

  # text files can be used to override permissions
  # and should contain the reason for blocking or unblocking a document,
  # user (abbrev) and date
  # - access_locked.txt overrides all
  # - access_free.txt overrides restricions in file name

  if ( $path->child('access_locked.txt')->is_file ) {
    $free_status = 0;
  } elsif ( $path->child('access_free.txt')->is_file ) {
    $free_status = 1;
  } else {
    ## use the first page of the document, hi res version
    my @files = sort $path->child('PIC')->children(qr/_A.JPG/);
    $files[0]->basename =~ m/.{39}(.{3})/;
    my $code = $1;
    ($free_status) = evaluate_code($code);
    ##print "$code => $free_status\n";
  }
  return $free_status;
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

