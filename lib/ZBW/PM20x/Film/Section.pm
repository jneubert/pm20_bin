# nbt, 2025-11-15

package ZBW::PM20x::Film::Section;

use strict;
use warnings;
use autodie;
use utf8::all;

use Carp qw/ cluck confess croak /;
use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;
use ZBW::PM20x::Film;
use ZBW::PM20x::Vocab;

Readonly my $FILM_ROOT_URI => 'https://pm20.zbw.eu/film/';

# items in a collection are primarily grouped by $type, identified by zotero
# or filmlist properties
# CAUTION: for geo categories, subject, ware and company categories are related!
Readonly my %GROUPING_PROPERTY => (
  co => {
    ## ignore countries for now! (logically primary category for companies?)
    primary_group => {
      type       => 'company',
      zotero     => 'pm20_id',
      filmlist   => 'start_company_id',
      jsonld     => 'about',
      rdf_pred   => 'schema:about',
      rdf_prefix => 'pm20co',
    },
  },
  wa => {
    primary_group => {
      type       => 'ware',
      zotero     => 'ware_id',
      filmlist   => 'start_ware_id',
      jsonld     => 'ware',
      rdf_pred   => 'zbwext:ware',
      rdf_prefix => 'pm20ware',
    },
    secondary_group => {
      type       => 'geo',
      zotero     => 'geo_id',
      filmlist   => 'start_company_id',
      jsonld     => 'country',
      rdf_pred   => 'zbwext:country',
      rdf_prefix => 'pm20geo',
    },
  },
  sh => {
    primary_group => {
      type       => 'geo',
      zotero     => 'geo_id',
      filmlist   => 'start_geo_id',
      jsonld     => 'country',
      rdf_pred   => 'zbwext:country',
      rdf_prefix => 'pm20geo',
    },
    secondary_group => {
      type       => 'subject',
      zotero     => 'subject_id',
      jsonld     => 'subject',
      rdf_pred   => 'zbwext:subject',
      rdf_prefix => 'pm20subject',
    },
  },
);

# Film structures

# $FILM =     { $film_id => { total_image_count, ... }, sections => [ $section_uri, ... ] }
# $SECTION =  { $section_uri => { img_count, ...} }

# Film::Section structures

# $SECTION =  { $section_uri => $section, ... }
# $FOLDER =   { $collection => { $folder_nk => { $filming => [ $section_uri, ... ] } } }
# $CATEGORY = { $category_type => { $category_id => { $filming => [ $section_uri ... ] } } }
# $CATEGORY_INV = { $type => { $secondary_category_id => { $filming => [ $section_uri ... ] } } }

my ( $SECTION, $FOLDER, $CATEGORY, $CATEGORY_INV );
( $SECTION, $FOLDER, $CATEGORY, $CATEGORY_INV ) = _init_data();

my %vocab = (
  subject => undef,
  geo     => undef,
  ware    => undef,
);

=encoding utf8

=head1 NAME

ZBW::PM20x::Film::Section - Functions for sections of PM20 microfilms

=head1 SYNOPSIS

  use ZBW::PM20x::Film::Section;
  my $section = ZBW::PM20x::Film::Section->init_from_uri('https://pm20.zbw.eu/film/h1/sh/S0373H/0002');
  my $section = ZBW::PM20x::Film::Section->init_from_id('h1/sh/S0373H/1115/R');

  my @folder_sections = ZBW::PM20x::Film::Section->foldersections('co/004711', 1);

=head1 DESCRIPTION

A film section is defined by the film, by the number of the image with which the
section starts.  and optionally /(L|R) for the left or right page on the image.

=head1 Class methods

=over 2

=item init_from_uri ($uri)

Return a filmsection object for the filmsection uri from film data.

=cut

sub init_from_uri {
  my $class       = shift or croak('param missing');
  my $section_uri = shift or croak('param missing');

  my ( $section_id, $film_id, $img_nr, $img_pos );

  # TODO check/extend for Kiel films
  # NB a film named "S0901aH" exists!
  if ( $section_uri =~
m;^${FILM_ROOT_URI}((h[12]/(?:co|wa|sh)/[AFSW]\d{4}a?H(?:_[12])?)/(\d{4})(?:/([LR]))?)$;
    )
  {
    $section_id = $1;
    $film_id    = $2;
    $img_nr     = $3;
    $img_pos    = $4;
  } else {
    confess "Invalid film section uri $section_uri";
  }

  my $self = $SECTION->{$section_uri};
  if ( not $self ) {
    confess "Invalid film section uri $section_uri";
  }

  bless $self, $class;

  return $self;
}

