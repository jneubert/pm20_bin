#!/bin/env perl
# nbt, 3.7.2020

# read all pm20 annotations from hypothes.is

use strict;
use warnings;

##use Hypothesis::API;
use Data::Dumper;
use JSON;
use REST::Client;
use Readonly;

Readonly my $READ_ALL_URL =>
  'https://hypothes.is/api/search?wildcard_uri=https://pm20intern.zbw.eu/*';

my $client = REST::Client->new();
$client->GET($READ_ALL_URL);
my $res = decode_json( $client->responseContent() );

##print Dumper $res;

foreach my $entry (@{$res->{rows}}) {
  print $entry->{uri}, "\t", $entry->{text}, "\n";
  my @list = split(/\$/, $entry->{text});
  print Dumper \@list;
}


