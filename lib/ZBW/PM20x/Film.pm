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

=encoding utf8

=head1 NAME

ZBW::PM20x::Film - Functions for PM20 microfilms


=head1 SYNOPSIS

  use ZBW::PM20x::Film;
  my $film = ZBW::PM20x::Film->new('h1/sh/S0073H_1');

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

    # strip "historical" prefix from film id
    $raw_id =~ m;^/mnt/intares/film/(.+)$;;
    $img_count{$1} = $raw_ref->{$raw_id};
  }

  return \%img_count;
}

1;

