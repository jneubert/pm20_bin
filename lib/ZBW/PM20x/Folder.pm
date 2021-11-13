# nbt, 2020-08-07

package ZBW::PM20x::Folder;

use strict;
use warnings;

use lib './lib/';

use Carp;
use Data::Dumper;
use HTML::Entities;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number reftype);
use ZBW::PM20x::Vocab;

Readonly our $FOLDER_ROOT     => path('/pm20/folder');
Readonly our $FOLDERDATA_ROOT => path('../data/folderdata');
##Readonly our $FOLDERDATA_FILE  => path('../data/rdf/pm20.extended.jsonld');
Readonly our $FOLDERDATA_FILE =>
  path('../data/rdf/pm20.extended.examples.jsonld');
Readonly our $DOCDATA_ROOT     => path('../data/docdata');
Readonly our @ACCESS_TYPES     => qw/ public intern /;
Readonly our $URI_STUB         => 'http://purl.org/pressemappe20/folder';
Readonly our $DFGVIEW_URL_STUB => 'https://pm20.zbw.eu/dfgview';

our ( %folderdata, %blank_node );

# global data structure (initialized lazily):
#
# {collection}
#   label       # for pe and co
#   vocab       # for sh and wa
#     {vocab}   # ag/je or ag/ip
#   doclist
#     internal
#     pulic
#   docdata
#     {full docdata file}

my %data;
foreach my $collection (qw/ co pe sh wa /) {
  foreach my $entry (qw/ label doclist docdata /) {
    $data{$collection}{$entry} = ();
  }
  foreach my $type (@ACCESS_TYPES) {
    $data{$collection}{doclist}{$type} = ();
  }
}

Readonly my $RDF_ROOT => path('../data/rdf');

Readonly my %DOCTYPE => (
  A => {
    de => 'Aufsatz',
    en => 'Article',
  },
  F => {
    de => 'Festschrift',
    en => 'Festschrift',
  },
  G => {
    de => 'Geschäftsbericht',
    en => 'Annual report',
  },
  H => {
    de => 'Hinweis',
    en => 'Hint',
  },
  M => {
    de => 'Monographie',
    en => 'Monograph',
  },
  P => {
    de => 'Presseartikel',
    en => 'Press article',
  },
  S => {
    de => 'Amtsblatt',
    en => 'Gazette',
  },
  T => {
    de => 'Typoskript',
    en => 'Typoscript',
  },
  U => {
    de => 'Statut',
    en => 'Statute',
  },
  Z => {
    de => 'Sonstiges',
    en => 'Other',
  },
);

=head1 NAME

ZBW::PM20x::Folder - Functions for PM20 folders

=head1 SYNOPSIS

  use ZBW::PM20x::Folder;
  my $folder = ZBW::PM20x::Folder->new( $collection, $folder_nk );
  my $label = $folder->get_folderlabel( $lang );

=head1 DESCRIPTION

  Identifiers:

    term_id     := \d{6}  # with leading zeros
    collection  := (co|pe|sh|wa)
    folder_nk   := <term_id> | <term_id>,<term_id>
    folder_id   := <collection>/<folder_nk>


=head1 Class methods

=over 2

=item new ( $collection, $folder_nk )

Return a new folder object.

=cut

sub new {
  my $class      = shift or croak('param missing');
  my $collection = shift or croak('param missing');
  my $folder_nk  = shift or croak('param missing');

  $folder_nk =~ m/^(\d{6})(,(\d{6}))?/
    or croak("irregular folder_id: $folder_nk for collection: $collection");
  my $term_id1 = $1;
  my $term_id2 = $3;

  my $self = {
    collection => $collection,
    folder_nk  => $folder_nk,
    folder_id  => "$collection/$folder_nk",
    term_id1   => $term_id1,
    term_id2   => $term_id2,
    folder_uri => "$URI_STUB/$collection/$folder_nk",
  };
  bless $self, $class;

  return $self;
}

=back

=head1 Instance methods

=over 2

=item get_folderlabel ( $lang, $with_signature )

Return a html-encoded, human-readable label for a folder, optionally with signature.

=cut

