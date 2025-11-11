# 07.11.2025

# verify that lists of sections for company folders are generated

use strict;
use warnings;

use lib '../lib';

use Data::Dumper;

use Test::More;

my $class = 'ZBW::PM20x::Folder';

use_ok($class) or die "Could not load $class\n";

my $collection = 'co';
my $folder_nk  = "041389" . "";

done_testing;
