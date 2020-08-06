# nbt, 2020-08-06

package ZBW::PM20x::Vocab;

use strict;
use warnings;

use JSON;
use Path::Tiny;
use Scalar::Util qw(looks_like_number reftype);

=head1 NAME

ZBW::PM20x::Vocab - Functions for PM20 vocabularies


=head1 SYNOPSIS

  use ZBW::PM20x::Vocab;
	my ($category_ref, $sig_lookup_ref, $modified_date) = get_vocab($vocab_file);

=head1 DESCRIPTION



=cut

=item get_vocab ($vocab_file)

Read a SKOS vocabluary in JSONLD format into perl datastructures

=cut

sub get_vocab {
  my $file = shift or die "param missing";

  my ( %cat, %lookup, $modified );
  foreach my $lang (qw/ en de /) {
    my @categories =
      @{ decode_json( $file->slurp )->{'@graph'} };

    # read jsonld graph
    foreach my $category (@categories) {

      my $type = $category->{'@type'};
      if ( $type eq 'skos:ConceptScheme' ) {
        $modified = $category->{modified};
      } elsif ( $type eq 'skos:Concept' ) {

        # skip orphan entries
        next unless exists $category->{broader};

        my $id = $category->{identifier};

        # map optional simple jsonld fields to hash entries
        my @fields =
          qw / notation notationLong foldersComplete geoCategoryType /;
        foreach my $field (@fields) {
          $cat{$id}{$field} = $category->{$field};
        }

        # map optional language-specifc jsonld fields to hash entries
        @fields = qw / prefLabel scopeNote /;
        foreach my $field (@fields) {
          foreach my $ref ( as_array( $category->{$field} ) ) {
            $cat{$id}{$field}{ $ref->{'@language'} } = $ref->{'@value'};
          }
        }

        # create lookup table for signatures
        $lookup{ $cat{$id}{notation} } = $id;
      } else {
        die "Unexpectend type $type\n";
      }
    }
  }
  # get the broader id for SM entries from first part of signature
  foreach my $id (keys %cat) {
    next unless $cat{$id}{notation} =~ m/ Sm\d/;
    my ($firstsig) = split(/ /, $cat{$id}{notation});

    # special case with artificially introduced x0 level
    if ($firstsig =~ m/^([a-z])0$/) {
      $firstsig = $1;
    }
    $cat{$id}{broader} = $lookup{$firstsig} or die "missing signature $firstsig\n";
  }

  return \%cat, \%lookup, $modified;
}

sub as_array {
  my $ref = shift;

  my @list = ();
  if ($ref) {
    if ( reftype($ref) eq 'ARRAY' ) {
      @list = @{$ref};
    } else {
      @list = ($ref);
    }
  }
  return @list;
}

1;

