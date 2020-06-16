#!/bin/env perl
# nbt, 27.8.2019

# evaluate the access status of a pm20 document and create or rewrite an
# .htaccess file, when access is to be denied, otherwise remove any existing
# .htaccess file

# TODO
# - generate meta.yaml from document data (once)
# - create sub evaluate_meta
# - create sub for checking moving wall (factor out from evaluate_code)

use strict;
use warnings;

use Data::Dumper;
use Log::Log4perl;
use Log::Log4perl::Level;
use Path::Iterator::Rule;
use Path::Tiny;
use Readonly;
##use ZBW::Logutil;

use lib '../lib';

# logging
#my $log = ZBW::Logutil->get_logger('parse_filenames.log.conf');
Log::Log4perl::init("/disc1/pm20/etc/document_locks.logconf");
my $log = Log::Log4perl->get_logger("root");
$log->level($INFO);

Readonly my $HTACCESS_CONTENT => 'Require env PM20_INTERNAL';

# these flags overide everything else!
Readonly my $ACCESS_LOCKED_FN => 'access_locked.txt';
Readonly my $ACCESS_FREE_FN   => 'access_free.txt';

# document-specific metadata, especially authors death_year and publication_date
# (overide codes from file name)
Readonly my $META_FN => 'meta.yaml';

# root directory for documents is required
if ( not @ARGV ) {
  die "Usage: $0 {root}\n";
}
my $docroot = path( $ARGV[0] );
if ( !$docroot->is_dir ) {
  die "docroot '$docroot' is not a directory\n";
}

$log->info("Start run $docroot");

# recursivly visit all subdirectories, which include a PIC subdirectory
my $rule = Path::Iterator::Rule->new;
$rule->and( sub { -d "$_/PIC" } );
my %options = ();
my $next    = $rule->iter( ($docroot), \%options );
while ( defined( my $file = $next->() ) ) {
  my $path        = path($file);
  my $free_status = is_free($path);
  $log->debug("free_status $free_status $path");

  # remove existing .htaccess file
  my $htaccess              = $path->child('.htaccess');
  my $pre_existing_htaccess = 0;
  if ( $htaccess->is_file ) {
    $pre_existing_htaccess = 1;
    $htaccess->remove;
  }
  if ( $free_status eq 0 ) {
    $htaccess->spew($HTACCESS_CONTENT);
  }

  # logging
  if ( $free_status and $pre_existing_htaccess ) {
    $log->info("unblocked $path");
  }
  if ( !$free_status and !$pre_existing_htaccess ) {
    $log->info("blocked $path");
  }
}

$log->info("End run $docroot");

#########################

sub is_free {
  my $path        = shift;
  my $free_status = 0;

  # text files can be used to override permissions
  # and should contain the reason for blocking or unblocking a document,
  # user (abbrev) and date
  # - access_locked.txt overrides all
  # - access_free.txt overrides restricions in file name

  if ( $path->child($ACCESS_LOCKED_FN)->is_file ) {
    $free_status = 0;
  } elsif ( $path->child($ACCESS_FREE_FN)->is_file ) {
    $free_status = 1;
  } elsif ( $path->child($META_FN)->is_file ) {
    ## TODO evaluate_meta
  } else {
    ## extract code from the first page of the document, hi res version
    my @files = sort $path->child('PIC')->children(qr/_A.JPG/);
    $files[0]->basename =~ m/.{39}(.{3})/;
    my $code = $1;
    ($free_status) = evaluate_code($code);
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
    $log->warn("Strange code $code");
  }
  return $free_status, $free_after;
}

