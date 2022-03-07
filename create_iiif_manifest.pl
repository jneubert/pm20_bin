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
use HTML::Entities qw(encode_entities_numeric);
use HTML::Template;
use JSON;
use Path::Tiny;
use Readonly;
use ZBW::PM20x::Folder;

$Data::Dumper::Sortkeys = 1;

Readonly my $PM20_ROOT_URI   => 'https://pm20.zbw.eu/folder/';
Readonly my $FOLDER_ROOT_URI => 'http://purl.org/pressemappe20/folder/';
Readonly my $PDF_ROOT_URI    => 'https://pm20.zbw.eu/pdf/folder/';
## manifest files exist in the web tree
Readonly my $IIIF_ROOT       => path('../web/folder/');
Readonly my $IMAGEDATA_ROOT  => path('../data/imagedata');
Readonly my $DOCDATA_ROOT    => path('../data/docdata');
Readonly my $FOLDERDATA_ROOT => path('../data/folderdata');
Readonly my %RES_EXT         => (
  A => '_A.JPG',
  B => '_B.JPG',
  C => '_C.JPG',
);
Readonly my @LANGUAGES   => qw/ en de /;
Readonly my @COLLECTIONS => qw/ co pe sh wa /;

my %holding = (
  co => {
    type_label => 'Firma',
    prefix     => 'co/',
    url_stub   => {
      '/mnt/inst/F' => 'http://webopac.hwwa.de/DigiInst/F/',
      '/mnt/fors/F' => 'http://webopac.hwwa.de/DigiInst2/F/',
      '/mnt/pers/A' => 'http://webopac.hwwa.de/DigiInst/A/',
    },
  },
  pe => {
    type_label => 'Person',
    prefix     => 'pe/',
    url_stub   => {
      '/mnt/digidata/P' => 'http://webopac.hwwa.de/DigiPerson/P/',
    },
  },
  sh => {
    type_label => 'Sach',
    prefix     => 'sa/',
    url_stub   => {
      '/mnt/sach/S' => 'http://webopac.hwwa.de/DigiSach/S/',
    },
  },
  wa => {
    type_label => 'Ware',
    prefix     => 'wa/',
    url_stub   => {
      '/mnt/ware/W' => 'http://webopac.hwwa.de/DigiWare/W/',
    },
  },
);

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

    foreach my $lang (@LANGUAGES) {
      my $label = encode_entities_numeric( $folder->get_folderlabel($lang) );

      # feedback mailto
      my $mailto =
          "&#109;&#97;ilto&#58;p%72essema%70pe&#50;0&#64;&#37;&#55;Ab%77&#46;eu"
        . "?subject=Feedback%20zu%20PM20%20$label"
        . "&amp;body=%0D%0A%0D%0A%0D%0A---%0D%0A"
        . "https://pm20.zbw.eu/dfgview/$collection/$folder_nk";

      my $folder_uri = $folder->get_folder_uri;
      my %tmpl_var   = (
        folder_label => $label,
        manifest_uri => "$PM20_ROOT_URI$collection/$folder_nk/manifest.json",
        folder_uri   => $folder_uri,
        main_loop    => build_canvases( $collection, $folder_nk, $folder_uri ),
##        mailto        => $mailto,
      );
      $tmpl->param( \%tmpl_var );

      write_manifest( $type, $lang, $folder, $tmpl );
    }
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
  my $folder_id = shift || die "param missing";
  my $doc_id    = shift || die "param missing";
  my $page      = shift || die "param missing";

  my %imagedata = %{ $imagedata_ref->{$folder_id} };

  return
      $imagedata{root} . '/'
    . $imagedata{docs}{$doc_id}{rp}
    . "/${page}_A.JPG";
}

sub get_image_uri {
  my $collection = shift || die "param missing";
  my $folder_id  = shift || die "param missing";
  my $doc_id     = shift || die "param missing";
  my $image_id   = shift || die "param missing";

  return "$PM20_ROOT_URI${collection}/${folder_id}/${doc_id}/${image_id}";
}

sub get_image_dir {
  my $collection = shift || die "param missing";
  my $folder_id  = shift || die "param missing";
  my $doc_id     = shift || die "param missing";
  my $image_id   = shift || die "param missing";

  my $image_dir =
    $IIIF_ROOT->child($collection)->child($folder_id)->child($doc_id)
    ->child($image_id);
  $image_dir->mkpath;
  return $image_dir;
}

