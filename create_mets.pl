#!/bin/perl
# nbt, 31.1.2018

# traverses image share and  folder roots

use strict;
use warnings;

use Data::Dumper;
use Encode;
use HTML::Entities;
use HTML::Template;
use JSON;
use Path::Tiny;

$Data::Dumper::Sortkeys = 1;

my $folder_root_uri = 'http://purl.org/pressemappe20/folder/';
my $pdf_root_uri    = 'http://zbw.eu/beta/pm20pdf/';
my $mets_root       = path('../var/mets/');
my $imagedata_root  = path('../var/imagedata');
my $docdata_root    = path('../var/docdata');
my $folderdata_root = path('../var/folderdata');
my $urlalias_file   = path("$folderdata_root/urlalias.pm20mets.txt");

my %res_ext = (
  DEFAULT => '_B.JPG',
  MAX     => '_A.JPG',
  MIN     => '_C.JPG',
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

my $tmpl = HTML::Template->new( filename => '../etc/html_tmpl/mets.tmpl' );

my (
  $docdata_file, $imagedata_file, $folderdata_file,
  $docdata_ref,  $imagedata_ref,  $folderdata_ref
);

# remove old alias file
open( my $url_fh, '>', $urlalias_file );

foreach my $holding_name ( sort keys %holding ) {

  # load input files
  $docdata_file    = $docdata_root->child("${holding_name}_docdata.json");
  $docdata_ref     = decode_json( $docdata_file->slurp );
  $imagedata_file  = $imagedata_root->child("${holding_name}_image.json");
  $imagedata_ref   = decode_json( $imagedata_file->slurp );
  $folderdata_file = $folderdata_root->child("${holding_name}_label.json");
  $folderdata_ref  = decode_json( $folderdata_file->slurp );

  foreach my $folder_id ( sort keys %{$docdata_ref} ) {

    # skip if none of the folder's articles are free
    next unless exists $docdata_ref->{$folder_id}{free};

    my $label =
      get_folderlabel( $folder_id, $holding{$holding_name}{type_label} );
    my $pdf_url =
        $pdf_root_uri
      . "$holding_name/"
      . get_folder_relative_path($folder_id)
      . "/${folder_id}.pdf";

    my %tmpl_var = (
      pref_label => $label,
      uri        => "$folder_root_uri$holding{$holding_name}{prefix}$folder_id",
      folder_id  => $folder_id,
      file_grp_loop => build_file_grp( $holding{$holding_name}, $folder_id ),
      phys_loop     => build_phys_struct($folder_id),
      log_loop      => build_log_struct($folder_id),
      link_loop     => build_link($folder_id),
      pdf_url       => $pdf_url,
    );
    $tmpl->param( \%tmpl_var );

    # write mets file for the folder
    write_mets( $holding_name, $folder_id, $tmpl );

    # create url aliases for awstats
    print $url_fh "/beta/pm20mets/$holding_name/"
      . get_folder_relative_path($folder_id)
      . "/${folder_id}.xml\t$label\n";
  }
}

close($url_fh);

####################

sub build_file_grp {
  my $holding_ref = shift || die "param missing";
  my $folder_id   = shift || die "param missing";

  my @file_grp_loop;

  foreach my $res ( sort keys %res_ext ) {
    my %entry = (
      use       => $res,
      file_loop => build_res_files( $holding_ref, $folder_id, $res ),
    );
    push( @file_grp_loop, \%entry );
  }
  return \@file_grp_loop;
}

sub build_res_files {
  my $holding_ref = shift || die "param missing";
  my $folder_id   = shift || die "param missing";
  my $res         = shift || die "param missing";

  my %imagedata = %{ $imagedata_ref->{$folder_id} };
  my %docdata   = %{ $docdata_ref->{$folder_id} };

  # create a flat list of files
  my @file_loop;
  foreach my $doc_id ( sort keys $docdata{free} ) {
    my $page_no = 1;
    foreach my $page ( @{ $imagedata{docs}{$doc_id}{pg} } ) {

      ( my $folder_hash = $folder_id ) =~ s/^(\d\d\d\d)../$1xx/;
      ( my $doc_hash    = $doc_id ) =~ s/^(\d\d\d)../$1xx/;

      # create url according to dir structure
      my $img_url =
          $holding_ref->{url_stub}{ $imagedata{root} }
        . $imagedata{docs}{$doc_id}{rp}
        . "/$page$res_ext{$res}";

      my %entry = (
        img_id  => get_img_id( $folder_id, $doc_id, $page_no, $res ),
        img_url => $img_url,
      );
      push( @file_loop, \%entry );
      $page_no++;
    }
  }
  return \@file_loop;
}

sub get_img_id {
  my $folder_id = shift || die "param missing";
  my $doc_id    = shift || die "param missing";
  my $page_no   = shift || die "param missing";
  my $res       = shift || die "param missing";

  return "img_${folder_id}_${doc_id}_${page_no}_" . lc($res);
}

sub build_phys_struct {
  my $folder_id = shift || die "param missing";

  my %imagedata = %{ $imagedata_ref->{$folder_id} };
  my %docdata   = %{ $docdata_ref->{$folder_id} };

  my @phys_loop;
  my $i = 1;
  foreach my $doc_id ( sort keys $docdata{free} ) {
    my $page_no = 1;
    foreach my $page ( @{ $imagedata{docs}{$doc_id}{pg} } ) {
      my @size_loop;
      foreach my $res ( sort keys %res_ext ) {
        push( @size_loop,
          { img_id => get_img_id( $folder_id, $doc_id, $page_no, $res ) } );
      }
      my %entry = (
        i        => $i,
        phys_id  => "phys_$i",
        page_uri => 'http://dummy.org',

        # TODO size_loop -> res_loop
        size_loop => \@size_loop,
      );
      push( @phys_loop, \%entry );
      $page_no++;
      $i++;
    }
  }
  return \@phys_loop;
}

sub build_log_struct {
  my $folder_id = shift || die "param missing";

  my %docdata = %{ $docdata_ref->{$folder_id} };

  my @log_loop;
  foreach my $doc_id ( sort keys $docdata{free} ) {
    my %entry = (
      document_id => "doc$doc_id",
      label       => get_doclabel( $doc_id, $docdata{info}{$doc_id} ),
      type        => 'Document',
    );
    push( @log_loop, \%entry );
  }
  return \@log_loop;
}

sub build_link {
  my $folder_id = shift || die "param missing";

  my %imagedata = %{ $imagedata_ref->{$folder_id} };
  my %docdata   = %{ $docdata_ref->{$folder_id} };

  # duplicates logic from build_phys_struct()!
  my @link_loop;
  my $i = 1;
  foreach my $doc_id ( sort keys $docdata{free} ) {
    foreach my $page ( @{ $imagedata{docs}{$doc_id}{pg} } ) {
      my %entry = (
        document_id => "doc$doc_id",
        phys_id     => "phys_$i",
      );
      push( @link_loop, \%entry );
      $i++;
    }
  }
  return \@link_loop;
}

sub write_mets {
  my $holding_name = shift || die "param missing";
  my $folder_id    = shift || die "param missing";
  my $tmpl         = shift || die "param missing";

  my %docdata = %{ $docdata_ref->{$folder_id} };

  my $relative_path = get_folder_relative_path($folder_id);

  my $mets_dir = $mets_root->child($holding_name)->child($relative_path);
  $mets_dir->mkpath;
  my $mets_file = $mets_dir->child("$folder_id\.xml");
  $mets_file->spew( $tmpl->output() );
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

