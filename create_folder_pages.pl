#!/bin/env perl
# nbt, 2021-10-26

# creates the .md files for folders

# to be invoked with a param, either for
# - an extended folder id (e.g., pe/000012)
# - a collection id (e.g., pe)
# - 'ALL' (to (re-) create all collections)

use strict;
use warnings;
use utf8;

use lib './lib';

use Data::Dumper;
use Encode;
use HTML::Template;
use JSON;
use Path::Tiny;
use Readonly;
use YAML;
use ZBW::PM20x::Folder;

$Data::Dumper::Sortkeys = 1;

# used only for debugging
my $json = JSON->new;

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
    if ( $collection eq 'sh' or $collection eq 'wa' ) {
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

    # parse data for decription and jsonld
    my $folderdata = parse_folderdata( $lang, $collection, $folder );

    # add description meta tag
    $tmpl_var{meta_description} = add_meta_description( $lang, $folderdata );

    # add schema jsonld
    $tmpl_var{schema_jsonld} =
      add_schema_jsonld( $lang, $collection, $folderdata );

    # TODO is raw, partly invalid jsonld useful?
    ##$tmpl_var{jsonld}           = add_jsonld($folderdata_raw);

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
      my $values =
        join( '<br>', @{ get_activities( $lang, $folderdata_raw ) } );

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

sub parse_folderdata {
  my $lang       = shift || die "param missing";
  my $collection = shift || die "param missing";
  my $folder     = shift || die "param missing";

  my $folderdata_raw = $folder->get_folderdata_raw;

  my $folderdata;
  my $extension = "";

  # set default name for "about"
  $folderdata->{name} = $folder->get_folderlabel($lang);

  if ( get_wd_uri($folderdata_raw) ) {
    if ( $collection eq 'pe' or $collection eq 'co' ) {

      # uri of the person or organization item
      $folderdata->{wikidata} = get_wd_uri($folderdata_raw);
    } else {
      $folderdata->{wikidata_folder_item} = get_wd_uri($folderdata_raw);
    }
  }

  # dates (for pe and co)
  foreach my $field (qw/ birthDate deathDate foundingDate dissolutionDate/) {
    if ( my $date = $folderdata_raw->{$field} ) {
      $date =~ s/(.*)?T00:00:00$/$1/;
      $folderdata->{$field} = $date;
    }
  }

  if ( $collection eq 'pe' ) {
    ##print Dumper $folderdata_raw;
    my $name = $folderdata->{name};
    if ( $name =~ m/^(.*)?, (.*)$/ and $name =~ m/^</ ) {
      $folderdata->{name} = "$2 $1";
    }

    my $from_to = $folderdata_raw->{dateOfBirthAndDeath};
    if ($from_to) {
      $extension = $from_to;
    }

    # for description property
    my @desc_parts;

    # hasOccupation entry has insufficient and invalid schema.org markup, can
    # be used only for description
    if ( $lang eq 'de' and $folderdata_raw->{hasOccupation} ) {
      push( @desc_parts, $folderdata_raw->{hasOccupation} );
    }

    if ( $folderdata_raw->{activity} ) {
      my $activities =
        join( ', ', @{ get_activities( $lang, $folderdata_raw ) } );
      if ($from_to) {
        $extension = "$extension; $activities";
      } else {
        $extension = $activities;
      }
      push( @desc_parts, "$activities" );
    }
    $folderdata->{foldername} = "$folderdata->{name} ($extension)";

    if ( $folderdata_raw->{nationality} ) {
      foreach my $field_ref ( @{ $folderdata_raw->{nationality} } ) {
        next unless $field_ref->{'@language'} eq $lang;
        $folderdata->{nationality} = {
          '@type' => 'Country',
          name    => $field_ref->{'@value'},
        };
      }
    }

    # pretty description
    if ( scalar(@desc_parts) gt 1 ) {
      $folderdata->{description} = "$desc_parts[0]. ($desc_parts[1])";
    } else {
      $folderdata->{description} = $desc_parts[0];
    }
  }

  if ( $collection eq 'co' ) {
    ##print Dumper $folderdata_raw;
    my $from_to = $folderdata_raw->{fromTo};
    if ($from_to) {
      $extension = $from_to;
    }
    if ( $folderdata_raw->{location} ) {
      ## use only first location
      my @locations = get_field_values( $lang, $folderdata_raw, 'location' );
      $folderdata->{location} = {
        '@type' => 'Place',
        name    => $locations[0],
      };
      ## create/extend extension
      if ($from_to) {
        $extension = "$extension; ";
      }
      $extension .= join( ', ', @locations );
    }
    $folderdata->{foldername} = "$folderdata->{name} ($extension)";

    if ( $folderdata_raw->{industry} ) {
      my @industries = get_field_values( $lang, $folderdata_raw, 'industry' );
      $folderdata->{description} = join( ', ', @industries );
    }
  }

  if ( $collection eq 'sh' ) {
    $folderdata->{name} =~ m/^(.*)? : (.*)$/;
    $folderdata->{name}       = $1;
    $folderdata->{foldername} = $folder->get_folderlabel($lang);
    if ( get_wd_uri( $folderdata_raw->{country} ) ) {
      $folderdata->{wikidata} = get_wd_uri( $folderdata_raw->{country} );
    }
  }

  if ( $collection eq 'wa' ) {
    $folderdata->{name} =~ m/^(.*)? : (.*)$/;
    my $ware = $1;
    my $geo  = $2;
    $folderdata->{name} = $ware;
    if ( $geo =~ m/^(Welt|World)$/ ) {
      $folderdata->{foldername} = $ware;
    } else {
      $folderdata->{foldername} = "$ware in $geo";
    }
    if ( get_wd_uri( $folderdata_raw->{ware} ) ) {
      $folderdata->{wikidata} = get_wd_uri( $folderdata_raw->{ware} );
    }
  }
  return $folderdata;
}

sub add_meta_description {
  my $lang       = shift || die "param missing";
  my $folderdata = shift || die "param missing";

  my $desc = (
    $lang eq 'en'
    ? "Dossier about $folderdata->{foldername}"
    : "Dossier zu $folderdata->{foldername}"
  );
  $desc .= (
    $lang eq 'en'
    ? ". From German and international press, 1908-1949."
    : ". Aus deutscher und internationaler Presse, 1908-1949."
  );

  ##print "$desc\n";
  return $desc;
}

sub add_schema_jsonld {
  my $lang       = shift || die "param missing";
  my $collection = shift || die "param missing";
  my $folderdata = shift || die "param missing";

  my %schema_type = (
    pe => "Person",
    co => "Organization",
    sh => "Country",
    wa => "ProductGroup"
  );

  my $schema_data_ref = {
    '@type'  => "CreativeWork",
    name     => $folderdata->{foldername},
    isPartOf => {
      '@type' => 'Collection',
      name    => (
        $lang eq 'en'
        ? '20th Century Press Archives'
        : 'Pressearchiv 20. Jahrhundert'
      ),
      sameAs => 'http://www.wikidata.org/entity/Q36948990',
    },
  };
  my $about = { '@type' => $schema_type{$collection}, };

  foreach my $prop (
    qw / name description nationality birthDate deathDate foundingDate dissolutionDate location /
    )
  {
    if ( $folderdata->{$prop} ) {
      $about->{$prop} = $folderdata->{$prop};
    }
  }

  if ( $collection eq 'pe' or $collection eq 'co' ) {
    $about->{name} = $folderdata->{name};
    if ( $folderdata->{wikidata} ) {
      $about->{sameAs} = $folderdata->{wikidata};
    }
  }
  if ( $collection eq 'sh' or $collection eq 'wa' ) {
    if ( $folderdata->{wikidata_folder_item} ) {
      $schema_data_ref->{sameAs} = $folderdata->{wikidata_folder_item};
    }
    if ( $folderdata->{wikidata} ) {
      $about->{sameAs} = $folderdata->{wikidata};
    }
    ## replace Country with City
    if ( $folderdata->{name} =~ m/(Hamburg|Berlin)/ ) {
      $about->{'@type'} = 'City';
    }
  }

  $schema_data_ref->{about} = $about;

  my $schema_ld = {
    '@context' => 'https://schema.org/',
    '@graph'   => [$schema_data_ref],
  };

  # will be utf8-encoded later in template
  return decode( 'UTF-8', encode_json($schema_ld) );
}

sub add_jsonld {
  my $folderdata_raw = shift || die "param missing";

  my $ld = {
    '@context' => 'https://pm20.zbw.eu/schema/context.jsonld',
    '@graph'   => [$folderdata_raw],
  };

  # will be utf8-encoded later in template
  return decode( 'UTF-8', encode_json($ld) );
}

sub get_wd_uri {
  my $folderdata_raw = shift || die "param missing";

  my $uri;
  foreach my $ref ( @{ $folderdata_raw->{exactMatch} } ) {
    next unless $ref->{'@id'} =~ m{wikidata.org/entity/Q\d+$};
    $uri = $ref->{'@id'};
  }
  return $uri;
}

sub get_activities {
  my $lang           = shift || die "param missing";
  my $folderdata_raw = shift || die "param missing";

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
  return \@field_values;
}