=item init_from_id ($section_id)

Return a filmsection object for the filmsection id.

=cut

sub init_from_id {
  my $class      = shift or croak('param missing');
  my $section_id = shift or croak('param missing');

  my $uri = $FILM_ROOT_URI . $section_id;

  my $self = $class->init_from_uri($uri);

  return $self;
}

=item foldersections ($folder_id, $filming)

Return a list of film sections for the folder, for a certain filming (1|2).
Currently, only for collection 'co'.

=cut

sub foldersections {
  my $class     = shift or croak('param missing');
  my $folder_id = shift or croak('param missing');
  my $filming   = shift or croak('param missing');

  my @sectionlist;
  my ( $collection, $folder_nk ) = $folder_id =~ m;^(co)/(\d{6})$;;

  foreach my $section_uri ( @{ $FOLDER->{$collection}{$folder_nk}{$filming} } )
  {
    my %entry = ( $section_uri => $SECTION->{$section_uri}, );
    push( @sectionlist, $SECTION->{$section_uri} );
  }
  return @sectionlist;
}

=item categorysections ($category_type, $category_id, $filming)

Return a list of film sections of type secondary for a certain primary category, for a
certain filming (1|2).

Valid $category_type are:

=over 2

=item *

geo - retrieves a list of subject entries for this geo

=item *

ware - retrieves a list of geo entries for this ware

=back

=cut

sub categorysections {
  my $class         = shift or croak('param missing');
  my $category_type = shift or croak('param missing');
  my $category_id   = shift or croak('param missing');
  my $filming       = shift or croak('param missing');

  croak("wrong category type $category_type")
    unless $category_type =~ m/^(geo|ware)$/;

  return unless $CATEGORY->{$category_type}{$category_id}{$filming};

  my @sectionlist = @{ $CATEGORY->{$category_type}{$category_id}{$filming} };

  return @sectionlist;
}

=item categorysections_inv ($category_type, $category_id, $filming)

Inversely, return a list of film sections of type primary for a certain
secondary category, for a certain filming (1|2).

Valid $category_type are:

=over 4

=item *

geo - retrieves a list of ware entries for this geo

=item *

subject - retrieves a list of geo entries for this subject

=back

=cut

sub categorysections_inv {
  my $class         = shift or croak('param missing');
  my $category_type = shift or croak('param missing');
  my $category_id   = shift or croak('param missing');
  my $filming       = shift or croak('param missing');

  croak("wrong category type $category_type")
    unless $category_type =~ m/^(geo|subject)$/;

  return unless $CATEGORY_INV->{$category_type}{$category_id}{$filming};

  my @sectionlist =
    @{ $CATEGORY_INV->{$category_type}{$category_id}{$filming} };

  return @sectionlist;
}

=item get_grouping_properties ($collection)

Return metadata structure about the grouping properties for a collection.

=cut

sub get_grouping_properties {
  my $class      = shift or croak('param missing');
  my $collection = shift or croak('param missing');

  return $GROUPING_PROPERTY{$collection};
}

=item is_valid_section_uri ($uri)

Returns 1 if the film section URI is valid.

=cut

sub is_valid_section_uri {
  my $class = shift or croak('param missing');
  my $uri   = shift or croak('param missing');

  my $is_valid;
  if ( $uri =~
    m;^${FILM_ROOT_URI}h[12]/(co|wa|sh)/[AFSW]\d{4}a?H(_[12])?/\d{4}(/[LR])?$; )
  {
    $is_valid = 1;
  }

  return $is_valid;
}

=back

=head1 Instance methods

=over 2

=item id ()

Return the id of the section (e.g., h1/sh/S0373H/1115/R).

=cut

sub id {
  my $self = shift or croak('param missing');

  my $uri = $self->{'@id'};
  my ($id) = $uri =~
m;^${FILM_ROOT_URI}(h[12]/(?:co|wa|sh)/[AFSW]\d{4}a?H(?:_[12])?/\d{4}(?:/[LR])?)$;;

  return $id;
}

=item uri ()

