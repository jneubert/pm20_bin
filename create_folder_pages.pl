#!/bin/env perl
# nbt, 2021-10-26

# creates the .md files for folders

# can be invoked either by
# - an extended folder id (e.g., pe/000012)
# - a collection id (e.g., pe)
# - 'ALL' (to (re-) create all collections)

use strict;
use warnings;
use utf8;

use lib './lib';

use Data::Dumper;
use HTML::Template;
use JSON;
use Path::Tiny;
use Readonly;
use YAML;
use ZBW::PM20x::Folder;

$Data::Dumper::Sortkeys = 1;

Readonly my $FOLDER_DATA    => path('/pm20/data/rdf/pm20.extended.jsonld');
Readonly my $FOLDER_ROOT    => $ZBW::PM20x::Folder::FOLDER_ROOT;
Readonly my $URL_DATA_ROOT  => path('/pm20/data/folderdata');
Readonly my $FOLDER_WEBROOT => path('/pm20/web/folder');
Readonly my %TITLE          => %{ YAML::LoadFile('archive_titles.yaml') };
Readonly my @COLLECTIONS    => qw/ co pe sh wa /;
Readonly my @LANGUAGES      => qw/ en de /;

my $tmpl = HTML::Template->new(
  filename => '../etc/html_tmpl/folder.md.tmpl',
  utf8     => 1
);

my %collection_ids;

our @company_relations = (
  {
    field => 'parentOrganization',
    label => {
      en => 'Parent organization',
      de => 'Übergeordnet',
    },
  },
  {
    field => 'subOrganization',
    label => {
      en => 'Subsidiary',
      de => 'Untergeordnet',
    },
  },
  {
    field => 'precedingCorporateBody',
    label => {
      en => 'Preceeding org.',
      de => 'Vorgänger',
    },
  },
  {
    field => 'succeedingCorporateBody',
    label => {
      en => 'Succeeding org.',
      de => 'Nachfolger',
    },
  },
  {
    field => 'relatedCorporateBody',
    label => {
      en => 'Related org.',
      de => 'Verwandte Org.',
    },
  },
);

# check arguments
if ( scalar(@ARGV) == 1 ) {
  if ( $ARGV[0] =~ m:^(co|pe|wa|sh)$: ) {
    my $collection = $1;
    load_ids( \%collection_ids );
    mk_collection($collection);
  } elsif ( $ARGV[0] =~ m:^(co|pe)/(\d{6}): ) {
    my $collection = $1;
    my $folder_nk  = $2;
    mk_folder( $collection, $folder_nk );
  } elsif ( $ARGV[0] =~ m:^(sh|wa)/(\d{6},\d{6})$: ) {
    my $collection = $1;
    my $folder_nk  = $2;
    mk_folder( $collection, $folder_nk );
  } elsif ( $ARGV[0] eq 'ALL' ) {
    load_ids( \%collection_ids );
    mk_all();
  } else {
    &usage;
  }
} else {
  &usage;
}

####################

sub mk_all {

  foreach my $collection (@COLLECTIONS) {
    mk_collection($collection);
  }
}

sub mk_collection {
  my $collection = shift or die "param missing";

  my @pages_for_sitemap;
  my $i = 0;
  foreach my $folder_nk ( sort @{ $collection_ids{$collection} } ) {
    $i++;
    ##next if ($i < 8100);

    mk_folder( $collection, $folder_nk, \@pages_for_sitemap );

    # debug and progress info
    if ( $i % 100 == 0 ) {
      print "$i folders done (up to $collection/$folder_nk)\n";
    }
  }

  # write a list of pages to index for Google etc.
  # (used in create_sitemap.pl
  $URL_DATA_ROOT->child("${collection}_for_sitemap.lst")
    ->spew( join( "\n", @pages_for_sitemap ) );
}

