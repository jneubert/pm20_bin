#!/bin/perl
# nbt, 31.1.2018

# traverses folder roots in order to create internal and external
# DFG-Viewer-suitable METS/MODS files per folder

# can be invoked either by
# - a folder id (e.g., pe/000012)
# - a collection id (e.g., pe)
# - 'ALL' (to (re-) create all collections)

# TODO
# - extend to english
# - extend to internal and external

use strict;
use warnings;

use Data::Dumper;
use Encode;
use HTML::Entities;
use HTML::Template;
use JSON;
use Path::Tiny;
use Readonly;

$Data::Dumper::Sortkeys = 1;

Readonly my $FOLDER_ROOT_URI => 'http://purl.org/pressemappe20/folder/';
Readonly my $PDF_ROOT_URI    => 'http://zbw.eu/beta/pm20pdf/';
Readonly my $FOLDER_ROOT     => path('/disc1/pm20/folder');
Readonly my $METS_ROOT       => path('../web.public/mets/');
Readonly my $IMAGEDATA_ROOT  => path('../data/imagedata');
Readonly my $DOCDATA_ROOT    => path('../data/docdata');
Readonly my $FOLDERDATA_ROOT => path('../data/folderdata');
Readonly my $URLALIAS_FILE   => path("$FOLDERDATA_ROOT/urlalias.pm20mets.txt");

Readonly my %RES_EXT => (
  DEFAULT => '_B.JPG',
  MAX     => '_A.JPG',
  MIN     => '_C.JPG',
);

