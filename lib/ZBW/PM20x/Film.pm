# nbt, 2024-04-30

package ZBW::PM20x::Film;

use strict;
use warnings;
use utf8;

use Carp qw/ cluck confess croak /;
use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;

Readonly my $RDF_ROOT  => path('../data/rdf');
Readonly my $IMG_COUNT => _init_img_count();

# items in a collection are primarily grouped by $type, identified by zotero
# or filmlist properties
Readonly my %GROUPING_PROPERTY => (
  co => {
    ## ignore countries for now!
    primary_group => {
      type       => 'company',
      zotero     => 'pm20Id',
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
      rdf_pred   => 'zbwext:subject',
      rdf_prefix => 'pm20subject',
    },
  },
);

# $FILM =     { $film_id => [ $section_uri ] }
# $SECTION =  { $section_uri => { img_count, ...} }
# $FOLDER =   { $collection => { $folder_nk => { $filming => [ $section_uri, ... ] } } }
# $CATEGORY = { $category_type => { $category_id => { $filming => [ $section_uri ... ] } } }
# DOES NOT WORK WITH Readonly!
##Readonly my ( $FILM, $SECTION, $FOLDER, $CATEGORY ) => _load_filmdata();
my ( $FILM, $SECTION, $FOLDER, $CATEGORY ) = _load_filmdata();

=encoding utf8

=head1 NAME

ZBW::PM20x::Film - Functions for PM20 microfilms


=head1 SYNOPSIS

  use ZBW::PM20x::Film;
  my $film = ZBW::PM20x::Film->new('h1/sh/S0073H_1');
  my @films = ZBW::PM20x::Film->films('h1_sh');
  my @sections = ZBW::PM20x::Film->foldersections('co/004711', 1);

  my $film_name = $film->name();              # S0073H_1
  my $logical_name = $film->logigcal_name();  # S0073H
  my $number_of_images = $film->img_count();

=head1 DESCRIPTION

The instances of this class represent digitized microfilms, as they are
physically organized on disk, e.g. S0073H_1. The superior unit (S0073H) is
called logical film.


=head1 Class methods

=over 2

=item new ($film_id)

Return a new film object from the named vocabulary.

=cut

sub new {
  my $class   = shift or croak('param missing');
  my $film_id = shift or croak('param missing');

  my ( $set, $collection, $film_name );

  # TODO check/extend for Kiel films
  # NB a film named "S0901aH" exists!
  if ( $film_id =~ m;^(h[12])/(co|wa|sh)/([AFSW]\d{4}a?H(_[12])?$)$; ) {
    $set        = $1;
    $collection = $2;
    $film_name  = $3;
  } else {
    confess "Invalid film id $film_id";
  }

  my $self = {
    film_id    => $film_id,
    set        => $set,
    collection => $collection,
    film_name  => $film_name
  };
  bless $self, $class;

  return $self;
}

=item get_grouping_properties ($collection)

Return metadata structure about the grouping properties for a collection.

=cut

sub get_grouping_properties {
  my $class      = shift or croak('param missing');
  my $collection = shift or croak('param missing');

  return $GROUPING_PROPERTY{$collection};
}

=item films ($subset)

Return a list of films sorted by film id for a subset (e.g. "h1_sh").

=cut