sub get_folderlabel {
  my $self           = shift or croak('param missing');
  my $lang           = shift or croak('param missing');
  my $with_signature = shift;

  my $collection = $self->{collection};

  my $label;
  if ( $collection eq 'pe' or $collection eq 'co' ) {
    if ( not defined $data{$collection}{label} ) {
      _load_folderdata($collection);
    }
    $label = $data{$collection}{label}{ $self->{folder_nk} };
  } elsif ( $collection eq 'sh' ) {
    if ( not defined $data{$collection}{vocab} ) {
      _load_vocabdata($collection);
    }
    my $geo = $data{$collection}{vocab}{ag}->label( $lang, $self->{term_id1} );
    my $subject =
      $data{$collection}{vocab}{je}->label( $lang, $self->{term_id2} );

    $label = "$geo : $subject";

    if ($with_signature) {
      ##$label = "$subject_ref->{$self->{term_id2}}{notation} $label";
      carp("with_signature not yet defined");
    }

    # encode HTML entities
    $label = encode_entities( $label, '<>&"' );

  } elsif ( $collection eq 'wa' ) {
    if ( not defined $data{$collection}{vocab} ) {
      _load_vocabdata($collection);
    }
    my $ware = $data{$collection}{vocab}{ip}->label( $lang, $self->{term_id1} )
      || $data{$collection}{vocab}{ip}->label( 'de', $self->{term_id1} );

    my $geo = $data{$collection}{vocab}{ag}->label( $lang, $self->{term_id2} );

    $label = "$ware : $geo";
    if ($with_signature) {
      carp("with_signature not yet defined");
    }

    # encode HTML entities
    $label = encode_entities( $label, '<>&"' );
  }

  return $label;
}

=item get_docdata ()

Return a hash with document data for a folder (TODO more specifc methods)

=cut

sub get_docdata {
  my $self = shift or croak('param missing');

  my $collection = $self->{collection};
  my $folder_nk  = $self->{folder_nk};

  return $data{$collection}{docdata}{$folder_nk};
}

=item get_doclabel ( $lang, $doc_id )

Return a html-encoded, human-readable label for a document from consolidated
document info.

=cut

sub get_doclabel {
  my $self   = shift or croak('param missing');
  my $lang   = shift or croak('param missing');
  my $doc_id = shift or croak('param missing');

  my $docdata_ref = $self->get_docdata();
  my $field_ref   = $docdata_ref->{info}{$doc_id}{con};

  my $label = '';
  if ( $field_ref->{title} ) {
    if ( $field_ref->{author} ) {
      $label = "$field_ref->{author}: $label";
    } else {
      $label = $field_ref->{title};
    }
  }
  if ( $field_ref->{pub} ) {
    my $src = $field_ref->{pub};
    if ( $field_ref->{date} ) {
      $src = "$src, $field_ref->{date}";
    }
    if ($label) {
      $label = "$label ($src)";
    } else {
      $label = $src;
    }
  }

  # if necessary, set generic label
  if ( not $label ) {

    # ... with or without type
    my $type = $field_ref->{type};
    if ($type) {
      if ( $DOCTYPE{$type} ) {
        $label = "$DOCTYPE{$type}{$lang} $doc_id";
      } else {
        warn "unknown $type\n";
      }
    } else {
      $label = ( $lang eq 'en' ? 'Doc ' : 'Dok ' ) . $doc_id;
    }
  }

  # add number of pages
  if ( $field_ref->{pages} ) {
    if ( $field_ref->{pages} > 1 ) {
      my $p = $lang eq 'en' ? 'p.' : 'S.';
      $label .= " ($field_ref->{pages} $p)";
    }
  } else {
    carp( "Missing pages for $doc_id: ", Dumper $field_ref );
  }

  # encode HTML entities
  $label = encode_entities( $label, '<>&"' );

  return $label;
}

=item get_folder_hashed_path ()

Return a path fragment for a folder with intermediate (hashed) directories.

=cut

sub get_folder_hashed_path {
  my $self = shift or croak('param missing');

  my $collection = $self->{collection};
  my $term_id1   = $self->{term_id1};
  my $term_id2   = $self->{term_id2};
  my $path       = path($collection);
  if ( $collection eq 'pe' or $collection eq 'co' ) {
    my $stub = substr( $term_id1, 0, 4 ) . 'xx';
    $path = $path->child($stub)->child($term_id1);
  } elsif ( $collection eq 'sh' or $collection eq 'wa' ) {
    my $stub1 = substr( $term_id1, 0, 4 ) . 'xx';
    my $stub2 = substr( $term_id2, 0, 4 ) . 'xx';
    $path =
      $path->child($stub1)->child($term_id1)->child($stub2)->child($term_id2);
  } else {
    croak("wrong collection: $collection");
  }

  return $path;
}

