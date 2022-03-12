#!/bin/perl
# nbt, 31.1.2018

# create a IIIF manifest files for pm20 folders

# can be invoked either by
# - an extended folder id (e.g., pe/000012)
# - a collection id (e.g., pe)
# - 'ALL' (to (re-) create all collections)

use strict;
use warnings;
use utf8;

use lib './lib';

use Data::Dumper;
use Encode;
use HTML::Entities;
use HTML::Template;
use JSON;
use Path::Tiny;
use Readonly;
use ZBW::PM20x::Folder;

$Data::Dumper::Sortkeys = 1;

Readonly my $PM20_ROOT_URI   => 'https://pm20.zbw.eu/folder/';
Readonly my $IIIF_ROOT_URI   => 'https://pm20.zbw.eu/iiif/folder/';
Readonly my $FOLDER_ROOT_URI => 'http://purl.org/pressemappe20/folder/';
Readonly my $PDF_ROOT_URI    => 'https://pm20.zbw.eu/pdf/folder/';
## manifest files exist in the web tree
Readonly my $IIIF_ROOT       => path('/pm20/iiif/folder');
Readonly my $IMAGEDATA_ROOT  => path('/pm20/data/imagedata');
Readonly my $DOCDATA_ROOT    => path('/pm20/data/docdata');
Readonly my $FOLDERDATA_ROOT => path('/pm20/data/folderdata');
Readonly my %RES_EXT         => (
  A => '_A.JPG',
  B => '_B.JPG',
  C => '_C.JPG',
);
Readonly my @LANGUAGES   => qw/ en de /;
Readonly my @COLLECTIONS => qw/ co pe sh wa /;

my $tmpl = HTML::Template->new(
  filename          => '../etc/html_tmpl/static_manifest.json.tmpl',
  utf8              => 1,
  loop_context_vars => 1
);

my (
  $docdata_file, $imagedata_file, $imagesize_file, $folderdata_file,
  $docdata_ref,  $imagedata_ref,  $imagesize_ref,  $folderdata_ref
);

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
  my $full_path = $ZBW::PM20x::Folder::FOLDER_ROOT->child($rel_path);
  if ( not -d $full_path ) {
    die "$full_path does not exist\n";
  }

  # open files if necessary
  # (check with arbitrary entry)
  if ( not defined $imagedata_ref ) {
    load_files($collection);
  }

  # TODO clearly wrong - change to public/intern pdfs?
  my $pdf_url = $PDF_ROOT_URI . "$rel_path/${folder_nk}.pdf";

  foreach my $type ( 'public', 'intern' ) {

    # get document list, skip if empty
    my $doclist_ref = $folder->get_doclist($type);
    next unless $doclist_ref and scalar( @{$doclist_ref} ) gt 0;

    my $folder_uri = $folder->get_folder_uri;
    my ( $main_loop_ref, $doc_loop_ref ) = build_canvases($folder);
    my %tmpl_var = (
      manifest_uri => "${IIIF_ROOT_URI}$collection/$folder_nk/manifest.json",
      folder_uri   => $folder_uri,
      main_loop    => $main_loop_ref,
      doc_loop     => $doc_loop_ref,
    );

    foreach my $lang (@LANGUAGES) {

      # label
      my $label = decode_entities( $folder->get_folderlabel($lang) );
      $tmpl_var{"folder_label_$lang"} = $label;

      # feedback mailto
      my $mailto =
          "&#109;&#97;ilto&#58;p%72essema%70pe&#50;0&#64;&#37;&#55;Ab%77&#46;eu"
        . "?subject=Feedback%20zu%20PM20%20$label"
        . "&amp;body=%0D%0A%0D%0A%0D%0A---%0D%0A"
        . "https://pm20.zbw.eu/dfgview/$collection/$folder_nk";

      ##$tmpl_var{mailto} = $mailto;
    }

    $tmpl->param( \%tmpl_var );

    write_manifest( $type, $folder, $tmpl );
  }
}

sub load_files {
  my $collection = shift || die "param missing";

  $docdata_file    = $DOCDATA_ROOT->child("${collection}_docdata.json");
  $docdata_ref     = decode_json( $docdata_file->slurp );
  $imagedata_file  = $IMAGEDATA_ROOT->child("${collection}_image.json");
  $imagedata_ref   = decode_json( $imagedata_file->slurp );
  $imagesize_file  = $IMAGEDATA_ROOT->child("${collection}_size.json");
  $imagesize_ref   = decode_json( $imagesize_file->slurp );
  $folderdata_file = $FOLDERDATA_ROOT->child("${collection}_label.json");
  $folderdata_ref  = decode_json( $folderdata_file->slurp );
}

sub get_max_image_fn {
  my $folder_nk = shift || die "param missing";
  my $doc_id    = shift || die "param missing";
  my $page      = shift || die "param missing";

  my %imagedata = %{ $imagedata_ref->{$folder_nk} };

  return
      $imagedata{root} . '/'
    . $imagedata{docs}{$doc_id}{rp}
    . "/${page}_A.JPG";
}

