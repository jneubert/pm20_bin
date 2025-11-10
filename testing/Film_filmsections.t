# 03.11.2025

use strict;
use warnings;

use lib '../lib';

use Data::Dumper;

use Test::More;

my $class = 'ZBW::PM20x::Film';

use_ok($class) or die "Could not load $class\n";

my $struct = $class->get_grouping_properties('wa');

ok($struct, 'get grouping wa');

#warn(Dumper $struct);

my ( $ware_id, $geo_id, $subject_id, $filming, @waresections, @geosections, @subjectsections );


# Tests for secondary sections


# testcase film/h1/wa/W0087H/0002 (Eisenwaren : Österreich)
# film.jsonld comprises 
#   - is arbitrary (beginning of new film, not beginning of geo
#     (as indicated by start date 1932))

$ware_id = 142275;
$geo_id = 141731; 
$filming = 1;

@waresections = $class->categorysections('ware', $ware_id, $filming);
ok(@waresections, "ware $ware_id has sections in filming $filming");

#warn(Dumper \@waresections);

@geosections = $class->categorysections_inv('geo', $geo_id, $filming);
ok(@geosections, "geo $geo_id has ware sections in filming $filming");

#warn(Dumper \@geosections);

# create a lookup hash of ware ids for the geo (just for testing)
my %ware =  map  { $_->{ware}{'@id'} =~ m/\/(\d+)$/ => 1 } @geosections;

# TODO inverse logic, when sections with start date are excluded
ok( $ware{$ware_id}, "section for ware id $ware_id in result");

#warn(Dumper \%ware_id);


# test case film/h1/sh/S0234H/0173/L (Polen : Seeschiffahrt)
$subject_id = 145567;
$geo_id = 140962; 

@subjectsections = $class->categorysections_inv('subject', $subject_id, $filming);
ok(@subjectsections, "subject $subject_id has geo sections in filming $filming");

# create a lookup hash of geo ids for the subject (just for testing)
my %geo =  map  { $_->{country}{'@id'} =~ m/\/(\d+)$/ => 1 } @subjectsections;
ok( $geo{$geo_id}, "section for geo id $geo_id in result");


done_testing;
