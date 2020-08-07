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

1;

