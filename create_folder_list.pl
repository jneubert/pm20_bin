#!/bin/env perl
# nbt, 2021-11-29

# creates the .md files for folder lists
# (links to all folders of a collection on one page)

# intended for pe and co, temporarily also for wa
# (for sh, categories work much better)

use strict;
use warnings;

use lib './lib';

use Data::Dumper;
use HTML::Template;
use JSON;
use Path::Tiny;
use Readonly;
use Unicode::Collate;
use YAML;
use ZBW::PM20x::Folder;

binmode( STDOUT, ":utf8" );
$Data::Dumper::Sortkeys = 1;

Readonly my $FOLDER_ROOT    => $ZBW::PM20x::Folder::FOLDER_ROOT;
Readonly my $FOLDER_WEBROOT => path('/pm20/web/folder');
Readonly my $IMAGEDATA_ROOT => path('/pm20/data/imagedata');
Readonly my %TITLE          => %{ YAML::LoadFile('archive_titles.yaml') };
Readonly my @COLLECTIONS    => qw/ co pe sh wa /;
Readonly my @LANGUAGES      => qw/ en de /;

my $tmpl =
  HTML::Template->new( filename => '../etc/html_tmpl/folderlist.md.tmpl' );

my ( $imagedata_file, $imagedata_ref );

# check arguments
if ( scalar(@ARGV) == 1 ) {
  if ( $ARGV[0] =~ m:^(co|pe|wa)$: ) {
    my $collection = $1;
    mk_collectionlist($collection);
  } elsif ( $ARGV[0] =~ m:^(co|pe)/(\d{6}): ) {
    my $collection = $1;
    my $folder_nk  = $2;
    mk_folder( $collection, $folder_nk );
  } elsif ( $ARGV[0] =~ m:^(sh|wa)/(\d{6},\d{6})$: ) {
    my $collection = $1;
    my $folder_nk  = $2;
    mk_folder( $collection, $folder_nk );
  } elsif ( $ARGV[0] eq 'ALL' ) {
    mk_all();
  } else {
    &usage;
  }
} else {
  &usage;
}

####################

sub mk_all {

  foreach my $collection (@COLLECTIONS) {
    mk_collectionlist($collection);
  }
}

sub mk_collectionlist {
  my $collection = shift or die "param missing";

  # load input files
  load_files($collection);

  foreach my $lang (@LANGUAGES) {

    # create partial lists keyed by start character
    my %abc;
    foreach my $folder_nk ( sort keys %{$imagedata_ref} ) {
      my $folder = ZBW::PM20x::Folder->new( $collection, $folder_nk );
      my $label  = $folder->get_folderlabel($lang);
      ## skip undefined folders (warning in Folder.pm)
      next unless $label;

      $label =~ s/&quot;//g;
      my $startchar = uc( substr( $label, 0, 1 ) );
      push( @{ $abc{$startchar} }, $folder );
    }

    my $uc = Unicode::Collate->new();
    my ( @tabs, @startchar_entries );
    foreach my $startchar ( sort { $uc->cmp( $a, $b ) } keys %abc ) {
      push( @tabs, { startchar => $startchar } );
      my @folders;
      my @folder_list =
        sort {
        $uc->cmp( $a->get_folderlabel($lang), $b->get_folderlabel($lang) )
        } @{ $abc{$startchar} };
      foreach my $folder (@folder_list) {
        my $label = $folder->get_folderlabel($lang);
        ## skip undefined folders (warning in Folder.pm)
        next unless $label;

        ##print $folder->get_folderlabel($lang), "\n";
        my $from_to = ( $folder->get_folderdata_raw )->{fromTo}
          || ( $folder->get_folderdata_raw )->{dateOfBirthAndDeath};
        my $path = $folder->get_folder_hashed_path->relative($collection)
          ->child("about.$lang.html");
        my %entry = (
          label   => $label,
          path    => "$path",
          from_to => $from_to,
        );
        push( @folders, \%entry );
      }
      my %entry = (
        "is_$lang"  => 1,
        startchar   => $startchar,
        folder_loop => \@folders,
      );
      push( @startchar_entries, \%entry );
    }
    my %tmpl_var = (
      "is_$lang"     => 1,
      provenance     => $TITLE{provenance}{hh}{$lang},
      label          => $TITLE{collection}{$collection}{$lang},
      backlink       => "../about.$lang.html",
      backlink_title => ( $lang eq 'de' ? 'Mappen' : 'folders' ),
      tab_loop       => \@tabs,
      startchar_loop => \@startchar_entries,
    );
    $tmpl->clear_params;
    $tmpl->param( \%tmpl_var );

    # write file
    my $out = $FOLDER_WEBROOT->child($collection)->child("about.$lang.md");
    $out->spew_utf8( $tmpl->output );
  }
}

sub load_files {
  my $collection = shift || die "param missing";

  $imagedata_file = $IMAGEDATA_ROOT->child("${collection}_image.json");
  $imagedata_ref  = decode_json( $imagedata_file->slurp );
}

sub usage {
  print "Usage: $0 {collection}|ALL\n";
  exit 1;
}

