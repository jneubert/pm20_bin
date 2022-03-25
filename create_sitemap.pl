#!/bin/env perl
# nbt, 2022-03-25

use strict;
use warnings;

use utf8;

use Data::Dumper;
use Web::Sitemap;

$Data::Dumper::Sortkeys = 1;

my $sm = Web::Sitemap->new(
  output_dir => '/var/tmp',

  ### Options ###

  temp_dir    => '/tmp',
  loc_prefix  => 'https://pm20.zbw.eu',
  index_name  => 'sitemap',
  file_prefix => 'sitemap.',

  # mark for grouping urls
  ##default_tag => 'my_tag',

# add <mobile:mobile/> inside <url>, and appropriate namespace (Google standard)
  mobile => 1,

  # add appropriate namespace (Google standard)
  ##images      => 1,

  # additional namespaces (scalar or array ref) for <urlset>
  ##namespace   => 'xmlns:some_namespace_name="..."',

  # location prefix for files-parts of the sitemap (default is loc_prefix value)
  ## file_loc_prefix  => 'http://my_domain.com',

  # specify data input charset
  charset => 'utf8',

##        move_from_temp_action => sub {
##                my ($temp_file_name, $public_file_name) = @_;

  # ...some action...
  #
  # default behavior is
  # File::Copy::move($temp_file_name, $public_file_name);
##        }

);

# not used - would only make sense with enhanced prio
my @main_url_list = (
  qw {
    /about.de.html
    /about.en.html
  }
);
##$sm->add( \@main_url_list, tag => 'main' );

# work through all sets used in make
foreach my $set (qw/ default category co pe sh wa /) {
  my $url_list_ref = get_urls($set);
  $sm->add( $url_list_ref, tag => $set );
}

# After calling finish() method will create an index file, which will link to files with URL's
$sm->finish;

# rough overview
print Dumper $sm;

###################

sub get_urls {
  my $set = shift or die "param missing";

  my $url_list_ref;
  my @temp = `/bin/sh /pm20/web/mk/find_md.sh $set`;
  foreach my $line (@temp) {
    chomp($line);
    $line = substr( $line, 1, );
    $line =~ s/(.+)?\.md$/$1\.html/;
    push( @$url_list_ref, $line );
  }

  return $url_list_ref;
}
