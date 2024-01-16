#!/bin/perl
# nbt, 2024-01-15

# merge info from zotero and filmlists by id

use strict;
use warnings;
use utf8;

use Data::Dumper;
use JSON;
use Path::Tiny;
use Readonly;

Readonly my $FILMDATA_ROOT => path('../data/filmdata');

binmode( STDOUT, ":utf8" );
binmode( STDERR, ":utf8" );
$Data::Dumper::Sortkeys = 1;

my $img_count_ref =
  decode_json( $FILMDATA_ROOT->child('img_count.json')->slurp );

foreach my $filming (qw/ 1 2 /) {
  foreach my $category_type (qw/ subject ware /) {
    my $collection =
      ( $category_type eq 'ware' )
      ? 'wa'
      : 'sh';
    my $set    = "h${filming}";
    my $subset = "${set}_$collection";

    # file names
    my $zotero_name   = "zotero.${subset}.json";
    my $filmlist_name = "${subset}.expanded.json";
    my $out_name =
      ( $category_type eq 'ware' )
      ? "$subset.by_ware_id.merged.json"
      : "$subset.by_geo_id.merged.json";

    # target data structure
    my %by_id;

    # which category id to use für by_id?
    my $by_category_type =
      ( $category_type eq 'ware' )
      ? 'ware'
      : 'geo';

    # basic structure to iterate over all films is the filmlist file
    my $templist_ref =
      decode_json( $FILMDATA_ROOT->child($filmlist_name)->slurp );
    my $filmlist_ref;
    foreach my $entry_ref ( @{$templist_ref} ) {
      $filmlist_ref->{ $entry_ref->{film_id} } = $entry_ref;
    }

    # film sections from zotero
    my $zotero_ref = decode_json( $FILMDATA_ROOT->child($zotero_name)->slurp );

    # itereta of over all films
    my $category_id;
    foreach my $film_id ( sort keys %{$filmlist_ref} ) {

      # skip films which are online
      if (  $filmlist_ref->{$film_id}{online}
        and $filmlist_ref->{$film_id}{online} ne '' )
      {
        print "$film_id    \tis online\n";
        next;
      }

      # when information from zotero exists, use preferably that
      if ( $zotero_ref->{$film_id} ) {
        print "$film_id  \tfrom zotero\n";

        # all section defined for this film in zotero
        my @items = sort keys %{ $zotero_ref->{$film_id}{item} };

        # TODO is the following ok? _2 films do not start with 0001
        # add the entry of a continuation, if it is missing in zotero
        if ( not $items[0] =~ m;$film_id/000[12](/[RL])?$; ) {
          my $entry_ref = {
            location  => "film/$set/$collection/$film_id/0002",
            first_img => $filmlist_ref->{$film_id}{start_sig},
          };
          push( @{ $by_id{$category_id}{sections} }, $entry_ref );

          # TODO add to total_number_of_images?

        }

        foreach my $location (@items) {
          my %data = %{ $zotero_ref->{$film_id}{item}{$location} };

          # skip items with un-identified category
          next unless $data{$by_category_type};

          # title for the marker (not validated, not guaranteed
          # to cover the whole stretch of images up to the next marker
          ## TODO improve for English
          my $first_img = $data{title};

          $category_id = $data{$by_category_type}{id};
          print "  $category_id\n";

          my $entry_ref = {
            location  => $location,
            first_img => $first_img,
          };

          push( @{ $by_id{$category_id}{sections} }, $entry_ref );

          # compute totals
          if ( exists $data{number_of_images} ) {
            $by_id{$category_id}{total_number_of_images} +=
              $data{number_of_images};
          } else {
            warn "number_of_images missing for $location\n";
          }
        }    # $location
      }
      #
      # when there is no information from zotero, add the film "in toto" from
      # the filmlist entry
      else {
        print "$film_id  \tfrom filmlist\n";

        # add first image under the last category used
        my %section_entry = (
          location  => "film/$set/$collection/$film_id",
          first_img => $filmlist_ref->{$film_id}{start_sig},
        );
        push( @{ $by_id{$category_id}{sections} }, \%section_entry );

        # update total_number_of_images
        my $key = "/mnt/intares/film/$set/$collection/$film_id";
        my $number_of_images;
        if (defined $img_count_ref->{$key}) {
          $number_of_images = $img_count_ref->{$key};
        } else {
          warn "number of images for full film $key not found\n";
          $number_of_images = 0;
        }
        $by_id{$category_id}{total_number_of_images} +=
          $number_of_images;
      }
    }
    my $out_file = $FILMDATA_ROOT->child($out_name);
    print "$out_file written\n\n";
    $out_file->spew( encode_json( \%by_id ) );
  }
}

