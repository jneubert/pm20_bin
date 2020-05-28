#!/bin/env perl
# nbt, 2020-04-20

# Create symlinks for a range film images in web.public
# (requires a checked.yaml file in the film directory)

use strict;
use warnings;
use utf8;

use Data::Dumper;
use Path::Tiny;
use YAML::Tiny;

binmode( STDOUT, ":utf8" );

my $film_root     = path('/disc1/pm20/film/');
my $pub_film_root = path('/disc1/pm20/web.public/film/');

my ( $holding, $film_id, $dir );

if ( scalar(@ARGV) < 1 ) {
  &usage;
  exit;
} else {
  $holding = $ARGV[0];
  $film_id = $ARGV[1] || undef;
  if ( not $holding =~ m/h(1|2)\/(sh|wa|co)/ ) {
    &usage;
    exit;
  }
}

# processing
if ( defined $film_id ) {
  # one single film directory
  $film_id =~ m/(S|W|A|F)(\d{4})(H|K)/ or die "Film id $film_id not valid\n";
  $dir = $film_root->child($holding)->child($film_id);
  link_film($dir);
} else {
  $film_root->child($holding)->visit( \&link_film );
}

################

sub usage {
  print "usage: (h1|h2)/(sh|wa|co) {film-id}\n";
}

sub link_film {
  my $dir = shift or die "param missing";
  return unless -d $dir;

  my $checked_fn = $dir->child('checked.yaml');
  return unless -f $checked_fn;
  my $checked = YAML::Tiny->read($checked_fn);
  ##print Dumper $checked; exit;

  # prepare target dir
  my $target_dir = get_target_dir($dir);
  print "$target_dir\n";
  prepare_target_dir($target_dir);

  foreach my $section ( @{$checked} ) {

    # skip empty "undef" section at the end
    next if not $section;

    print Dumper $section;
    check_section_fields($checked_fn, $section);
    link_section($dir, $section->{start}, $section->{end});
  }
}

sub prepare_target_dir {
  my $target_dir = shift or die "param missing";

  # create empty public film directory or purge symlinks from it
  if ( !-d $target_dir ) {
    $target_dir->mkpath;
  } else {
    foreach my $symlink ( $target_dir->children ) {
      next unless -l $symlink;
      $symlink->remove;
    }
  }
  return $dir;
}

sub link_section {
  my $dir       = shift or die "param missing";
  my $start_img = shift or die "param missing";
  my $end_img   = shift or die "param missing";

  # TODO extend for half films
  $dir =~ m/(S|W|A|F)(\d{4})(H|K)/ or die "Film id in $dir not valid\n";
  for ( my $i = $start_img ; $i <= $end_img ; $i++ ) {

    my $start_chr = $1;
    my $film_no   = $2;
    my $end_chr   = $3;

    # build and check source file name
    my $img_fn =
      $start_chr . "$film_no" . sprintf( "%04d", $i ) . $end_chr . '.jpg';
    my $src = $dir->child($img_fn);
    die "File $src missing: $!\n" if not $src->is_file;

    # check if a the source file is locked
    next if is_locked($src);

    # build target file name and create as symlink
    my $target_dir = get_target_dir($dir);
    my $target     = $target_dir->child($img_fn);
    symlink( $src, $target ) or die "Could not create symlink $target: $!\n";

    print "$i: $src\n";
  }
}

sub get_target_dir {
  my $dir = shift or die "param missing";

  return $pub_film_root->child( $dir->relative($film_root) );
}

sub is_locked {
  my $src = shift or die "param missing";

  ( my $lock = $src ) =~ s/(.*?)\.jpg/$1.locked.txt/;

  # TODO extend with date/qid from file contents for moving wall

  if ( -f $lock ) {
    return 1;
  } else {
    return 0,;
  }
}

sub check_section_fields {
  my $checked_fn = shift or die "param missing";
  my $section = shift or die "param missing";

  my @required_fields = qw/ title_de title_en start end checked_by checked_date /;

  foreach my $field (@required_fields) {
    if (not defined $section->{$field}) {
      die "missing $field field in $checked_fn\n";
    }
  }
}
