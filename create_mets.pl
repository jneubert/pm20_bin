#!/bin/perl
# nbt, 31.1.2018

# traverses folder roots in order to create internal and external
# DFG-Viewer-suitable METS/MODS files per folder

# can be invoked either by
# - an extended folder id (e.g., pe/000012)
# - a collection id (e.g., pe)
# - 'ALL' (to (re-) create all collections)

use strict;
use warnings;

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

# use folder_root for persistent URI, and image_root for internal linking
# to image files (spares redirect for every file)
Readonly my $FOLDER_ROOT_URI => 'https://purl.org/pressemappe20/folder/';
Readonly my $IMAGE_ROOT_URI  => 'https://pm20.zbw.eu/folder/';
Readonly my $PDF_ROOT_URI    => 'http://zbw.eu/beta/pm20pdf/';
Readonly my $METS_ROOT       => path('../web.public/mets');
Readonly my $IMAGEDATA_ROOT  => path('../data/imagedata');
Readonly my $URLALIAS_FILE =>
  path("$ZBW::PM20x::Folder::FOLDERDATA_ROOT/urlalias.pm20mets.txt");

Readonly my %RES_EXT => (
  DEFAULT => '_B.JPG',
  MAX     => '_A.JPG',
  MIN     => '_C.JPG',
);

Readonly my @LANGUAGES => qw/ en de /;

# url_stub mappings according to ??_image.json
my %conf = (

  #  test => {
  #    prefix   => 'pe/',
  #    url_stub => {
  #      '/mnt/digidata/P' => 'http://webopac.hwwa.de/DigiPerson/P/',
  #    },
  #  },
  co => {
    type_label => {
      de => 'Firma',
      en => 'Company',
    },
    prefix   => 'co/',
    url_stub => {
      '/mnt/inst/F' => 'http://webopac.hwwa.de/DigiInst/F/',
      '/mnt/pers/A' => 'http://webopac.hwwa.de/DigiInst/A/',
    },
  },
  pe => {
    type_label => {
      de => 'Person',
      en => 'Person',
    },
    prefix   => 'pe/',
    url_stub => {
      '/pm20/folder/pe' => 'https://pm20.zbw.eu/folder/pe/',
    },
  },
  sh => {
    type_label => {
      de => 'Sach',
      en => 'Subject',
    },
    prefix   => 'sa/',
    url_stub => {
      '/pm20/folder/sh' => 'https://pm20.zbw.eu/folder/sh/',
    },
  },
  wa => {
    type_label => {
      de => 'Ware',
      en => 'Ware',
    },
    prefix   => 'wa/',
    url_stub => {
      '/mnt/ware/W' => 'http://webopac.hwwa.de/DigiWare/W/',
    },
  },
);

my ( $docdata_file, $imagedata_file, $docdata_ref, $imagedata_ref, );

my $tmpl = HTML::Template->new( filename => '../etc/html_tmpl/mets.tmpl' );

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

  # overwrite old alias file
  open( my $alias_fh, '>', $URLALIAS_FILE );

  foreach my $collection ( sort keys %conf ) {

    # $alias_fh is defined only when invoked from here
    mk_collection( $collection, $alias_fh );

  }
  close($alias_fh);
}

sub mk_collection {
  my $collection = shift or die "param missing";
  my $alias_fh   = shift;

  # load input files
  load_files($collection);

  foreach my $folder_nk ( sort keys %{$imagedata_ref} ) {
    mk_folder( $collection, $folder_nk, $alias_fh );
  }
}

sub mk_folder {
  my $collection = shift || die "param missing";
  my $folder_nk  = shift || die "param missing";
  my $alias_fh   = shift;

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
      my $label = $folder->get_folderlabel($lang);

      my %tmpl_var = (
        pref_label    => $label,
        uri           => "$FOLDER_ROOT_URI$conf{$collection}{prefix}$folder_nk",
        folder_nk     => $folder_nk,
        file_grp_loop => build_file_grp( $type, $conf{$collection}, $folder ),
        phys_loop     => build_phys_struct( $type, $folder ),
        log_loop      => build_log_struct( $type, $lang, $folder ),
        link_loop     => build_link( $type, $folder ),
        pdf_url       => $pdf_url,
      );
      $tmpl->param( \%tmpl_var );

      # write mets file for the folder
      write_mets( $type, $lang, $folder, $tmpl );

      # create url aliases for awstats
      if ($alias_fh) {
        print $alias_fh '/mets/' . $folder->get_folder_hashed_path()
          . "/$type.mets.$lang.xml\t$label\n";
      }
    }
  }
}

