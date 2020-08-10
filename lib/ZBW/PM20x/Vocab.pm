# nbt, 2020-08-06

package ZBW::PM20x::Vocab;

use strict;
use warnings;

use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number reftype);

Readonly my $RDF_ROOT => path('../data/rdf');

my %vocab_all;

=head1 NAME

ZBW::PM20x::Vocab - Functions for PM20 vocabularies


=head1 SYNOPSIS

  use ZBW::PM20x::Vocab;
	my ($category_ref, $sig_lookup_ref, $modified_date) = get_vocab('ag');

=head1 DESCRIPTION



=cut

=item get_vocab ($vocab)

Read a SKOS vocabluary in JSONLD format into perl datastructures

=cut

sub get_vocab {
  my $vocab = shift or die "param missing";

  if ( not defined $vocab_all{$vocab} ) {

    my ( %cat, %lookup, $modified );
    my $file = path("$RDF_ROOT/$vocab.skos.jsonld");
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
    foreach my $id ( keys %cat ) {
      next unless $cat{$id}{notation} =~ m/ Sm\d/;
      my ($firstsig) = split( / /, $cat{$id}{notation} );

      # special case with artificially introduced x0 level
      if ( $firstsig =~ m/^([a-z])0$/ ) {
        $firstsig = $1;
      }
      $cat{$id}{broader} = $lookup{$firstsig}
        or die "missing signature $firstsig\n";
    }

    # save vocabs for later invocations
    $vocab_all{$vocab}{id}       = \%cat;
    $vocab_all{$vocab}{nta}      = \%lookup;
    $vocab_all{$vocab}{modified} = $modified;
  }

  return $vocab_all{$vocab}{id}, $vocab_all{$vocab}{nta},
    $vocab_all{$vocab}{modified};
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

=item get_termlabel ( $lang, $vocab, $term_id, $with_signature )

Return the label for a term, optionally prepended by signature.

=cut

sub get_termlabel {
  my $lang    = shift or die "param missing";
  my $vocab   = shift or die "param missing";
  my $term_id = shift or die "param missing";
  my $with_signature = shift;

  my $label = $vocab_all{$vocab}{id}{$term_id}{prefLabel}{$lang};
  if ($with_signature) {
    $label = "$vocab_all{$vocab}{id}{$term_id}{notation} $label";
  }
  return $label;
}

1;