sub films {
  my $class  = shift or croak('param missing');
  my $subset = shift or croak('param missing');

  my @films;

  my $subset_path = $subset =~ s/_/\//r;

  foreach my $film_id ( keys %{$IMG_COUNT} ) {
    next unless $film_id =~ m/^$subset_path\//;

    # fix error with redundant _1/_2 and full films (e.g. A0023H)
    next
      if (defined $IMG_COUNT->{ ${film_id} . '_1' }
      and defined $IMG_COUNT->{ ${film_id} . '_2' } );

    # fix special case A0040H and A0040H_1 (no _2 exists)
    next if $film_id eq 'h1/co/A0040H';

    my $film = $class->new($film_id);

    next unless $film->img_count;

    push( @films, $film );
  }

  @films = sort { $a->{film_id} cmp $b->{film_id} } @films;

  return @films;
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

=back

=head1 Instance methods

=over 2

=item name ()

Return the actual name of the film (e.g., S0073H_1).

=cut

sub name {
  my $self = shift or croak('param missing');

  my $name = $self->{film_name};

  return $name;
}

=item logical_name ()

Return the name of the film (e.g., S0073H) - ignoring pysical splits.

=cut

sub logical_name {
  my $self = shift or croak('param missing');

  my $logical_name = $self->{film_name};
  $logical_name =~ s/^(.+)?_[12]$/$1/;

  return $logical_name;
}

=item img_count ()

Return the numer of images files under the film directory.

=cut

sub img_count {
  my $self = shift or croak('param missing');

  my $img_count = $IMG_COUNT->{ $self->{film_id} };

  return $img_count;
}

=back

=cut

############ internal

sub _init_img_count {

  my %img_count;
  my $raw_ref =
    decode_json( path('/pm20/data/filmdata/img_count.json')->slurp() );
  foreach my $raw_id ( keys %{$raw_ref} ) {

    # skip misnamend (and empty) films
    next if $raw_id =~ m/F0549H_3$/;
    next if $raw_id =~ m/S9393$/;
    next if $raw_id =~ m/S9398$/;
    next if $raw_id =~ m/dummy$/;

    # strip filesystem prefix from film id
    $raw_id =~ m;^/pm20/film/(.+)$;;
    $img_count{$1} = $raw_ref->{$raw_id};
  }

  return \%img_count;
}

sub _load_filmdata {

  my ( $FILM, $SECTION, $FOLDER, $CATEGORY );

  my $film_file = path('../data/rdf/film.jsonld');
  my @filmdata  = @{ decode_json( $film_file->slurp )->{'@graph'} };

  foreach my $filmdata_ref (@filmdata) {
    my $type = $filmdata_ref->{'@type'};
    my $uri  = $filmdata_ref->{'@id'};
    if ( $type eq 'Pm20FilmItem' ) {
      $SECTION->{$uri} = $filmdata_ref;
    } elsif ( $type eq 'Pm20Film' ) {
      $FILM->{$uri} = $filmdata_ref;
    } else {
      ## subsets
      ##print Dumper $filmdata_ref;
    }
  }

  # folders and categories
  foreach my $section_uri ( sort keys %{$SECTION} ) {
    $section_uri =~ m;/film/h(1|2)/(co|wa|sh)/(.+)?/(\d+)(?:/(R|L))?$;;
    my $filming    = $1;
    my $collection = $2;
    my $film_name  = $3;
    my $img_nr     = $4;
    my $rl         = $5;

    my $section_ref = $SECTION->{$section_uri};

    # folders (currently only for co)
    if ( my $pm20_uri = $section_ref->{about}{'@id'} ) {
      $pm20_uri =~ m;folder/co/(\d{6});;
      my $folder_nk = $1;
      push( @{ $FOLDER->{$collection}{$folder_nk}{$filming} }, $section_uri );
    }

    # categories
    else {
      my $grp_prop_ref = ZBW::PM20x::Film->get_grouping_properties($collection);
      my $category_type = $grp_prop_ref->{primary_group}{type};
      my $category_prop = $grp_prop_ref->{primary_group}{jsonld};

      if ( $section_ref->{$category_prop}
        and my $category_uri = $section_ref->{$category_prop}{'@id'} )
      {
        $category_uri =~ m;category/$category_type/i/(\d{6});;
        my $category_id = $1;
        push(
          @{ $CATEGORY->{$category_type}{$category_id}{$filming} },
          $section_uri
        );
      }
    }
  }
  return $FILM, $SECTION, $FOLDER, $CATEGORY;
}

1;