Return the URI of the section (e.g., https://pm20.zbw.eu/film/h1/sh/S0373H/1115/R).

=cut

sub uri {
  my $self = shift or croak('param missing');

  my $uri = $self->{'@id'};

  return $uri;
}

=item collection ()

Return the collection for the section.

=cut

sub collection {
  my $self = shift or croak('param missing');

  # extract from uri
  my ($collection) = $self->{'@id'} =~ m;/(co|wa|sh)/;;

  return $collection;
}

=item filming ()

Return the filming for the section.

=cut

sub filming {
  my $self = shift or croak('param missing');

  # extract from uri
  my ($filming) = $self->{'@id'} =~ m;/[hk]([12])/(?:co|wa|sh)/;;

  return $filming;
}

=item title ()

Returns the full section title, as captured in Zotero or in the film lists,
always in German.

=cut

sub title {
  my $self = shift or croak('param missing');

  my $title = $self->{'title'};

  return $title;
}

=item label ( $lang, $detail_voc )

Returns the partial category label from $detail_voc, in the according language.

The full title may include additional information (e.g., individual diseases,
or political relations to ...). For now, these keywords are added in German.

For entries from the filmlists, currently no label can be generated (because of
missing ids), and the full German title is returned.

=cut

sub label {
  my $self       = shift or croak('param missing');
  my $lang       = shift or croak('param missing');
  my $detail_voc = shift or croak('param missing');

  my $section_id = $self->id;
  my $collection = $self->collection;
  my $vocab_name = $detail_voc->vocab_name;
  my $term_id;

  # lazy load
  if (not defined $vocab{$vocab_name}) {
    __PACKAGE__->_load_vocab($vocab_name);
  }

  # sh
  if ( $collection eq 'sh' ) {
    if ( $vocab_name eq 'geo' ) {
      if ( $self->{country}{'@id'} =~ m;.+/i/(\d{6})$; ) {
        $term_id = $1;
      }
    }
    elsif ( $vocab_name eq 'subject' ) {
      if ( $self->{subject} && $self->{subject}{'@id'} =~ m;.+/i/(\d{6})$; ) {
        $term_id = $1;
      } else {
        return;
      }
    }
  }

  # wa
  elsif ( $collection eq 'wa' ) {
    if ( $vocab_name eq 'ware' ) {
      if ( $self->{ware}{'@id'} =~ m;.+/i/(\d{6})$; ) {
        $term_id = $1;
      }
    }
    elsif ( $vocab_name eq 'geo' ) {
      if ( $self->{country} && $self->{country}{'@id'} =~ m;.+/i/(\d{6})$; ) {
        $term_id = $1;
      } else {
        return;
      }
    }
  }

  # vocab lookup
  my $label = $vocab{$vocab_name}->label( $lang, $term_id );
  warn "$section_id: Term $term_id not found in $vocab_name\n" unless $label;

  # TODO handle labels with keys/translations
  # for ware, we for now have labels combined with keywords
  if ( $collection eq 'sh' ) {
    if ( $self->{keywords} ) {
      $label = "$label - " . $self->{keywords}[0];
    }
  }
  return $label;
}

=item img_count ()

Returns the number of images in this section, or undef, if section or count is
not defined.

Uses totalImageCount property - may that span more than one film?
See read_zotero.pl for the computation of number_of_images.

=cut

sub img_count {
  my $self       = shift or croak('param missing');
  
  return $self->{totalImageCount};
}

##### helper procedures - only internally used?

sub is_known_variant {
  my $vocab_name = shift or croak('param missing');
  my $string     = shift or croak('param missing');

  # prepare lookup
  my %variant;
  my $list_str = << 'EOF';
Neufundland
Nigeria
Osmanisches Reich
Protektorat
Saarland
Sowjetunion
Vereinigte Staaten
Jugoslawien
Palästina
Türkei
Südwestafrika
Danzig
Russland
Deutschland (bis 1945)
Nordische Länder
Böhmen und Mähren (Reichsprotektorat)
Französisch-Nordafrika
Ostpreussen
Memel
Elsass-Lothringen
Neu Kaledonien
Posen
EOF
  my @list = split( "\n", $list_str );
  foreach my $key (@list) {
    $variant{$key} = 1;
  }

  my $is_variant = $variant{$string};

  return $is_variant;
}

sub has_known_subdivisions {
  my $title = shift or croak('param missing');

  my $list_str = << 'EOF';
Außenpolitik und politische Beziehungen zum Ausland
Wahlen für parlamentarische Körperschaften
Fremdländische Kapitalanlagen, privatwirtschaftliche Interessen, Angehöriger
Geschichtliche Vorgänge in einzelnen Staaten, Provinzen und Städten
Einwanderer aus
Schiffsverkehr mit
Politische Beziehungen zu
Wirtschaftspolitische Beziehungen zu
Handelsbeziehungen zu
Minderheiten aus einzelnen Ländern
Verhandlungen parlamentarischer Körperschaften einzelner Regionen
Staatsgrenzen gegenüber einzelnen Ländern
Landeskunde, Landschaften, Beschreibung einzelner Orte und Gegenden
Nationale Angehörige im Ausland, in einzelnen Ländern
Geheimbünde, Einzelne
Bevölkerungsbewegung und Bevölkerungsstatistik einzelner Provinzen, Bundesstaaten und Städte
Alliierte und assoziierte Mächte, Ministerkonferenzen und Botschafterkonferenzen
Völkerbundsversammlung (Verhandlungen)
Völkerbundsrat (Verhandlungen)
Ständige Organisation der Arbeit, Hauptversammlungen
einzelne
Einzelne
EOF
  my @list = split( "\n", $list_str );

  my $has_subdivisions;
  foreach my $key (@list) {
    if ( $title =~ m/$key/ ) {
      $has_subdivisions = 1;
    }
  }

  return $has_subdivisions;
}

=back

=cut

############ internal

sub _init_data {

  # use the unblessed section data loaded in Film.pm
  my $SECTION_FROM_FILM = ZBW::PM20x::Film::_SECTION();

  # populate $SECTION
  foreach my $section_uri ( sort keys %{$SECTION_FROM_FILM} ) {

    if ( not __PACKAGE__->is_valid_section_uri($section_uri) ) {
      confess "Invalid film section uri $section_uri";
    }

    my $section_data = $SECTION_FROM_FILM->{$section_uri};
    my $section      = bless( $section_data, __PACKAGE__ );

    $SECTION->{$section_uri} = $section;
  }

  # folders and categories
  foreach my $section_uri ( sort keys %{$SECTION} ) {
    my $section = $SECTION->{$section_uri};
    my $filming = $section->filming;
    my $section_id   = $section->id;

    # folders (currently only for co)
    # TODO add folder and section objects
    if ( my $pm20_uri = $section->{about}{'@id'} ) {
      $pm20_uri =~ m;folder/co/(\d{6});;
      my $folder_nk = $1;
      push( @{ $FOLDER->{co}{$folder_nk}{$filming} }, $section->uri );
    }

    # categories
    else {
      # primary group
      my $grp_prop_ref =
        __PACKAGE__->get_grouping_properties( $section->collection );
      my $category_type = $grp_prop_ref->{primary_group}{type};
      my $category_prop = $grp_prop_ref->{primary_group}{jsonld};

      if ( $section->{$category_prop}
        and my $category_uri = $section->{$category_prop}{'@id'} )
      {
        my ($category_id) =
          $category_uri =~ m;category/$category_type/i/(\d{6});;
        push(
          @{ $CATEGORY->{$category_type}{$category_id}{$filming} },
          $section
        );
      }

      next unless $grp_prop_ref->{secondary_group};

      # secondary group
      my $secondary_category_type = $grp_prop_ref->{secondary_group}{type};
      my $secondary_category_prop = $grp_prop_ref->{secondary_group}{jsonld};

      if ( $section->{$secondary_category_prop}
        and my $category_uri = $section->{$secondary_category_prop}{'@id'} )
      {
        if ($category_uri =~ m;category/$secondary_category_type/i/(\d{6});) {
          my $secondary_category_id = $1;
          push(
            @{
              $CATEGORY_INV->{$secondary_category_type}{$secondary_category_id}
                {$filming}
            },
            $section
          );
        } else {
          warn "$section_id: no id for $category_uri\n";
        }
      }
    }
  }
  return $SECTION, $FOLDER, $CATEGORY, $CATEGORY_INV;
}

sub _load_vocab {
  my $class = shift or confess ('class missing');
  my $vocab_name = shift or confess ('param missing');

  $vocab{$vocab_name} = ZBW::PM20x::Vocab->new($vocab_name) || croak;
}

1;