sub mk_folder {
  my $collection            = shift || die "param missing";
  my $folder_nk             = shift || die "param missing";
  my $pages_for_sitemap_ref = shift;

  my $folder = ZBW::PM20x::Folder->new( $collection, $folder_nk );

  # check if folder dir exists in the source tree
  my $rel_path  = $folder->get_folder_hashed_path();
  my $full_path = $FOLDER_ROOT->child($rel_path);
  if ( $folder->get_doc_counts and not -d $full_path ) {
    die "$full_path does not exist\n";
  }

  # create folder dir (including hashed level) in the web tree
  my $folder_dir = $FOLDER_WEBROOT->child($rel_path);
  $folder_dir->mkpath;

  # TODO type public/intern (currently not necessary)
  my $type           = 'dummy';
  my $folderdata_raw = $folder->get_folderdata_raw;
  #
  # wikidata link (use only first one)
  my $wdlink;
  for my $exact_match ( @{ $folderdata_raw->{exactMatch} } ) {
    next if $wdlink;
    my $uri = $exact_match->{'@id'};
    next unless $uri =~ m/wikidata\.org/;
    $wdlink = $uri;
  }

  # main loop
  foreach my $lang (@LANGUAGES) {
    my $label            = $folder->get_folderlabel($lang);
    my $collection_title = $TITLE{collection}{$collection}{$lang};
    my $backlink         = "../../about.$lang.html";
    my $backlink_title =
      $collection_title . ( $lang eq 'de' ? '-Mappen' : ' folders' );
    if ( $collection eq 'sh' ) {
      $backlink = "../../../../../../category/about.$lang.html";
      $backlink_title =
        $lang eq 'de' ? 'Mappen nach Systematik' : 'Folders by category system';
    }
    if ( $collection eq 'wa' ) {
      $backlink = '../../' . $backlink;
    }

    my %tmpl_var = (
      "is_$lang"     => 1,
      provenance     => $TITLE{provenance}{hh}{$lang},
      coll           => $collection_title,
      label          => $label,
      folder_uri     => $folder->get_folder_uri,
      dfgview_url    => $folder->get_dfgview_url,
      iiifview_url   => $folder->get_iiifview_url,
      fid            => "$collection/$folder_nk",
      backlink       => $backlink,
      backlink_title => $backlink_title,
      modified       => $folder->get_modified,
      doc_counts     => $folder->format_doc_counts($lang) || undef,
    );

    # add description meta tag
    $tmpl_var{meta_description} =
      add_meta_description( $lang, $collection, $folderdata_raw );

    if ($wdlink) {
      $tmpl_var{wdlink} = $wdlink;
    }

    if ( $folderdata_raw->{temporal} ) {
      $tmpl_var{holdings} = join( '<br>', @{ $folderdata_raw->{temporal} } );
    }
    if ( $collection eq 'pe' or $collection eq 'co' ) {
      $tmpl_var{from_to} =
        ( $folderdata_raw->{dateOfBirthAndDeath} || $folderdata_raw->{fromTo} );
      $tmpl_var{gnd}       = $folderdata_raw->{gndIdentifier};
      $tmpl_var{signature} = $folderdata_raw->{notation};
    }

    if ( $folderdata_raw->{activity} ) {
      my @field_values;
      foreach my $field_ref ( @{ $folderdata_raw->{activity} } ) {
        my @entry;
        foreach my $part (qw/ location about /) {
          if ( not $field_ref->{$part} ) {
            warn "missing activity $part", Dumper $field_ref;
            next;
          }
          foreach my $subfield_ref ( @{ $field_ref->{$part} } ) {
            next unless $subfield_ref->{'@language'} eq $lang;
            push( @entry, $subfield_ref->{'@value'} );
          }
        }
        push( @field_values, join( ' - ', @entry ) );
      }
      my $values = join( '<br>', @field_values );

      $tmpl_var{activity} = $values;
    }
    if ( $folderdata_raw->{nationality} ) {
      $tmpl_var{nationality} =
        get_field_values( $lang, $folderdata_raw, 'nationality' );
    }
    if ( $folderdata_raw->{hasOccupation} and $lang eq 'de' ) {
      $tmpl_var{occupation} = $folderdata_raw->{hasOccupation};
    }

    if ( $folderdata_raw->{note} and $lang eq 'de' ) {
      my @notes = @{ $folderdata_raw->{note} };
      $tmpl_var{note} = join( "<br>", @notes );
    }

    $tmpl_var{company_relations_loop} = get_company_relations( $lang, $folder );
    if ( $folderdata_raw->{location} ) {
      $tmpl_var{location} =
        get_field_values( $lang, $folderdata_raw, 'location' );
    }
    if ( $folderdata_raw->{industry} ) {
      $tmpl_var{industry} =
        get_field_values( $lang, $folderdata_raw, 'industry' );
    }
    if ( $folderdata_raw->{organizationType} ) {
      $tmpl_var{organization_type} =
        get_field_values( $lang, $folderdata_raw, 'organizationType' );
    }

    $tmpl->clear_params;
    $tmpl->param( \%tmpl_var );
    ##print Dumper \%tmpl_var;

    # write  file for the folder
    my $fn = write_page( $type, $lang, $folder, $tmpl );

    # collect URLs of pages to add in sitemap
    if ( $tmpl_var{'doc_counts'} and $pages_for_sitemap_ref ) {
      $fn =~ s/\.md$/.html/;
      $fn =~ s|/pm20/web/|./|;
      push( @{$pages_for_sitemap_ref}, "$fn" );
    }

  }
}

sub load_ids {
  my $coll_id_ref = shift;

  # create a list of numerical keys for each collection
  my $data = decode_json( $FOLDER_DATA->slurp );
  foreach my $entry ( @{ $data->{'@graph'} } ) {
    $entry->{identifier} =~ m/^(co|pe|sh|wa)\/(\d{6}(?:,\d{6})?)$/;
    push( @{ $coll_id_ref->{$1} }, $2 );
  }
}

sub usage {
  print "Usage: $0 {folder-id}|{collection}|ALL\n";
  exit 1;
}

