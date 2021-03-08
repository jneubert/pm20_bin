#!/bin/perl
# nbt, 8.3.2021

# create aliases for folders and collections

use strict;
use warnings;
use utf8;

use lib './lib';

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use ZBW::PM20x::Folder;

$Data::Dumper::Sortkeys = 1;

Readonly my $IMAGEDATA_ROOT => path('../data/imagedata');
Readonly my $KLASSDATA_ROOT => path('../data/klassdata');
Readonly my $URLALIAS_FILE  => path("../var/awstats/urlalias.pm20.txt");

# open alias file
open( my $alias_fh, '>:encoding(cp1252)', $URLALIAS_FILE );

# static aliases
print $alias_fh <<"EOF";
/\tHome
/film/\tDigitalisierte Filme
/list/publication/\tListe der Zeitungen und Zeitschriften
/doc/holding/\tBestandsübersicht
/category/geo/\tMappen nach Ländersystematik
/category/subject/\tMappen nach Sachsystematik
EOF

# collections
foreach my $collection (qw/ pe sh /) {

  # load input file
  my $imagedata_file = $IMAGEDATA_ROOT->child("${collection}_image.json");
  my $imagedata_ref  = decode_json( $imagedata_file->slurp );

  foreach my $folder_nk ( sort keys %{$imagedata_ref} ) {
    my $folder = ZBW::PM20x::Folder->new( $collection, $folder_nk );

    print $alias_fh '/mets/' . $folder->get_folder_hashed_path() . "/\t"
      . ( $folder->get_folderlabel('de') || 'label_missing' ), "\n";
  }
}

# categories
foreach my $vocab (qw/ geo subject /) {
  my $klassdata_file = $KLASSDATA_ROOT->child("${vocab}_by_signature.de.json");
  my $klassdata_ref = decode_json( $klassdata_file->slurp );
  foreach my $entry (@{$klassdata_ref->{results}{bindings}}) {
    my $uri = defined $entry->{category} ? $entry->{category}{value} : $entry->{country}{value};
    my $label = defined $entry->{categoryLabel} ? $entry->{categoryLabel}{value} : $entry->{countryLabel}{value};
    my $signature = $entry->{signature}{value};
    (my $id = $uri) =~ s|.+/(\d{6})$|$1|;
    print $alias_fh "/category/$vocab/i/$id/\t$signature $label\n";
  }
  
}

close($alias_fh);

