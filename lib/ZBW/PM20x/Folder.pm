# nbt, 2020-08-07

package ZBW::PM20x::Folder;

use strict;
use warnings;

use lib './lib/';

use HTML::Entities;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number reftype);
use ZBW::PM20x::Vocab;

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

=over 1

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
  };
  bless $self, $class;

  return $self;
}

=head1 Instance methods

=over 1

=item get_folderlabel ( $lang, $with_signature )

Return a html-encoded, human-readable label for a folder, optionally with signature.

=cut

# TODO use Vocab::get_termlabel()

sub get_folderlabel {
  my $self = shift or croak('param missing');
  my $lang = shift or croak('param missing');
  my $with_signature = shift;

  my ($geo_ref)     = ZBW::PM20x::Vocab->new('ag');
  my ($subject_ref) = ZBW::PM20x::Vocab->new('je');

  if ( $self->{collection} eq 'sh' ) {

    my $geo     = $geo_ref->{ $self->{term_id1} }{prefLabel}{$lang};
    my $subject = $subject_ref->{ $self->{term_id2} }{prefLabel}{$lang};

    my $label = "$geo : $subject";

    if ($with_signature) {
      $label = "$subject_ref->{$self->{term_id2}}{notation} $label";
    }

    # encode HTML entities
    $label = encode_entities( $label, '<>&"' );

    # mark unchecked translated labels
    if ( $lang eq 'en' and $subject =~ m/^\. / ) {
      $label =~ s/(.*?) : \. (.*)/$1 : $2 \*/;
    }
    return $label;
  }
}

=item get_doclabel ( $lang, $doc_id, $field_ref )

Return a html-encoded, human-readable label for a document from consolidated document info.

=cut

sub get_doclabel {
  my $lang      = shift or croak('param missing');
  my $doc_id    = shift or croak('param missing');
  my $field_ref = shift or croak('param missing');

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
        print "unknown $type\n";
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
  my $term_id1 = $self->{term_id1};
  my $term_id2 = $self->{term_id2};
  my $path = path($collection);
  if ( $collection eq 'pe' or $collection eq 'co' ) {
    my $stub = substr( $term_id1, 0, 4 ) . 'xx';
    $path = $path->child($stub)->child( $term_id1 );
  } elsif ( $collection eq 'sh' or $collection eq 'wa' ) {
    my $stub1 = substr( $term_id1, 0, 4 ) . 'xx';
    my $stub2 = substr( $term_id2, 0, 4 ) . 'xx';
    $path = $path->child($stub1)->child( $term_id1 )->child($stub2)
      ->child( $term_id2 );
  } else {
    croak("wrong collection: $collection");
  }

  return $path;
}

1;

