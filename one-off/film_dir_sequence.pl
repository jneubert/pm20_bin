#/bin/env perl
# nbt, 15.2.22
#
# Sequene of real film directories (excluding directories of symlinks, which
# merge two half films)
#
use strict;
use warnings;
use v5.10;

use Path::Tiny;

my @dir_seq = ();

my @subsets = qw: h1/sh h2/sh :;
foreach my $subset (@subsets) {
  my @dirs = path("/pm20/film/$subset")->children;

  foreach my $dir ( sort @dirs ) {
    next unless $dir->is_dir;
    $dir = $dir->basename;

    # remove previous dir, if current is a part of the previous
    my $prev = $dir_seq[-1];
    if ( $prev and $dir =~ m/^$prev/ ) {
      pop(@dir_seq);
    }

    push( @dir_seq, "\"$dir\"" );
  }

  my @statements;
  push( @statements, '<?php function prev_next_film ($film_id) {' );
  push( @statements, '$filmlist = ' );
  push( @statements, '[', join( ',', @dir_seq ), '];' );
  push( @statements, '$index = array_search($film_id, $filmlist);' );
  push( @statements, 'if ($index != 0) { $prev = $filmlist[$index-1]; }' );
  push( @statements, 'if ($index != array_slice($filmlist, -1)) { $next = $filmlist[$index+1]; }');
  push( @statements, 'return [ $prev, $next ];' );
  push( @statements, '}' );

  ( my $infix = $subset ) =~ s;/;_;;
  path("/pm20/web/film/prev_next_film.$infix.inc")
    ->spew( join( "\n", @statements ) );
}
