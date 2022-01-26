# nbt, 2020-08-06

package ZBW::PM20x::Vocab;

use strict;
use warnings;
use utf8;

use Carp qw/ cluck confess/;
use Data::Dumper;
use Exporter;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number reftype);

# exported package constants
our @ISA    = qw/ Exporter /;
our @EXPORT = qw/ @LANGUAGES $SM_QR $DEEP_SM_QR /;

Readonly our @LANGUAGES => qw/ en de /;

# identifies "Sondermappen" on different levels
Readonly our $SM_QR => qr/ Sm\d+/;
##Readonly our $DEEP_SM_QR      => qr/ Sm\d+\.[IVX]+/;
Readonly our $DEEP_SM_QR => qr/ Sm\d+\.\d+/;

Readonly my $RDF_ROOT => path('../data/rdf');

# detail type -> relevant count property
Readonly my %COUNT_PROPERTY => (
  subject => 'zbwext:folderCount',
  geo     => 'zbwext:shFolderCount',
);

=encoding utf8

=head1 NAME

ZBW::PM20x::Vocab - Functions for PM20 vocabularies


=head1 SYNOPSIS

  use ZBW::PM20x::Vocab;
  my $voc = ZBW::PM20x::Vocab->new('ag');

  my $last_modified = $voc->modified;
  my $label = $voc->label($lang, $id);
  my $signature = $voc->signature($id);
  my $term_id = $voc->lookup_signature('A10');
  my $subheading = $voc->subheading('A');
  my $folder_count = $voc->folder_count( 'subject', $id );
  
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


  $id   term id (\d{6}, with leading zeros)

=cut

=head1 Class methods

=over 2

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
  my $file = path("$RDF_ROOT/$vocab_name.skos.extended.jsonld");
  foreach my $lang (qw/ en de /) {
    my @categories =
      @{ decode_json( $file->slurp )->{'@graph'} };

    # read jsonld graph
    foreach my $category (@categories) {

      my $type = $category->{'@type'};
      next unless $type;
      if ( $type eq 'skos:ConceptScheme' ) {
        $self->{modified} = $category->{modified};
      } elsif ( $type eq 'skos:Concept' ) {

        # skip orphan entries
        next if not exists $category->{broader};

        my $id = $category->{identifier};

        # map optional simple jsonld fields to hash entries
        my @fields = qw / notation notationLong foldersComplete geoCategoryType
          zbwext:shFolderCount zbwext:folderCount /;
        foreach my $field (@fields) {
          $cat{$id}{$field} = $category->{$field};
        }

        # map optional multivalued language-independent jsonld fields to hash
        # entries
        @fields = qw / exactMatch /;
        foreach my $field (@fields) {
          foreach my $entry ( _as_array( $category->{$field} ) ) {
            if ( $lang eq 'de' ) {
              push( @{ $cat{$id}{$field} }, $entry );
            }
          }
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

        # with extended vocabs, lots of types are possible
        ##croak "Unexpectend type $type\n";
        next;
      }
    }

    # save state
    $self->{id}  = \%cat;
    $self->{nta} = \%lookup;

    # get the broader id for SM entries from first parts of the signature
    # TODO there are more types of hierarchies (below Sm and below ordinary
    # terms, so the second level should not be used before further analysis
    foreach my $id ( keys %cat ) {
      my $signature = $cat{$id}{notation};
      next if not $signature =~ m/ Sm\d/;

      my $start_sig;
      if ( $signature =~ $DEEP_SM_QR ) {
        $start_sig = $self->start_sig( $id, 2 );
      } elsif ( $signature =~ $SM_QR ) {
        $start_sig = $self->start_sig( $id, 1 );

        # special case with artificially introduced x0 level
        if ( $signature =~ m/^([a-z])0$/ ) {
          $start_sig = $1;
        }
      } else {
        cluck("Unknown Sm scheme: signature $signature");
      }
      $cat{$id}{broader} = $lookup{$start_sig}
        or confess("missing signature $start_sig");
    }

    $self->_add_subheadings();
  }

  return $self;
}

