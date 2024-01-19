# nbt, 2020-08-07

package ZBW::PM20x::Folder;

use strict;
use warnings;

use lib './lib/';
use utf8;

use Carp;
use Data::Dumper;
use HTML::Entities;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number reftype);
use ZBW::PM20x::Vocab;

Readonly my $FOLDER_URI_ROOT  => 'https://pm20.zbw.eu/folder/';
Readonly our $FOLDER_ROOT     => path('/pm20/folder');
Readonly our $FOLDERDATA_FILE => path('/pm20/data/rdf/pm20.extended.jsonld');
##Readonly our $FOLDERDATA_FILE =>
##  path('../data/rdf/pm20.extended.examples.jsonld');
Readonly our $DOCDATA_ROOT      => path('/pm20/data/docdata');
Readonly our $FILMDATA_ROOT     => path('/pm20/data/filmdata');
Readonly our @ACCESS_TYPES      => qw/ public intern /;
Readonly our $URI_STUB          => 'https://pm20.zbw.eu/folder';
Readonly our $DFGVIEW_URL_STUB  => 'https://pm20.zbw.eu/dfgview';
Readonly our $IIIFVIEW_URL_STUB => 'https://pm20.zbw.eu/iiifview/folder';

our ( %folderdata, %blank_node );

# global data structure (initialized lazily):
#
# {collection}
#   doclist
#     internal
#     pulic
#   docdata
#     {full docdata file}
#   filmsectiondata

