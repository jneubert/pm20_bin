#!/bin/perl
# nbt, 31.1.2018

# traverses image share and folder roots

use strict;
use warnings;

use Data::Dumper;
use Encode;
use HTML::Entities;
use HTML::Template;
use Image::Thumbnail;
use JSON;
use Path::Tiny;

$Data::Dumper::Sortkeys = 1;

# TODO different root uri for public/non-public file?
my $pm20_root_uri  = 'https://pm20.zbw.eu/folder/';
my $iiif_root      = path('/pm20/folder');
my $imagedata_root = path('../data/imagedata');

my %res_ext = (
  A => '_A.JPG',
  B => '_B.JPG',
  C => '_C.JPG',
);

my %holding = (

  co => {
    url_stub => {
      '/mnt/inst/F' => 'http://webopac.hwwa.de/DigiInst/F/',
      '/mnt/fors/F' => 'http://webopac.hwwa.de/DigiInst2/F/',
      '/mnt/pers/A' => 'http://webopac.hwwa.de/DigiInst/A/',
    },
  },
  pe => {
    url_stub => {
      '/mnt/digidata/P' => 'http://webopac.hwwa.de/DigiPerson/P/',
    },
  },
  sh => {
    url_stub => {
      '/mnt/sach/S' => 'http://webopac.hwwa.de/DigiSach/S/',
    },
  },
  wa => {
    url_stub => {
      '/mnt/ware/W' => 'http://webopac.hwwa.de/DigiWare/W/',
    },
  },
);

my $info_tmpl =
  HTML::Template->new( filename => '../etc/html_tmpl/info.json.tmpl', );

my ( $imagedata_file, $imagesize_file, $imagedata_ref, $imagesize_ref, );

foreach my $holding_name ( sort keys %holding ) {

  # TODO reactivate
  next unless $holding_name eq 'co';

  # load input files
  $imagedata_file = $imagedata_root->child("${holding_name}_image.json");
  $imagedata_ref  = decode_json( $imagedata_file->slurp );
  $imagesize_file = $imagedata_root->child("${holding_name}_size.json");
  $imagesize_ref  = decode_json( $imagesize_file->slurp );

  foreach my $folder_id ( sort keys %{$imagedata_ref} ) {

    # TODO reactivate
    next unless $folder_id eq "019784";

    foreach my $doc_id ( keys %{ $imagedata_ref->{$folder_id}{docs} } ) {

      foreach my $page ( @{ $imagedata_ref->{$folder_id}{docs}{$doc_id}{pg} } )
      {
        my $max_image_fn = get_max_image_fn( $folder_id, $doc_id, $page );
        my $image_id     = substr( $page, 24, 4 );
        my $image_uri =
          get_image_uri( $holding_name, $folder_id, $doc_id, $image_id );
        my $image_dir =
          get_image_dir( $holding_name, $folder_id, $doc_id, $image_id );
        my @rewrites;

        # create iiif info
        my %info_tmpl_var = ( image_uri => $image_uri, );
        foreach my $res ( keys %res_ext ) {
          my ( $width, $height ) = get_dim( $max_image_fn, $res );
          my $real_url =
            get_image_real_url( $holding_name, $folder_id, $doc_id, $page,
            $res );
          $info_tmpl_var{"width_$res"}  = $width;
          $info_tmpl_var{"height_$res"} = $height;

          # add rewrite
          push( @rewrites, { "full" => $real_url } ) if ( $res eq 'A' );
          push( @rewrites, { "$width,$height" => $real_url } );
          push( @rewrites, { "$width,"        => $real_url } );
        }
        $info_tmpl->param( \%info_tmpl_var );
        write_info( $image_dir, $info_tmpl );

        # make thumbnail
        make_thumbnail( $max_image_fn, $image_dir )
          unless -f "$image_dir/thumbnail.jpg";

        # htaccess file
        write_htaccess( $image_dir, \@rewrites );
      }
    }
  }
}

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

sub get_image_dir {
  my $holding_name = shift || die "param missing";
  my $folder_id    = shift || die "param missing";
  my $doc_id       = shift || die "param missing";
  my $image_id     = shift || die "param missing";

  my $image_dir =
    $iiif_root->child($holding_name)->child($folder_id)->child($doc_id)
    ->child($image_id);
  $image_dir->mkpath;
  return $image_dir;
}

sub get_image_uri {
  my $holding_name = shift || die "param missing";
  my $folder_id    = shift || die "param missing";
  my $doc_id       = shift || die "param missing";
  my $image_id     = shift || die "param missing";

  return "$pm20_root_uri${holding_name}/${folder_id}/${doc_id}/${image_id}";
}

sub get_image_real_url {
  my $holding_name = shift || die "param missing";
  my $folder_id    = shift || die "param missing";
  my $doc_id       = shift || die "param missing";
  my $page         = shift || die "param missing";
  my $res          = shift || die "param missing";

  my %imagedata = %{ $imagedata_ref->{$folder_id} };

  # create url according to dir structure
  my $url =
      $holding{$holding_name}{url_stub}{ $imagedata{root} }
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

sub write_info {
  my $image_dir = shift || die "param missing";
  my $info_tmpl = shift || die "param missing";

  my $json = $info_tmpl->output;

  my $info_file = $image_dir->child('info.json');
  $info_file->spew($json);
}

sub make_thumbnail {
  my $max_image_fn = shift || die "param missing";
  my $image_dir    = shift || die "param missing";

  # file is written
  my $t = new Image::Thumbnail(
    size       => "150",
    create     => 1,
    module     => 'Image::Magick',
    input      => "$max_image_fn",
    outputpath => "$image_dir/thumbnail.jpg",
  );
}

sub write_htaccess {
  my $image_dir    = shift || die "param missing";
  my $rewrites_ref = shift || die "param missing";

  my $fh = $image_dir->child('.htaccess')->openw;
  print $fh "RewriteEngine On\n";
  foreach my $rewrite_ref ( @{$rewrites_ref} ) {
    foreach my $from ( keys %{$rewrite_ref} ) {
      my $to = $rewrite_ref->{$from};
      print $fh "RewriteRule \"full/$from/0/default.jpg\" \"$to\" [R=303,L]\n";
    }
  }
  close($fh);
}
