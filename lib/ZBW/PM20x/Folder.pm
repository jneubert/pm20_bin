# nbt, 2020-08-07

package ZBW::PM20x::Folder;

use strict;
use warnings;

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
	my $label = get_folderlabel( $lang, $folder_id );

=head1 DESCRIPTION



=cut

=item get_folderlabel ( $lang, $folder_id, $with_signature )

Return a html-encoded, human-readable label for a folder, optionally with signature.

=cut

sub get_folderlabel {
  my $lang       = shift or die "param missing";
  my $collection = shift or die "param missing";
  my $folder_id  = shift or die "param missing";
  my $with_signature = shift;

  my ($geo_ref)     = ZBW::PM20x::Vocab::get_vocab('ag');
  my ($subject_ref) = ZBW::PM20x::Vocab::get_vocab('je');

  $folder_id =~ m/(\d{6})(,(\d{6}))?/
    or die "irregular folder_id: $folder_id for collection: $collection\n";
  my $id1 = $1;
  my $id2 = $3;

  if ( $collection eq 'sh' ) {

    my $geo     = $geo_ref->{$id1}{prefLabel}{$lang};
    my $subject = $subject_ref->{$id2}{prefLabel}{$lang};

    my $label = "$geo : $subject";

    if ($with_signature) {
      $label = "$subject_ref->{$id2}{notation} $label";
    }

    # encode HTML entities
    $label = encode_entities( $label, '<>&"' );

    # mark unchecked translated labels
    if ( $lang eq 'en' and $subject =~ m/^\. / ) {
      $label =~ s/(.*?) : \. (.*)/$1 : $2<sup>*<\/sup>/;
    }
    return $label;
  }
}

sub get_doclabel {
  my $lang      = shift || die "param missing";
  my $doc_id    = shift || die "param missing";
  my $field_ref = shift || die "param missing";

  my $label;
  if ( $field_ref->{title} ) {
    if ( $field_ref->{author} ) {
      $label = "$field_ref->{author}: $label";
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
    warn "Missing pages for $doc_id: ", Dumper $field_ref;
  }

  # encode HTML entities
  $label = encode_entities( $label, '<>&"' );

  return $label;
}

1;