my %data;
foreach my $collection (qw/ co pe sh wa /) {
  foreach my $entry (qw/ doclist docdata /) {
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

=item new_from_uri { $uri }

Return a new folder object from an folder URI.

=cut

sub new_from_uri {
  my $class = shift or croak('param missing');
  my $uri   = shift or croak('param missing');

  $uri =~ m!$FOLDER_URI_ROOT(co|pe|sh|wa)/(\d{6}(,\d{6})?)$!
    or croak("$uri is not a valid folder uri");
  my $collection = $1;
  my $folder_nk  = $2;

  my $folder = $class->new( $collection, $folder_nk );
  return $folder;
}

=back

=head1 Instance methods

=over 2

=item get_folder_uri

Return the URI for a folder

=cut

sub get_folder_uri {
  my $self = shift or croak('param missing');

  my $folder_uri = $FOLDER_URI_ROOT . $self->get_folder_id;
  return $folder_uri;
}

=item get_folder_id

Get folder id ({collection}/{folder_nk}).

=cut

sub get_folder_id {
  my $self = shift or croak('param missing');

  my $fid = $self->{collection} . '/' . $self->{folder_nk};
  return $fid;
}

=item get_folderlabel ( $lang, $with_signature )

Return a html-encoded, human-readable label for a folder, optionally with signature.

=cut

sub get_folderlabel {
  my $self           = shift or croak('param missing');
  my $lang           = shift or croak('param missing');
  my $with_signature = shift;

  if ($with_signature) {
    ##$label = "$subject_ref->{$self->{term_id2}}{notation} $label";
    carp("with_signature not yet defined");
  }

  my $collection = $self->{collection};
  my $folder_nk  = $self->{folder_nk};

  # lazy load - test with example value
  if ( not defined $folderdata{co} ) {
    _load_folderdata();
  }

  my $label;

  if ( $collection eq 'pe' or $collection eq 'co' ) {
    ## currently no distinction between English and German prefLabel
    $label = $folderdata{$collection}{$folder_nk}{prefLabel};
  } else {
    foreach
      my $label_ref ( @{ $folderdata{$collection}{$folder_nk}{prefLabel} } )
    {
      next unless $label_ref->{'@language'} eq $lang;
      $label = $label_ref->{'@value'};
    }
  }

  if ( not $label ) {
    warn "label missing for $collection/$folder_nk\n";
    $label = '';
  }

  # encode HTML entities
  $label = encode_entities( $label, '<>&"' );

  return $label;
}

=item get_relpath_to_folder ( $folder )

Get relative filesystem path to another folder.

=cut

sub get_relpath_to_folder {
  my $self    = shift or croak('param missing');
  my $folder2 = shift or croak('param missing');

  my $rel_path =
    $folder2->get_folder_hashed_path->relative( $self->get_folder_hashed_path );
  return $rel_path;
}

=item format_doc_counts ( $lang, {$total_only} )

Return a language-specific string with total and free document counts, undef if
none of them defined. If $total_only is set, return only first count.

=cut

sub format_doc_counts {
  my $self       = shift or croak('param missing');
  my $lang       = shift or croak('param missing');
  my $total_only = shift;

  my $folderdata_raw = $self->get_folderdata_raw;

  my $doc_counts = '';
  if ( exists $folderdata_raw->{totalDocCount} ) {
    $doc_counts .= $folderdata_raw->{totalDocCount}{'@value'};
    $doc_counts .= ( $lang eq 'en' ? ' documents' : ' Dokumente' );
  }
  if ( not $total_only ) {
    $doc_counts .= ' / ';
    if ( exists $folderdata_raw->{freeDocCount} ) {
      $doc_counts .= $folderdata_raw->{freeDocCount}{'@value'};
      $doc_counts .=
        ( $lang eq 'en' ? ' available on the web' : ' im Web zugänglich' );
    }
  }
  if ( $doc_counts ne '' ) {
    return $doc_counts;
  } else {
    return;
  }
}

=item get_film_img_counts ()

Return a string with film image counts for the first and second filming, undef
if none of them defined. (Currently, only for co)

=cut

sub get_film_img_counts {
  my $self = shift or croak('param missing');

  my $fid = $self->get_folder_id;

  return unless $fid =~ m/^co\//;

  # data has to be loaded, if not exists
  if ( not defined $data{co}{"film_img_count"} ) {
    _load_film_img_count_data();
  }

  my $img_counts = '';

  ##print Dumper $fid, $data{co}{film_img_count}{$fid};
  my ($cnt1, $cnt2);
  if ( $cnt1 = $data{co}{film_img_count}{$fid}{1} ) {
    $img_counts = $cnt1;
  }
  if ( $cnt2 = $data{co}{film_img_count}{$fid}{2} ) {
    if ( $cnt1 ) {
      $img_counts .= ' / ';
    }
    $img_counts .= $cnt2;
  }
  if ($img_counts) {
    return $img_counts;
  } else {
    return;
  }
}

=item get_wdlink ()

Get the URI of the exact matching Wikidata item. If more than one exists, issue
a warning and return the first.

=cut

sub get_wdlink {
  my $self = shift or croak('param missing');

  my $fid            = $self->get_folder_id;
  my $label          = $self->get_folderlabel('en');
  my $folderdata_raw = $self->get_folderdata_raw;

  my $wdlink;
  if ( $folderdata_raw->{exactMatch} ) {
    if ( scalar( $folderdata_raw->{exactMatch} ) gt 1 ) {
      warn "more than one wdlink for $fid $label\n";
    }
    $wdlink = $folderdata_raw->{exactMatch}[0]{'@id'};
  } else {
    warn "no wdlink for $fid $label\n";
  }
  return $wdlink;
}

=item get_modified

Get date of last modification.

=cut

sub get_modified {
  my $self = shift or croak('param missing');

  my $folderdata_raw = $self->get_folderdata_raw;
  my $modified;

  # pe and co have onw timestamps
  if ( $folderdata_raw->{modified} ) {
    $modified = $folderdata_raw->{modified};
  } else {

    # arbitrary timestamp (end of Sach migration)
    $modified = '2021-01-21';
  }
  return $modified;
}

=item get_folderdata_raw ()

Return a hash of raw data from JSONLD

=cut

sub get_folderdata_raw {
  my $self = shift or croak('param missing');

  # lazy load - test with example value
  if ( not defined $folderdata{co} ) {
    _load_folderdata();
  }

  my $data = $folderdata{ $self->{collection} }{ $self->{folder_nk} };
  return $data;
}

=item get_docdata ( $doc_id )

Return a hash with document data for a document of a folder

=cut

sub get_docdata {
  my $self   = shift or croak('param missing');
  my $doc_id = shift or croak('param missing');

  my $collection = $self->{collection};
  my $folder_nk  = $self->{folder_nk};

  return $data{$collection}{docdata}{$folder_nk}{info}{$doc_id}{con};
}

=item get_doclabel ( $lang, $doc_id )

Return a html-encoded, human-readable label for a document from consolidated
document info.

=cut

sub get_doclabel {
  my $self      = shift or croak('param missing');
  my $lang      = shift or croak('param missing');
  my $doc_id    = shift or croak('param missing');
  my $short_flg = shift;

  my $field_ref = $self->get_docdata($doc_id);

  my $label = '';
  if ( $field_ref->{title} ) {
    $label .= $field_ref->{title};
    if ( $field_ref->{author} ) {
      $label = "$field_ref->{author}: $label";
    }
  }
  if ( not $short_flg ) {
    if ( $field_ref->{pub} ) {
      my $src = $field_ref->{pub};

      # remove non-essential parts of the source description
      $src =~ s/(.*?) \(.*?\)(.*)/$1$2/g;
      $src =~ s/(.*?) \<.*?\>(.*)/$1$2/g;
      $src =~ s/, Nr\. \d+$//g;

      if ( $field_ref->{date} ) {
        $src = "$src, $field_ref->{date}";
      }
      if ($label) {
        $label = "$label ($src)";
      } else {
        $label = $src;
      }
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

=item get_dfgview_url ( $lang )

Return a URL for the DFG viewer, loading the folder METS file.

=cut

sub get_dfgview_url {
  my $self = shift or croak('param missing');
  my $lang = shift;

  # currenly, $lang is not used

  return "$DFGVIEW_URL_STUB/$self->{folder_id}";
}

=item get_iiifview_url ( $lang )

Return a URL for the IIIF viewer, loading the folder IIIF manifest file
(language selected here, public/intern via Apache).

=cut

sub get_iiifview_url {
  my $self = shift or croak('param missing');
  my $lang = shift;

  # currenly, $lang is not used

  return "$IIIFVIEW_URL_STUB/$self->{folder_id}";
}

=item get_document_hashed_path ( $doc_id )

Return a path fragment for a folder's document with intermediate (hashed)
directories for web access.

=cut

sub get_document_hashed_path {
  my $self   = shift or croak('param missing');
  my $doc_id = shift or croak('param missing');

  my $path = $self->get_folder_hashed_path->child($doc_id);

  return $path;
}

=item get_document_hashed_fspath ( $doc_id )

Return a path fragment for a folder's document with intermediate (hashed)
directories for file system access (with additional intermediate dir).

=cut

sub get_document_hashed_fspath {
  my $self   = shift or croak('param missing');
  my $doc_id = shift or croak('param missing');

  my $stub = $doc_id;
  $stub =~ s/^(\d\d\d)\d\d/$1xx/;
  my $path = $self->get_folder_hashed_path->child($stub)->child($doc_id);

  return $path;
}

=item get_document_locked_flag ( $doc_id )

Returns 1, if the document is locked (still under copyright), undef otherwise.

=cut

sub get_document_locked_flag {
  my $self   = shift or croak('param missing');
  my $doc_id = shift or croak('param missing');

  my $lock_status;

  # if .htaccess in document directory exists
  my $lockfile = $FOLDER_ROOT->child(
    $self->get_document_hashed_fspath($doc_id)->child('.htaccess') );
  if ( -f $lockfile ) {
    $lock_status = 1;
  }

  return $lock_status;
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

      # skip locked documents
      if ( $type eq 'public' ) {
        next if ( $self->get_document_locked_flag($doc_id) );
      }
      push( @{$doclist_ref}, $doc_id );
    }
  }

  return $doclist_ref;
}

=item get_filmsectionlist( $filming )

Return a sorted list of film sections for a folder (leaves out sections already
published as folders and not manually indexed) for either filming 1 or 2.

=cut

sub get_filmsectionlist {
  my $self    = shift or croak('param missing');
  my $filming = shift or croak('param missing');

  my @filmsectionlist = ();

  my $collection = $self->{collection};
  my $folder_nk  = $self->{folder_nk};

  # list has to be created, if not exists
  if ( not defined $data{$collection}{"filmsection${filming}data"} ) {
    _load_filmsectiondata( $collection, $filming );
  }
  my $filmsectiondata_ref = $data{$collection}{"filmsection${filming}data"};

  if ( $filmsectiondata_ref->{$folder_nk} ) {
    @filmsectionlist = @{ $filmsectiondata_ref->{$folder_nk} };
  }

  return \@filmsectionlist;
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

sub _load_filmsectiondata {
  my $collection = shift or croak('param missing');
  my $filming    = shift or croak('param missing');

  my %filmdata;

  # TODO currently reads zotero data -
  # to be replaced by getting more complete data from Wikidata
  my $provenance       = 'h';                                  # currently fixed
  my $subset           = "${provenance}${filming}_$collection";
  my $filmsection_file = $FILMDATA_ROOT->child("zotero.$subset.json");
  my $filmsection_ref  = decode_json( $filmsection_file->slurp );

  foreach my $film ( sort keys %{$filmsection_ref} ) {
    foreach my $section_name ( sort keys %{ $filmsection_ref->{$film}{item} } )
    {
      my $section_ref = $filmsection_ref->{$film}{item}{$section_name};
      my $folder_nk;
      if ( $section_ref->{pm20Id} ) {
        if ( $section_ref->{pm20Id} =~ m;^(co|pe|sh|wa)/(\d{6}(,\d{6})?)$; ) {
          $folder_nk = $2;
          push( @{ $filmdata{$folder_nk} }, $section_ref );
        } else {
          croak "Illegal $section_ref->{pm20Id} in $section_name\n";
        }
      }
    }
  }
  $data{$collection}{"filmsection${filming}data"} = \%filmdata;

  # debug?
  foreach my $folder ( keys %filmdata ) {
    ##print "$folder\n" if scalar(@{$filmdata{$folder}}) gt 2;
  }
}

# load complete folderdata (from jsonld)

sub _load_folderdata {

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
}

sub _load_film_img_count_data {
  foreach my $filming (qw/ 1 2 /) {
    my %filmdata = %{
      decode_json(
        $FILMDATA_ROOT->child("zotero.h${filming}_co.by_company_id.json")
          ->slurp
      )
    };
    foreach my $folder_id ( keys %filmdata ) {
      if ( my $total = $filmdata{$folder_id}{total_number_of_images} ) {
        $data{co}{film_img_count}{$folder_id}{$filming} = $total;
      }
    }
  }
}

1;