sub write_page {
  my $type   = shift || die "param missing";
  my $lang   = shift || die "param missing";
  my $folder = shift || die "param missing";
  my $tmpl   = shift || die "param missing";

  my $page_dir = $folder->get_folder_hashed_path();
  $page_dir = $FOLDER_WEBROOT->child($page_dir);
  my $page_file = $page_dir->child("about.$lang.md");

  # remove blank lines (necessary for pipe tables)
  # within fenced block
  my $lines = $tmpl->output();
  $lines =~ m/\A(.*?::: .*?\n)(.*)(\n:::\n.*)\z/ms;
  my $start  = $1;
  my $fenced = $2;
  my $end    = $3;
  $fenced =~ s/\n+/\n/mg;
  $lines = "$start$fenced$end";

  $page_file->spew_utf8($lines);
  ##print "written $page_file\n";

  return $page_file;
}

sub get_field_values {
  my $lang           = shift || die "param missing";
  my $folderdata_raw = shift || die "param missing";
  my $field          = shift || die "param missing";

  my @field_values;
  foreach my $field_ref ( @{ $folderdata_raw->{$field} } ) {
    next unless $field_ref->{'@language'} eq $lang;
    push( @field_values, $field_ref->{'@value'} );
  }

  my $values = join( '; ', @field_values );
  return $values;
}

sub get_company_relations {
  my $lang   = shift || die "param missing";
  my $folder = shift || die "param missing";

  my @field_entries;
  my $folderdata_raw = $folder->get_folderdata_raw;
  foreach my $field_ref (@company_relations) {
    my $field_name = $field_ref->{field};
    next unless $folderdata_raw->{$field_name};

    foreach my $occ ( @{ $folderdata_raw->{$field_name} } ) {
      my $folder2 = ZBW::PM20x::Folder->new_from_uri( $occ->{url} );
      my $path =
        $folder->get_relpath_to_folder($folder2)->child("/about.$lang.html");
      my %entry = (
        field_label => $field_ref->{label}{$lang},
        name        => $occ->{name},
        url         => "$path",
      );
      push( @field_entries, \%entry );
    }
  }
  return \@field_entries;
}

sub add_meta_description {
  my $lang           = shift || die "param missing";
  my $collection     = shift || die "param missing";
  my $folderdata_raw = shift || die "param missing";

  print Dumper $folderdata_raw;

  my ( $desc, $label );
  my $ext = "";

  if ( $collection eq 'pe' ) {
    my $fullname = $folderdata_raw->{prefLabel};
    if ( $fullname =~ m/^(.*)?, (.*)$/ ) {
      $label = "$2 $1";
    }
    my $from_to = $folderdata_raw->{dateOfBirthAndDeath};
    if ($from_to) {
      $ext = $from_to;
    }
    if ( $folderdata_raw->{activity} ) {
      if ($from_to) {
        $ext = "$ext; ";
      }
      foreach my $field_ref ( @{ $folderdata_raw->{activity}[0]{location} } ) {
        next unless $field_ref->{'@language'} eq $lang;
        $ext .= "$field_ref->{'@value'}, ";
      }
    }
    if ( $folderdata_raw->{activity} ) {
      foreach my $field_ref ( @{ $folderdata_raw->{activity}[0]{about} } ) {
        next unless $field_ref->{'@language'} eq $lang;
        $ext .= "$field_ref->{'@value'}, ";
      }
    }
  }

  if ( $collection eq 'co' ) {
    $label = $folderdata_raw->{prefLabel};
    my $from_to = $folderdata_raw->{fromTo};
    if ($from_to) {
      $ext = $from_to;
    }
    if ( $folderdata_raw->{location} ) {
      if ($from_to) {
        $ext = "$ext; ";
      }
      foreach my $field_ref ( @{ $folderdata_raw->{location} } ) {
        next unless $field_ref->{'@language'} eq $lang;
        $ext .= "$field_ref->{'@value'}, ";
      }
    }
  }

  if ( $collection eq 'sh' ) {
    foreach my $field_ref ( @{ $folderdata_raw->{prefLabel} } ) {
      next unless $field_ref->{'@language'} eq $lang;
      $field_ref->{'@value'} =~ m/^(.*)? : (.*)$/;
      $label = "'$2' in $1";
    }
  }

  if ( $collection eq 'wa' ) {
    foreach my $field_ref ( @{ $folderdata_raw->{prefLabel} } ) {
      next unless $field_ref->{'@language'} eq $lang;
      $field_ref->{'@value'} =~ m/^(.*)? : (.*)$/;
      my $ware = $1;
      my $geo  = $2;
      if ( $geo =~ m/^(Welt|World)$/ ) {
        $label = $ware;
      } else {
        $label = "$ware in $geo";
      }
    }
  }

  if ( $ext eq "" ) {
    $desc = $label;
  } else {
    $ext =~ s/(.*)?, $/$1/;
    $desc = "$label ($ext)";
  }
  $desc = (
    $lang eq 'en'
    ? "Newspaper articles about $desc"
    : "Zeitungsartikel zu $desc"
  );
  $desc .= (
    $lang eq 'en'
    ? ". From German and international press, 1908-1949"
    : ". Aus deutscher und internationaler Presse, 1908-1949"
  );

  print "$desc\n";
  return $desc;
}