sub get_image_real_url {
  my $collection = shift || die "param missing";
  my $folder_id  = shift || die "param missing";
  my $doc_id     = shift || die "param missing";
  my $page       = shift || die "param missing";
  my $res        = shift || die "param missing";

  my %imagedata = %{ $imagedata_ref->{$folder_id} };

  # create url according to dir structure
  my $url =
      $holding{$collection}{url_stub}{ $imagedata{root} }
    . $imagedata{docs}{$doc_id}{rp} . '/'
    . $page
    . $RES_EXT{$res};

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
  my $collection = shift || die "param missing";
  my $folder_id  = shift || die "param missing";
  my $folder_uri = shift || die "param missing";

  my %imagedata = %{ $imagedata_ref->{$folder_id} };
  my %docdata   = %{ $docdata_ref->{$folder_id} };

  my @main_loop;
  my $i = 1;
  foreach my $doc_id ( sort keys %{ $docdata{free} } ) {
    my $page_no = 0;
    foreach my $page ( @{ $imagedata{docs}{$doc_id}{pg} } ) {

      my $real_max_url =
        get_image_real_url( $collection, $folder_id, $doc_id, $page, 'A' );
      my $max_image_fn = get_max_image_fn( $folder_id, $doc_id, $page );
      my $image_id     = substr( $page, 24, 4 );
      my $image_uri =
        get_image_uri( $collection, $folder_id, $doc_id, $image_id );
      my $image_dir =
        get_image_dir( $collection, $folder_id, $doc_id, $image_id );
      my ( $width, $height ) = get_dim( $max_image_fn, 'A' );
      my %entry = (
        image_no     => $page_no,
        canvas_label => get_doclabel( $doc_id, $docdata{info}{$doc_id} ),
        thumb_uri    => "$image_uri/thumbnail.jpg",
        img_uri      => $image_uri,
        real_max_url => $real_max_url,
        width        => $width,
        height       => $height,

      );
      push( @main_loop, \%entry );
      $page_no++;
      $i++;
    }
  }
  return \@main_loop;
}

sub write_manifest {
  my $type   = shift || die "param missing";
  my $lang   = shift || die "param missing";
  my $folder = shift || die "param missing";
  my $tmpl   = shift || die "param missing";

  my $hashed_path   = $folder->get_folder_hashed_path();
  my $manifest_dir  = $IIIF_ROOT->child($hashed_path);
  my $manifest_file = $manifest_dir->child("$type.manifest.$lang.json");
  $manifest_file->spew_utf8( $tmpl->output );
}

sub get_folderlabel {
  my $folder_id  = shift || die "param missing";
  my $type_label = shift || die "param missing";

  my %docdata = %{ $docdata_ref->{$folder_id} };

  # preferably, get data from folder data
  my $label;
  if ( exists $folderdata_ref->{$folder_id} ) {
    $label = $folderdata_ref->{$folder_id};
  } elsif ( exists $docdata{info}{"00001"}{IPERS} ) {
    $label = $docdata{info}{"00001"}{IPERS};
  } elsif ( exists $docdata{info}{"00001"}{NFIRM}
    and $docdata{info}{"00001"}{NFIRM} =~ m/::.+/ )
  {
    $label =
      ( split( /::/, $docdata{info}{"00001"}{NFIRM} ) )[1];
  } else {
    $label = "$type_label $folder_id";
  }
  return convert_label($label);
}

sub get_doclabel {
  my $doc_id    = shift || die "param missing";
  my $field_ref = shift || die "param missing";

  my $label;
  if ( $field_ref->{TIT} ) {
    ( $label = $field_ref->{TIT} ) =~ s/^t=//;
    if ( $field_ref->{AUT} ) {
      ( $label = $field_ref->{AUT} . ": " . $label ) =~ s/^v=//;
    }
  }
  if ( $field_ref->{NQUE} ) {
    my $src = $field_ref->{NQUE};
    if ( $field_ref->{DATE} ) {
      $src = "$src, $field_ref->{DATE}";
    }
    if ($label) {
      $label = "$label ($src)";
    } else {
      $label = $src;
    }
  }
  if ( not $label ) {
    if ( $field_ref->{ART} ) {
      if ( $field_ref->{ART} =~ m/::.+/ ) {
        $label = ( split( /::/, $field_ref->{ART} ) )[1] . ' ' . $doc_id;
      } else {
        $label = $field_ref->{ART} . ' ' . $doc_id;
      }
    } else {
      $label = "Dok $doc_id";
    }
  }
  if ( $field_ref->{PAG} ) {
    if ( $field_ref->{PAG} > 1 ) {
      $label .= " ($field_ref->{PAG} S.)";
    }
  } else {
    warn "Missing PAG for $doc_id: ", Dumper $field_ref;
  }
  return convert_label($label);
}

sub convert_label {
  my $label = shift || die "param missing";

  $label = Encode::encode( 'utf-8', $label );
  $label = encode_entities_numeric( $label, '<>&"' );

  return $label;
}

sub get_folder_relative_path {
  my $folder_id = shift || die "param missing";

  my %imagedata = %{ $imagedata_ref->{$folder_id} };

  my $folder_relative_path;
  foreach my $doc_id ( keys %{ $imagedata{docs} } ) {
    my $doc_relative_path = path( $imagedata{docs}{$doc_id}{rp} );
    $folder_relative_path = $doc_relative_path->parent(4);
    last;
  }
  return $folder_relative_path;
}

sub usage {
  print "Usage: $0 {folder-id}|{collection}|ALL\n";
  exit 1;
}