# url_stub mappings according to ??_image.json
my %conf = (

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
      '/mnt/pers/A' => 'http://webopac.hwwa.de/DigiInst/A/',
    },
  },
  pe => {
    type_label => 'Person',
    prefix     => 'pe/',
    url_stub   => {
      '/mnt/digidata/P' => 'https://pm20.zbw.eu/folder/pe/',
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

# check arguments
if ( scalar(@ARGV) == 1 ) {
  if ( $ARGV[0] =~ m:^(co|pe|wa|sh)$: ) {
    my $collection = $1;
    mk_collection($collection);
  } elsif ( $ARGV[0] =~ m:^((co|pe)/\d{6}|(sh|wa)/\d{6},\d{6})$: ) {
    my $folder_id = $1;

    # TODO check existence of folder directory
    # TODO (proc empty)
    mk_folder($folder_id);
  } elsif ( $ARGV[0] eq 'ALL' ) {
    mk_all();
  } else {
    &usage;
  }
} else {
  &usage;
}

my (
  $docdata_file, $imagedata_file, $folderdata_file,
  $docdata_ref,  $imagedata_ref,  $folderdata_ref
);

####################

sub mk_all {

  # remove old alias file
  open( my $url_fh, '>', $URLALIAS_FILE );

  foreach my $collection ( sort keys %conf ) {

    mk_collection( $collection, $url_fh );

  }
  close($url_fh);
}

sub mk_collection {
  my $collection = shift or die "param missing";
  my $url_fh     = shift;

  # load input files
  $docdata_file    = $DOCDATA_ROOT->child("${collection}_docdata.json");
  $docdata_ref     = decode_json( $docdata_file->slurp );
  $imagedata_file  = $IMAGEDATA_ROOT->child("${collection}_image.json");
  $imagedata_ref   = decode_json( $imagedata_file->slurp );
  $folderdata_file = $FOLDERDATA_ROOT->child("${collection}_label.json");
  $folderdata_ref  = decode_json( $folderdata_file->slurp );

  foreach my $folder_id ( sort keys %{$docdata_ref} ) {

    # skip if none of the folder's articles are free
    next unless exists $docdata_ref->{$folder_id}{free};

    my $label =
      get_folderlabel( $folder_id, $conf{$collection}{type_label} );
    my $pdf_url =
        $PDF_ROOT_URI
      . "$collection/"
      . get_folder_relative_path($folder_id)
      . "/${folder_id}.pdf";

    my %tmpl_var = (
      pref_label    => $label,
      uri           => "$FOLDER_ROOT_URI$conf{$collection}{prefix}$folder_id",
      folder_id     => $folder_id,
      file_grp_loop => build_file_grp( $conf{$collection}, $folder_id ),
      phys_loop     => build_phys_struct($folder_id),
      log_loop      => build_log_struct($folder_id),
      link_loop     => build_link($folder_id),
      pdf_url       => $pdf_url,
    );
    $tmpl->param( \%tmpl_var );

    # write mets file for the folder
    write_mets( $collection, $folder_id, $tmpl );

    # create url aliases for awstats
    if ($url_fh) {
      print $url_fh "/beta/pm20mets/$collection/"
        . get_folder_relative_path($folder_id)
        . "/${folder_id}.xml\t$label\n";
    }
  }
}

sub mk_folder {
}

####################

sub build_file_grp {
  my $collection_ref = shift || die "param missing";
  my $folder_id      = shift || die "param missing";

  my @file_grp_loop;

  foreach my $res ( sort keys %RES_EXT ) {
    my %entry = (
      use       => $res,
      file_loop => build_res_files( $collection_ref, $folder_id, $res ),
    );
    push( @file_grp_loop, \%entry );
  }
  return \@file_grp_loop;
}

sub build_res_files {
  my $collection_ref = shift || die "param missing";
  my $folder_id      = shift || die "param missing";
  my $res            = shift || die "param missing";

  my %imagedata = %{ $imagedata_ref->{$folder_id} };
  my %docdata   = %{ $docdata_ref->{$folder_id} };

  # create a flat list of files
  my @file_loop;
  foreach my $doc_id ( sort keys %{ $docdata{free} } ) {
    my $page_no = 1;
    foreach my $page ( @{ $imagedata{docs}{$doc_id}{pg} } ) {

      ( my $folder_hash = $folder_id ) =~ s/^(\d\d\d\d)../$1xx/;
      ( my $doc_hash    = $doc_id ) =~ s/^(\d\d\d)../$1xx/;

      # create url according to dir structure
      my $img_url =
          $collection_ref->{url_stub}{ $imagedata{root} }
        . $imagedata{docs}{$doc_id}{rp}
        . "/$page$RES_EXT{$res}";

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
  foreach my $doc_id ( sort keys %{ $docdata{free} } ) {
    my $page_no = 1;
    foreach my $page ( @{ $imagedata{docs}{$doc_id}{pg} } ) {
      my @size_loop;
      foreach my $res ( sort keys %RES_EXT ) {
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
  foreach my $doc_id ( sort keys %{ $docdata{free} } ) {
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
  foreach my $doc_id ( sort keys %{ $docdata{free} } ) {
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
  my $collection = shift || die "param missing";
  my $folder_id  = shift || die "param missing";
  my $tmpl       = shift || die "param missing";

  my %docdata = %{ $docdata_ref->{$folder_id} };

  # TODO change logic for relative path - not save for sh/wa!!
  my $relative_path = get_folder_relative_path($folder_id);

  my $mets_dir =
    $METS_ROOT->child($collection)->child($relative_path)->child($folder_id);
  $mets_dir->mkpath;
  my $mets_file = $mets_dir->child("public.mets.de.xml");
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
    if ( $field_ref->{type} ) {
      if ( $field_ref->{type} =~ m/::.+/ ) {
        $label = ( split( /::/, $field_ref->{type} ) )[1] . ' ' . $doc_id;
      } else {
        $label = $field_ref->{type} . ' ' . $doc_id;
      }
    } else {
      $label = "Dok $doc_id";
    }
  }
  if ( $field_ref->{pages} ) {
    if ( $field_ref->{pages} > 1 ) {
      $label .= " ($field_ref->{pages} S.)";
    }
  } else {
    warn "Missing pages for $doc_id: ", Dumper $field_ref;
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

sub usage {
  print "Usage: $0 {folder-id}|{collection}|ALL\n";
  exit 1;
}