=item get_dfgview_url ()

Return a URL for the DFG viewer, loading the folder METS file.

=cut

sub get_dfgview_url {
  my $self = shift or croak('param missing');
  my $lang = shift;

  # currenly, $lang is not used

  return "$DFGVIEW_URL_STUB/$self->{folder_id}";
}

=item get_document_hashed_path ()

Return a path fragment for a folder's document with intermediate (hashed) directories.

=cut

sub get_document_hashed_path {
  my $self   = shift or croak('param missing');
  my $doc_id = shift or croak('param missing');

  my $stub = substr( $doc_id, 0, 3 ) . 'xx';
  my $path = $self->get_folder_hashed_path->child($stub)->child($doc_id);

  return $path;
}

=item get_doclist( $type )

Return a reference to a list of sorted document ids for the folder, either of
all documents (type 'intern') or only of free documents (type 'public').

=cut

sub get_doclist {
  my $self = shift or croak('param missing');
  my $type = shift or croak('param missing');

  my $collection  = $self->{collection};
  my $folder_nk   = $self->{folder_nk};
  my $doclist_ref = $data{$collection}{doclist}{$type};

  if ( not defined $doclist_ref ) {

    # list has to be created
    if ( not defined $data{$collection}{docdata} ) {
      _load_docdata($collection);
    }
    my @tmplist = sort keys %{ $data{$collection}{docdata}{$folder_nk}{info} };
    foreach my $doc_id (@tmplist) {

      # skip if .htaccess in document directory exists
      if ( $type eq 'public' ) {
        my $lockfile = $FOLDER_ROOT->child(
          $self->get_document_hashed_path($doc_id)->child('.htaccess') );
        next if -f $lockfile;
      }
      push( @{$doclist_ref}, $doc_id );
    }
  }

  return $doclist_ref;
}

=back

=cut

# Internal procedures

sub _load_docdata {
  my $collection = shift or croak('param missing');

  my $docdata_file = $DOCDATA_ROOT->child("${collection}_docdata.json");
  my $docdata_ref  = decode_json( $docdata_file->slurp );
  $data{$collection}{docdata} = $docdata_ref;
}

# load old folderdata (only labels)

sub _load_folderdata {
  my $collection = shift or croak('param missing');

  if ( $collection eq 'co' or $collection eq 'pe' ) {
    my $folderdata_file = $FOLDERDATA_ROOT->child("${collection}_label.json");
    my $folderdata_ref  = decode_json( $folderdata_file->slurp );
    $data{$collection}{label} = $folderdata_ref;
  } else {
    confess("undefined collection: $collection");
  }
  print Dumper \%data;
}

# load complete folderdata (from jsonld)

sub _load_folderdata1 {

  my @folders =
    @{ decode_json( $FOLDERDATA_FILE->slurp )->{'@graph'} };
  foreach my $folder_ref (@folders) {
    my $id_value = $folder_ref->{'@id'};
    my $folder_key;

    # should be folder URL or blank node
    if ( $id_value =~ m/^http/ ) {
      my @parts      = split( /\//, $id_value );
      my $folder_nk  = $parts[-1];
      my $collection = $parts[-2];

      $folderdata{$collection}{$folder_nk} = $folder_ref;
    } elsif ( $id_value =~ m/^_:b/ ) {
      $blank_node{$id_value} = $folder_ref;
    } else {
      confess("strange folder \@id value: $id_value");
    }
  }
  print Dumper \%folderdata, \%blank_node;

  #$data{$collection}{label} = $folderdata_ref;

}

sub _load_vocabdata {
  my $collection = shift or croak('param missing');

  if ( $collection eq 'sh' ) {
    $data{$collection}{vocab}{ag} = ZBW::PM20x::Vocab->new('ag');
    $data{$collection}{vocab}{je} = ZBW::PM20x::Vocab->new('je');
  } elsif ( $collection eq 'wa' ) {
    $data{$collection}{vocab}{ag} = ZBW::PM20x::Vocab->new('ag');
    $data{$collection}{vocab}{ip} = ZBW::PM20x::Vocab->new('ip');
  } else {
    confess("undefined collection: $collection");
  }
}

1;

