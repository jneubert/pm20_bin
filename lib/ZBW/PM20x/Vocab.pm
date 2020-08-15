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
  my $voc = ZBW::PM20x::Vocab->new('ag');

  my $last_modified = $voc->modified;
  my $label = $voc->label($id);
  my $signature = $voc->signature($id);
  my $term_id = $voc->lookup_signature('A10');
  my $subheading = $voc->subheading('A');
  my $folder_count = $voc->folder_count( 'subject', $id );
  
  set_folder_count($type, $id, $count);
  broader($id)

	my ($category_ref, $sig_lookup_ref, $modified_date) = get_vocab('ag');

=head1 DESCRIPTION

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

=item new ($vocab_name)

Return a new vocab object from the named vocabulary. (Names are lowercase ifis
klass_code).  Read the according SKOS vocabluary in JSONLD format into the
object.

=cut

sub new {
  my $class      = shift or croak('param missing');
  my $vocab_name = shift or croak('param missing');

  my $self = { vocab_name => $vocab_name };
  bless $self, $class;

  # initialize with file
  my ( %cat, %lookup, $modified );
  my $file = path("$RDF_ROOT/$vocab_name.skos.jsonld");
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
        next if not exists $category->{broader};

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
          foreach my $ref ( _as_array( $category->{$field} ) ) {
            $cat{$id}{$field}{ $ref->{'@language'} } = $ref->{'@value'};
          }
        }

        # add signature to lookup table
        $lookup{ $cat{$id}{notation} } = $id;
      } else {
        croak "Unexpectend type $type\n";
      }
    }

    # get the broader id for SM entries from first part of signature
    foreach my $id ( keys %cat ) {
      next if not $cat{$id}{notation} =~ m/ Sm\d/;
      my ($firstsig) = split( / /, $cat{$id}{notation} );

      # special case with artificially introduced x0 level
      if ( $firstsig =~ m/^([a-z])0$/ ) {
        $firstsig = $1;
      }
      $cat{$id}{broader} = $lookup{$firstsig}
        or croak "missing signature $firstsig\n";
    }

    # save state
    $self->{id}       = \%cat;
    $self->{nta}      = \%lookup;
    $self->{modified} = $modified;

    $self->_add_subheadings();
  }

  return $self;
}

=item label ( $lang, $term_id )

Return the label for a term.

=cut

sub label {
  my $self    = shift or croak('param missing');
  my $lang    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $label = $self->{id}{$term_id}{prefLabel}{$lang};

  # mark unchecked translated labels
  if ( $lang eq 'en' and $label =~ m/^\. / ) {
    $label =~ s/\. (.*)/$1 \*/;
  }

  return $label;
}

=item signature ( $term_id )

Return the signature for a term.

=cut

sub signature {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $signature = $self->{id}{$term_id}{notation};

  return $signature;
}

=item siglink ( $term_id )

Return the signature for a term, formatted suitable for a link.

=cut

sub siglink {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $siglink = $self->{id}{$term_id}{notation};
  $siglink =~ s/ /_/g;

  return $siglink;
}

=item subheading ( $lang, $key )

Return the subheading for a key (normally, the first letter of the signature).

=cut

sub subheading {
  my $self = shift or croak('param missing');
  my $lang = shift or croak('param missing');
  my $key  = shift or croak('param missing');

  my $subheading = $self->{subhead}{$key}{$lang};

  return $subheading;
}

=item scope_note( $term_id )

Return the scope note for a term, or undef, if not defined.

=cut

sub scope_note {
  my $self    = shift or croak('param missing');
  my $lang    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $scope_note = $self->{id}{$term_id}{scopeNote}{$lang};

  return $scope_note;
}

=item geo_category_type( $term_id )

Return the geo_category_type (A for "Sternchenland", B for normal, C for "Kästschenland), or undef, if not defined.

=cut

sub geo_category_type {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $geo_category_type = $self->{id}{$term_id}{geoCategoryType};

  return $geo_category_type;
}

=item folders_complete( $term_id )

Return true if the subject folders are comlete for a country, false otherwise. 

=cut

sub folders_complete {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $folders_complete;
  if (  $self->{id}{$term_id}{folders_complete}
    and $self->{id}{$term_id}{folders_complete} eq 'Y' )
  {
    $folders_complete = 1;
  }

  return $folders_complete;
}

=item folder_count( $detail_type, $term_id )

Return the folder_count (A for "Sternchenland", B for normal, C for "Kästschenland), or undef, if not defined.

=cut

sub folder_count {
  my $self        = shift or croak('param missing');
  my $detail_type = shift or croak('param missing');
  my $term_id     = shift or croak('param missing');

  # TODO get from loaded data
  my $count_prop   = "${detail_type}FolderCount";
  my $folder_count = $self->{id}{$term_id}{$count_prop} || '';

  return $folder_count;
}

############ internal

sub _as_array {
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

sub _add_subheadings {
  my $self = shift or croak('param missing');

  if ( $self->{vocab_name} eq 'ag' ) {
    $self->{subhead} = {
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
  } elsif ( $self->{vocab_name} eq 'je' ) {
    foreach my $id ( keys %{ $self->{id} } ) {
      my %terminfo  = %{ $self->{id}{$id} };
      my $signature = $terminfo{notation};
      next if not $signature =~ m/^[a-z]$/;
      foreach my $lang (@LANGUAGES) {
        my $label = $terminfo{prefLabel}{$lang};

        # remove generalizing phrases
        $label =~ s/, Allgemein$//i;
        $label =~ s/, General$//i;

        $self->{subhead}{$signature}{$lang} = $label;
      }
    }
  }
  return;
}

1;

