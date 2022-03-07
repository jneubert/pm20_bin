#!/bin/perl
# nbt, 31.1.2018

# create a IIIF manifest for pm20 folders

use strict;
use warnings;

use Data::Dumper;
use Encode;
use HTML::Entities;
use HTML::Template;
use JSON;
use Path::Tiny;

$Data::Dumper::Sortkeys = 1;

##my $pm20_root_uri = 'http://pm20.zbw.eu/folder/';
my $pm20_root_uri   = 'https://pm20.zbw.eu/folder/';
my $folder_root_uri = 'http://purl.org/pressemappe20/folder/';
my $pdf_root_uri    = 'https://pm20.zbw.eu/pdf/folder/';
my $iiif_root       = path('../web/folder/');
##my $iiif_root       = path('/disc1/pm20/folder');
my $imagedata_root  = path('../data/imagedata');
my $docdata_root    = path('../data/docdata');
my $folderdata_root = path('../data/folderdata');

my %res_ext = (
  A => '_A.JPG',
  B => '_B.JPG',
  C => '_C.JPG',
);

my %holding = (

  #  test => {
  #    prefix   => 'pe/',
  #    url_stub => {
  #      '/mnt/digidata/P' => 'http://webopac.hwwa.de/DigiPerson/P/',
  #    },
  #  },
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

my $manifest_tmpl = HTML::Template->new(
  filename          => '../etc/html_tmpl/static_manifest.json.tmpl',
  loop_context_vars => 1
);

my (
  $docdata_file, $imagedata_file, $imagesize_file, $folderdata_file,
  $docdata_ref,  $imagedata_ref,  $imagesize_ref,  $folderdata_ref
);

foreach my $collection ( sort keys %holding ) {

  # TODO reactivate
  next unless $collection eq 'co';

  # load input files
  $docdata_file    = $docdata_root->child("${collection}_docdata.json");
  $docdata_ref     = decode_json( $docdata_file->slurp );
  $imagedata_file  = $imagedata_root->child("${collection}_image.json");
  $imagedata_ref   = decode_json( $imagedata_file->slurp );
  $imagesize_file  = $imagedata_root->child("${collection}_size.json");
  $imagesize_ref   = decode_json( $imagesize_file->slurp );
  $folderdata_file = $folderdata_root->child("${collection}_label.json");
  $folderdata_ref  = decode_json( $folderdata_file->slurp );

  foreach my $folder_id ( sort keys %{$docdata_ref} ) {

    # TODO reactivate
    next unless $folder_id eq "019784";

    # skip if none of the folder's articles are free
    next unless exists $docdata_ref->{$folder_id}{free};

    my $label =
      get_folderlabel( $folder_id, $holding{$collection}{type_label} );
    my $folder_uri = "$folder_root_uri$holding{$collection}{prefix}$folder_id";
    my $pdf_url =
        $pdf_root_uri
      . "$collection/"
      . get_folder_relative_path($folder_id)
      . "/${folder_id}.pdf";

    # create iiif manifest
    my %manifest_tmpl_var = (
      folder_label => $label,
      manifest_uri => "$pm20_root_uri$collection/$folder_id/manifest.json",
      folder_uri   => $folder_uri,
      main_loop    => build_canvases( $collection, $folder_id, $folder_uri ),
    );
    $manifest_tmpl->param( \%manifest_tmpl_var );
    write_manifest( $collection, $folder_id, $manifest_tmpl );

    # create url aliases for awstats
    ##print $url_fh "/beta/pm20mets/$collection/"
    ##  . get_folder_relative_path($folder_id)
    ##  . "/${folder_id}.xml\t$label\n";
  }
}

## TODO reactivate
##close($url_fh);

####################

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

  return "$pm20_root_uri${collection}/${folder_id}/${doc_id}/${image_id}";
}

sub get_image_dir {
  my $collection = shift || die "param missing";
  my $folder_id  = shift || die "param missing";
  my $doc_id     = shift || die "param missing";
  my $image_id   = shift || die "param missing";

  my $image_dir =
    $iiif_root->child($collection)->child($folder_id)->child($doc_id)
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
    . $res_ext{$res};

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
  my $collection    = shift || die "param missing";
  my $folder_id     = shift || die "param missing";
  my $manifest_tmpl = shift || die "param missing";

  my %docdata = %{ $docdata_ref->{$folder_id} };

  my $json = $manifest_tmpl->output;

  my $manifest_dir = $iiif_root->child($collection)->child($folder_id);
  $manifest_dir->mkpath;
  my $manifest_file = $manifest_dir->child('manifest.json');
  $manifest_file->spew($json);
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
  $label = encode_entities( $label, '<>&"' );

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

