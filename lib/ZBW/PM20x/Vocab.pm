# nbt, 2020-08-06

package ZBW::PM20x::Vocab;

use strict;
use warnings;

use Carp;
use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number reftype);

Readonly my $RDF_ROOT  => path('../data/rdf');
Readonly my @LANGUAGES => qw/ en de /;

my %vocab_all;

=head1 NAME

ZBW::PM20x::Vocab - Functions for PM20 vocabularies


=head1 SYNOPSIS

  use ZBW::PM20x::Vocab;
	my ($category_ref, $sig_lookup_ref, $modified_date) = get_vocab('ag');

=head1 DESCRIPTION


=cut

=item get_vocab_all ()

Read all vocabularies into a data structure, organized as:

  {$vocab}          e.g., 'ag'
    id              by identifier (main term entry)
      {$id}         hash with everything from database
    modified        last modification of the vocabulary
    nta             by signature
      {$signature}  points to id
    subhead         subheadings for lists
      {$first}      first letter of signature

=cut

sub get_vocab_all {

  foreach my $vocab (qw/ ag je /) {
    get_vocab($vocab);
    add_subheadings($vocab);
  }
  return \%vocab_all;
}

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

  if (not defined $vocab_all{$vocab}{id}{$term_id}) {
    confess "Term $term_id not defined in vocab $vocab";
  }
  my $label = $vocab_all{$vocab}{id}{$term_id}{prefLabel}{$lang};

  # mark unchecked translated labels
  if ( $lang eq 'en' and $label =~ m/^\. / ) {
    $label =~ s/\. (.*)/$1 \*/;
  }

  # optionally, prepend with signature
  if ($with_signature) {
    $label = "$vocab_all{$vocab}{id}{$term_id}{notation} $label";
  }

  return $label;
}

=item get_siglink ( $vocab, $term_id )

Return the signature for a term, formatted suitable for a link.

=cut

sub get_siglink {
  my $vocab   = shift or die "param missing";
  my $term_id = shift or die "param missing";

  my $siglink = $vocab_all{$vocab}{id}{$term_id}{notation};
  $siglink =~ s/ /_/g;

  return $siglink;
}

############ internal

sub add_subheadings {
  my $vocab = shift or die "param missing";

  my $subheading_ref;

  if ( $vocab eq 'ag' ) {
    $subheading_ref = {
      A => {
        de => 'Europa',
        en => 'Europe',
      },
      B => {
        de => 'Asien',
        en => 'Asia',
      },
      C => {
        de => 'Afrika',
        en => 'Africa',
      },
      D => {
        de => 'Australien und Ozeanien',
        en => 'Australia and Oceania',
      },

      E => {
        de => 'Amerika',
        en => 'America',
      },

      F => {
        de => 'Polargebiete',
        en => 'Polar regions',
      },

      G => {
        de => 'Meere',
        en => 'Seas',
      },

      H => {
        de => 'Welt',
        en => 'World',
      },
    };
  } elsif ($vocab eq 'je') {
    foreach my $id ( keys %{ $vocab_all{$vocab}{id} } ) {
      my %terminfo = %{ $vocab_all{$vocab}{id}{$id} };
      my $signature = $terminfo{notation};
      next unless $signature =~ m/^[a-z]$/;
      foreach my $lang (@LANGUAGES) {
        my $label = $terminfo{prefLabel}{$lang};

        # remove generalizing phrases
        $label =~ s/, Allgemein$//i;
        $label =~ s/, General$//i;

        $subheading_ref->{$signature}{$lang} = $label;
      }
    }
  }

  $vocab_all{$vocab}{subhead} = $subheading_ref;

  return $subheading_ref;
}

1;