sub get_doc_uri {
  my $collection = shift || die "param missing";
  my $folder_nk  = shift || die "param missing";
  my $doc_id     = shift || die "param missing";

  return "${IIIF_ROOT_URI}$collection/${folder_nk}/${doc_id}";
}

sub get_image_uri {
  my $collection = shift || die "param missing";
  my $folder_nk  = shift || die "param missing";
  my $doc_id     = shift || die "param missing";
  my $page_no    = shift || die "param missing";

  my $doc_uri = get_doc_uri( $collection, $folder_nk, $doc_id );
  $page_no = sprintf( "%04d", $page_no );
  return "$doc_uri/${page_no}";
}

sub get_image_dir {
  my $folder   = shift || die "param missing";
  my $doc_id   = shift || die "param missing";
  my $image_id = shift || die "param missing";

  my $image_dir = get_manifest_dir($folder)->child($doc_id)->child($image_id);
  $image_dir->mkpath;
  return $image_dir;
}

sub get_image_real_url {
  my $folder = shift || die "param missing";
  my $doc_id = shift || die "param missing";
  my $page   = shift || die "param missing";
  my $res    = shift || die "param missing";

  # create url according to dir structure
  my $url =
      $PM20_ROOT_URI
    . $folder->get_document_hashed_path($doc_id)->child('PIC')
    ->child( $page . $RES_EXT{$res} );

  return $url;
}

sub get_dim {
  my $max_image_fn = shift || die "param missing";
  my $res          = shift || die "param missing";

  my $width  = $imagesize_ref->{$max_image_fn}{$res}{w};
  my $height = $imagesize_ref->{$max_image_fn}{$res}{h};
  return ( $width, $height );
}

sub build_canvases {
  my $folder = shift || die "param missing";

  my $collection = $folder->{collection};
  my $folder_nk  = $folder->{folder_nk};

  my %imagedata = %{ $imagedata_ref->{$folder_nk} };
  my %docdata   = %{ $docdata_ref->{$folder_nk} };

  my @main_loop;
  my @doc_loop;
  foreach my $doc_id ( sort keys %{ $docdata{free} } ) {

    my @page_loop;
    my %doc_entry =
      ( doc_uri => get_doc_uri( $collection, $folder_nk, $doc_id ), );
    foreach my $lang (@LANGUAGES) {
      my $label = decode_entities( $folder->get_doclabel( $lang, $doc_id ) );
      $doc_entry{"doc_label_$lang"} = $label;
    }

    # cannot be enumerated independently from file names, because in
    # create_iiif_img.pl only file names are available!
    ##my $page_no = 1;
    foreach my $page ( @{ $imagedata{docs}{$doc_id}{pg} } ) {

      my $real_max_url = get_image_real_url( $folder, $doc_id, $page, 'A' );
      my $max_image_fn = get_max_image_fn( $folder_nk, $doc_id, $page );
      my $image_id     = substr( $page, 24, 4 );
      ## file name is 0 based; start page numbers with 1
      my $page_no = $image_id + 1;

      my $image_uri =
        get_image_uri( $collection, $folder_nk, $doc_id, $page_no );
      my $canvas_uri = "$image_uri/canvas";
      my $image_dir  = get_image_dir( $folder, $doc_id, $image_id );
      ## w,h are here only used for aspect ratio
      my ( $width, $height ) = get_dim( $max_image_fn, 'A' );
      my %entry = (
        canvas_uri   => $canvas_uri,
        thumb_uri    => "$image_uri/thumbnail.jpg",
        img_uri      => $image_uri,
        real_max_url => $real_max_url,
        width        => $width,
        height       => $height,

      );

      foreach my $lang (@LANGUAGES) {
        my $label = $lang eq 'en' ? 'p. ' : 'S. ';
        $label .= "$page_no ("
          . decode_entities( $folder->get_doclabel( $lang, $doc_id ) ) . ')';
        $entry{"canvas_label_$lang"} = $label;
      }

      push( @main_loop, \%entry );
      push( @page_loop, { canvas_uri => $canvas_uri } );
      ##$page_no++;
    }
    $doc_entry{page_loop} = \@page_loop;
    push( @doc_loop, \%doc_entry );
  }
  return \@main_loop, \@doc_loop;
}

sub get_manifest_dir {
  my $folder = shift || die "param missing";

  my $dir =
    $IIIF_ROOT->child( $folder->{collection} )->child( $folder->{folder_nk} );
  $dir->mkpath;

  return $dir;
}

sub write_manifest {
  my $type   = shift || die "param missing";
  my $folder = shift || die "param missing";
  my $tmpl   = shift || die "param missing";

  my $manifest_file = get_manifest_dir($folder)->child("$type.manifest.json");
  $manifest_file->spew_utf8( $tmpl->output );
}

sub usage {
  print "Usage: $0 {folder-id}|{collection}|ALL\n";
  exit 1;
}