sub load_files {
  my $collection = shift || die "param missing";
  $imagedata_file = $IMAGEDATA_ROOT->child("${collection}_image.json");
  $imagedata_ref  = decode_json( $imagedata_file->slurp );
}

sub build_file_grp {
  my $type           = shift || die "param missing";
  my $collection_ref = shift || die "param missing";
  my $folder         = shift || die "param missing";

  my @file_grp_loop;

  foreach my $res ( sort keys %RES_EXT ) {
    my %entry = (
      use       => $res,
      file_loop => build_res_files( $type, $collection_ref, $folder, $res ),
    );
    push( @file_grp_loop, \%entry );
  }
  return \@file_grp_loop;
}

sub build_res_files {
  my $type           = shift || die "param missing";
  my $collection_ref = shift || die "param missing";
  my $folder         = shift || die "param missing";
  my $res            = shift || die "param missing";

  my $collection = $folder->{collection};
  my $folder_nk  = $folder->{folder_nk};
  my %imagedata  = %{ $imagedata_ref->{$folder_nk} };

  # create a flat list of files
  my @file_loop;
  foreach my $doc_id ( @{ $folder->get_doclist($type) } ) {
    my $page_no = 1;
    foreach my $page ( @{ $imagedata{docs}{$doc_id}{pg} } ) {

      # create url according to dir structure
      my $img_url;
      if ( $collection eq 'pe' or $collection eq 'sh' ) {
        ## switch to new mechanism
        $img_url =
            "$IMAGE_ROOT_URI$collection/"
          . $imagedata{docs}{$doc_id}{rp}
          . "/$page$RES_EXT{$res}";
      } else {
        $img_url =
            $collection_ref->{url_stub}{ $imagedata{root} }
          . $imagedata{docs}{$doc_id}{rp}
          . "/$page$RES_EXT{$res}";
      }

      my %entry = (
        img_id  => get_img_id( $folder_nk, $doc_id, $page_no, $res ),
        img_url => $img_url,
      );
      push( @file_loop, \%entry );
      $page_no++;
    }
  }

  return \@file_loop;
}

sub get_img_id {
  my $folder_nk = shift || die "param missing";
  my $doc_id    = shift || die "param missing";
  my $page_no   = shift || die "param missing";
  my $res       = shift || die "param missing";

  return "img_${folder_nk}_${doc_id}_${page_no}_" . lc($res);
}

sub build_phys_struct {
  my $type   = shift || die "param missing";
  my $folder = shift || die "param missing";

  my $folder_nk = $folder->{folder_nk};
  my %imagedata = %{ $imagedata_ref->{$folder_nk} };

  my @phys_loop;
  my $i = 1;
  foreach my $doc_id ( @{ $folder->get_doclist($type) } ) {
    my $page_no = 1;
    foreach my $page ( @{ $imagedata{docs}{$doc_id}{pg} } ) {
      my @size_loop;
      foreach my $res ( sort keys %RES_EXT ) {
        push( @size_loop,
          { img_id => get_img_id( $folder_nk, $doc_id, $page_no, $res ) } );
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
  my $type   = shift || die "param missing";
  my $lang   = shift || die "param missing";
  my $folder = shift || die "param missing";

  my @log_loop;
  foreach my $doc_id ( @{ $folder->get_doclist($type) } ) {
    my $label = $folder->get_doclabel( $lang, $doc_id );
    my %entry = (
      document_id => "doc$doc_id",
      label       => $label,
      type        => 'Document',
    );
    push( @log_loop, \%entry );
  }
  return \@log_loop;
}

sub build_link {
  my $type   = shift || die "param missing";
  my $folder = shift || die "param missing";

  my $folder_nk = $folder->{folder_nk};
  my %imagedata = %{ $imagedata_ref->{$folder_nk} };

  # duplicates logic from build_phys_struct()!
  my @link_loop;
  my $i = 1;
  foreach my $doc_id ( @{ $folder->get_doclist($type) } ) {
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
  my $type   = shift || die "param missing";
  my $lang   = shift || die "param missing";
  my $folder = shift || die "param missing";
  my $tmpl   = shift || die "param missing";

  my $hashed_path = $folder->get_folder_hashed_path();
  my $mets_dir    = $METS_ROOT->child($hashed_path);
  $mets_dir->mkpath;

  my $mets_file = $mets_dir->child("$type.mets.$lang.xml");
  $mets_file->spew_utf8( $tmpl->output() );
}

sub usage {
  print "Usage: $0 {folder-id}|{collection}|ALL\n";
  exit 1;
}