=back

=head1 Instance methods

=over 2

=item modified ()

Returns the date of the last (manual) modification of the vocabulary (obtained from the term timestamps).

=cut

sub modified {
  my $self = shift or croak('param missing');

  # apparently, for some vocab, jsonld return a date value, for some a string
  my $modified;
  if ( ref( $self->{modified} ) ) {
    $modified = $self->{modified}{'@value'};
  } else {
    $modified = $self->{modified};
  }

  return $modified;
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
  if ( $lang eq 'en' and $label and $label =~ m/^\. / ) {
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

=item broader ( $term_id )

Return the id for the hierarchically superordinated term.

=cut

sub broader {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $broader = $self->{id}{$term_id}{broader};

  return $broader;
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

=item wdlink( $term_id )

Return a link to the exactly matching Wikidata item

=cut

sub wdlink {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');

  my $wdlink;
  if ( defined $self->{id}{$term_id}{exactMatch} ) {
    my @exact_links = @{ $self->{id}{$term_id}{exactMatch} };
    foreach my $link (@exact_links) {
      if ( $link =~ m|^http://www\.wikidata\.org/entity| ) {
        $wdlink = $link;
        last;
      }
    }
  }

  return $wdlink;
}

=item geo_category_type( $term_id )

Return the geo_category_type (A for "Sternchenland", B for normal, C for "Kästchenland"), or undef, if not defined.

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
  if (  $self->{id}{$term_id}{foldersComplete}
    and $self->{id}{$term_id}{foldersComplete} eq 'Y' )
  {
    $folders_complete = 1;
  }

  return $folders_complete;
}

=item folder_count( $category_type, $term_id )

Return the folder_count (A for "Sternchenland", B for normal, C for "Kästschenland), or undef, if not defined.

=cut

sub folder_count {
  my $self          = shift or croak('param missing');
  my $category_type = shift or croak('param missing');
  my $term_id       = shift or croak('param missing');

  # get from extended vocab data
  my $folder_count =
    $self->{id}{$term_id}{ $COUNT_PROPERTY{$category_type} } || '';
  return $folder_count;
}

=item start_sig ( $term_id, $level )

Returns the start level(s) of the signature, e.g e4 Sm3.IVa

level 1: e4; level 2: e4 Sm3

=cut

sub start_sig {
  my $self    = shift or croak('param missing');
  my $term_id = shift or croak('param missing');
  my $level   = shift or croak('param missing');

  my $signature = $self->signature($term_id);
  my $start_sig;
  if ( $level == 2 ) {
    if ( $signature =~ m/^([a-z]\S*? Sm\d+)(\.[IVX]+|[a-z])/ ) {
      $start_sig = $1;
    } else {
      cluck("no level 2 signature for $term_id $signature");
      return;
    }
  } elsif ( $level == 1 ) {
    if ( $signature =~ m/^([a-z]\S*?) (Sm\d+|\(alt\)|I)/ ) {
      $start_sig = $1;
    } elsif ( $signature =~ m/^\S+$/ ) {
      ## signature does not contain any blanks
      $start_sig = $signature;
    } else {
      cluck("no level 1 signature for $term_id $signature");
      return;
    }
  }
}

=item lookup_signature ( $signature )

Look up a term id by signature, undef if not defined.

=cut

sub lookup_signature {
  my $self      = shift or croak('param missing');
  my $signature = shift or croak('param missing');

  my $term_id = $self->{nta}{$signature};

  return $term_id;
}

=back

=cut

############ internal

sub _as_array {
  my $var = shift;

  # $var may or may not be a reference
  my @list = ();
  if ($var) {
    if ( reftype($var) and reftype($var) eq 'ARRAY' ) {
      @list = @{$var};
    } else {
      @list = ($var);
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

