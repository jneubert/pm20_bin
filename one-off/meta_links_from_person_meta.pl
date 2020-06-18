#!/bin/env perl
# nbt, 2020-06-18

# In the folder for Herbert Backe, most locked articles are by himself.
# Therefore, create meta.yaml symlinks in locked document dirs to
# folder_person_meta.yaml.
# CAUTION: For documents with other authors, meta.yaml has to be removed
# manually!

use strict;
use warnings;

use Path::Tiny;

my $folder_id = 'pe/000839';
( my $extended = $folder_id ) =~ s|(pe)/(\d{4})(\d{2})|$1/$2xx/$2$3|;
my $root = path( '/disc1/pm20/folder/' . $extended );
##print "$root\n";

foreach my $hashed ( $root->children() ) {
  foreach my $path ( $hashed->children() ) {
    next unless $path->is_dir();
    if ( $path->child('.htaccess')->is_file ) {
      my $person_meta   = $root->child('folder_person_meta.yaml');
      my $document_meta = $path->child('meta.yaml');
      symlink( $person_meta, $document_meta )
        or die "Could not create $document_meta: $!\n";
      print "$document_meta\n";
    }
  }
}
