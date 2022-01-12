#!/bin/env perl
# nbt, 28.5.2018

# Create a PM20 folder PDF from METS und JPEGs

# to be called with the PDF url, redirects to that one when finished

use strict;
use warnings;

use CGI;
use CGI::Push qw(:standard);
use Data::Dumper;
use File::Temp;
use Path::Tiny;
##use Plack::Request;
##use Plack::Response;
use Readonly;

Readonly my $PDF_ROOT      => '/srv/pm20pdf/';
Readonly my $METS_URL_ROOT => 'http://zbw.eu/beta/pm20mets/';
Readonly my $PDF_URL_ROOT  => 'http://zbw.eu/beta/pm20pdf/';

# init
my $q = CGI->new;

##$File::Temp::KEEP_ALL = 1;
my $tempdir  = File::Temp::tempdir('/srv/tmp/.folder2pdfXXXXXXXX');
my $log_file = "$tempdir/build.log";

# init log to avoid race condition
path($log_file)->touch;

# read param
my $pdf_url = $q->param('pdf');

# validate $pdf_url
if ( not $pdf_url ) {
  print $q->header( 'text/plain', '400 Bad Request' );
  print "Missing PDF URL\n";
  exit;
}

if ( not $pdf_url =~ m/^$PDF_URL_ROOT([a-z0-9\/\.])+$/ ) {
  print $q->header( 'text/plain', '400 Bad Request' );
  print "Mal-formed PDF URL: $pdf_url\n";
  exit;
}

##print "Content-type: text/plain\n\n";
##print "Creating folder pdf ...\n";

# fork this process
my $pid = fork();
die "Fork failed: $!" if !defined $pid;

if ( $pid == 0 ) {

  # do this in the child
  open STDIN,  "</dev/null";
  open STDOUT, ">/dev/null";
  open STDERR, ">/dev/null";
  ##system('bash -c \'(sleep 10; touch ./test_file)\'&');
  system("perl /usr/local/bin/folder2pdf.pl $pdf_url $log_file \&");
  exit;
}

do_push(
  -next_page => \&next_page,
  -last_page => \&last_page,
  -delay     => 1,
  -nph       => 0,
  -type      => 'dynamic',
);

sub next_page {
  my $message = `cat $log_file`;

  if ( $message =~ m/Done/msx ) {
    return undef;
  }
  return "Content-type: text/plain\n\n", $message;
}

sub last_page {

  # redirect to the newly created file
  return $q->header(
    -refresh => "5; URL=$pdf_url",
    -type    => 'text/html'
  ), 'Done. Please reload, if PDF is not downloaded automatically.';
}

####################

sub url_ok {
  my $pdf_url = shift or die "param missing\n";

  if ( $pdf_url =~ m/^${PDF_URL_ROOT}[a-z0-9\/\.]+$/ ) {
    return 1;
  } else {
    return 0;
  }
}

