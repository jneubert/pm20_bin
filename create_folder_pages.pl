#!/bin/env perl
# nbt, 2021-10-26

# Create the folder tree for the web directory, and
# create symlinks for actual document directories

# can be invoked either by
# - an extended folder id (e.g., pe/000012)
# - a collection id (e.g., pe)
# - 'ALL' (to (re-) create all collections)

use strict;
use warnings;

use lib './lib';

use Data::Dumper;
use HTML::Template;
use JSON;
use Path::Tiny;
use Readonly;
use YAML;
use ZBW::PM20x::Folder;

Readonly my $FOLDER_ROOT    => $ZBW::PM20x::Folder::FOLDER_ROOT;
Readonly my $FOLDER_WEBROOT => path('/pm20/web/folder.new');
Readonly my $IMAGEDATA_ROOT => path('/pm20/data/imagedata');
Readonly my %TITLE          => %{ YAML::LoadFile('archive_titles.yaml') };
Readonly my @COLLECTIONS    => qw/ co pe sh wa /;
Readonly my @LANGUAGES      => qw/ en de /;

my $tmpl = HTML::Template->new( filename => '../etc/html_tmpl/folder.md.tmpl' );

my ( $imagedata_file, $imagedata_ref );

# check arguments
if ( scalar(@ARGV) == 1 ) {
  if ( $ARGV[0] =~ m:^(co|pe|wa|sh)$: ) {
    my $collection = $1;
    mk_collection($collection);
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
    mk_collection($collection);
  }
}

sub mk_collection {
  my $collection = shift or die "param missing";

  # load input files
  load_files($collection);

  foreach my $folder_nk ( sort keys %{$imagedata_ref} ) {
    mk_folder( $collection, $folder_nk );
  }
}

sub mk_folder {
  my $collection = shift || die "param missing";
  my $folder_nk  = shift || die "param missing";

  my $folder = ZBW::PM20x::Folder->new( $collection, $folder_nk );

  # check if folder dir exists
  my $rel_path  = $folder->get_folder_hashed_path();
  my $full_path = $FOLDER_ROOT->child($rel_path);
  if ( not -d $full_path ) {
    die "$full_path does not exist\n";
  }

  # open files if necessary
  # (check with arbitrary entry)
  if ( not defined $imagedata_ref ) {
    load_files($collection);
  }

  # create folder dir (including hashed level)
  my $folder_dir = $FOLDER_WEBROOT->child($rel_path);
  $folder_dir->mkpath;

  # TODO type public/intern
  my $type           = 'dummy';
  my $folderdata_raw = $folder->get_folderdata_raw;
  print Dumper $folderdata_raw;
  my $doc_counts =
    $folderdata_raw->{freeDocCount} . ' / ' . $folderdata_raw->{totalDocCount};

  foreach my $lang (@LANGUAGES) {
    my $label = $folder->get_folderlabel($lang);

    my %tmpl_var = (
      "is_$lang"  => 1,
      provenance  => $TITLE{provenance}{hh}{$lang},
      coll        => $TITLE{collection}{$collection}{$lang},
      label       => $label,
      folder_uri  => $folder->get_folder_uri,
      dfgview_url => $folder->get_dfgview_url,
      fid         => "$collection/$folder_nk",
      doc_counts  => $doc_counts,
    );

    if ( $folderdata_raw->{note} ) {
      my @notes = @{ $folderdata_raw->{note} };
      $tmpl_var{note} = join( "<br>", @notes );
    }

    if ( $collection eq 'pe' or $collection eq 'co' ) {
      $tmpl_var{from_to} =
        ( $folderdata_raw->{dateOfBirthAndDeath} || $folderdata_raw->{fromTo} );
      $tmpl_var{gnd} = $folderdata_raw->{gndIdentifier};
    }
    if ( $collection eq 'co' ) {
      $tmpl_var{location} =
        get_field_values( $lang, $folderdata_raw, 'location' );
    }
    $tmpl->clear_params;
    $tmpl->param( \%tmpl_var );
    print Dumper \%tmpl_var;

    # write  file for the folder
    write_page( $type, $lang, $folder, $tmpl );
  }
}

sub load_files {
  my $collection = shift || die "param missing";

  $imagedata_file = $IMAGEDATA_ROOT->child("${collection}_image.json");
  $imagedata_ref  = decode_json( $imagedata_file->slurp );
}

sub usage {
  print "Usage: $0 {folder-id}|{collection}|ALL\n";
  exit 1;
}

sub write_page {
  my $type   = shift || die "param missing";
  my $lang   = shift || die "param missing";
  my $folder = shift || die "param missing";
  my $tmpl   = shift || die "param missing";

  my $page_dir = $folder->get_folder_hashed_path();
  $page_dir = $FOLDER_WEBROOT->child($page_dir);
  my $page_file = $page_dir->child("about.$lang.md");

  # remove blank lines (necessary for pipe tables)
  # within fenced block
  my $lines = $tmpl->output();
  $lines =~ m/\A(.*?::: .*?\n)(.*)(\n:::\n.*)\z/ms;
  my $start  = $1;
  my $fenced = $2;
  my $end    = $3;
  $fenced =~ s/\n+/\n/mg;
  $lines = "$start$fenced$end";

  $page_file->spew_utf8($lines);
  print "written $page_file\n";
}

sub get_field_values {
  my $lang           = shift || die "param missing";
  my $folderdata_raw = shift || die "param missing";
  my $field          = shift || die "param missing";

  my @field_values;
  foreach my $field_ref ( @{ $folderdata_raw->{$field} } ) {
    next unless $field_ref->{'@language'} eq $lang;
    push( @field_values, $field_ref->{'@value'} );
  }

  my $values = join( '; ', @field_values );
  return $values;
}

