#!/bin/env perl
# nbt, 15.7.2020

# create category overview pages from data/rdf/*.jsonld and
# data/klassdata/*.json

use strict;
use warnings;
use utf8;
binmode( STDOUT, ":encoding(UTF-8)" );

use lib './lib';

use Carp;
use Data::Dumper;
use HTML::Template;
use JSON;
use Path::Tiny;
use Readonly;
use Scalar::Util qw(looks_like_number reftype);
use YAML;
use ZBW::PM20x::Folder;
use ZBW::PM20x::Vocab;

Readonly my $WEB_ROOT        => path('../web.public/category');
Readonly my $KLASSDATA_ROOT  => path('../data/klassdata');
Readonly my $FOLDERDATA_ROOT => path('../data/folderdata');
Readonly my $TEMPLATE_ROOT   => path('../etc/html_tmpl');

my %PROV = (
  hwwa => {
    name => {
      en => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
      de => 'Hamburgisches Welt-Wirtschafts-Archiv (HWWA)',
    }
  },
);

my @LANGUAGES = qw/ de en /;

# TODO create and load external yaml
# TODO use prov as the first level?
my $definitions_ref = YAML::Load(<<'EOF');
geo:
  prov: hwwa
  title:
    en: Folders by Country Category System
    de: Mappen nach Ländersystematik
  result_file: geo_by_signature
  vocab: ag
  uri_field: country
  detail:
    subject:
      result_file: subject_folders
      vocab: je
#    ware
#      result_file: ware_folders
#      vocab: ip
subject:
  prov: hwwa
  title:
    en: Folders by Subject Category System
    de: Mappen nach Sachsystematik
  result_file: subject_by_signature
  vocab: je
  uri_field: category
  detail:
    geo:
      result_file: subject_folders
      vocab: ag
EOF

# data for all vocabularies
my %vocab_all = %{ ZBW::PM20x::Vocab::get_vocab_all() };

# set last_modified entries for all category types
set_last_modified();

# category overview pages
my ( $master_ref, $detail_ref );

# loop over category types
foreach my $category_type ( keys %{$definitions_ref} ) {
  my $def_ref = $definitions_ref->{$category_type};

  # master vocabulary reference
  my $master_vocab = $def_ref->{vocab};
  $master_ref = $vocab_all{$master_vocab};

  # loop over detail types
  foreach my $detail_type ( keys %{ $def_ref->{detail} } ) {

    # detail vocabulary reference
    my $detail_vocab =
      $def_ref->{detail}{$detail_type}{vocab};
    $detail_ref = $vocab_all{$detail_vocab};

    # count folders and add to master
    my ( $category_count, $total_folder_count ) =
      count_folders_per_category( $category_type, $detail_type );

    foreach my $lang (@LANGUAGES) {
      my @lines;
      my $title = $def_ref->{title}{$lang};
      my $provenance =
        $PROV{ $def_ref->{prov} }{name}{$lang};

      # some header information for the page
      my $backlinktitle =
        $lang eq 'en'
        ? 'Folders by Category system'
        : 'Mappen nach Systematik';
      my %tmpl_var = (
        "is_$lang"          => 1,
        "is_$category_type" => 1,
        title               => $title,
        etr                 => "category_overview/$category_type",
        modified            => $def_ref->{last_modified},
        backlink            => "../about.$lang.html",
        backlink_title      => $backlinktitle,
        provenance          => $provenance,
        category_count      => $category_count,
        folder_count        => $total_folder_count,
      );

      # read json input
      my $file =
        $KLASSDATA_ROOT->child( $def_ref->{result_file} . ".$lang.json" );
      my @categories =
        @{ decode_json( $file->slurp )->{results}->{bindings} };

      # main loop
      my $firstletter_old = '';
      foreach my $category (@categories) {

        # skip result if no folders exist
        next
          if not( exists $category->{shCountLabel}
          or exists $category->{countLabel} );

        # control break?
        my $firstletter = substr( $category->{signature}->{value}, 0, 1 );
        if ( $firstletter ne $firstletter_old ) {
          push( @lines,
            '',
            "### $master_ref->{subhead}{$firstletter}{$lang}"
              . "<a name='$firstletter'></a>",
            '' );
          $firstletter_old = $firstletter;
        }

        ##print Dumper $category; exit;
        my $category_uri = $category->{ $def_ref->{uri_field} }{value};
        my $id;
        if ( $category_uri =~ m/(\d{6})$/ ) {
          $id = $1;
        } else {
          croak "irregular category uri $category_uri";
        }
        my $label =
          ZBW::PM20x::Vocab::get_termlabel( $lang, $def_ref->{vocab}, $id, 1 );
        my $entry_note = (
          defined $master_ref->{id}{$id}{geoCategoryType}
          ? "$master_ref->{id}{$id}{geoCategoryType} "
          : ''
          )
          . '('
          . (
          defined $master_ref->{id}{$id}{foldersComplete}
            and $master_ref->{id}{$id}{foldersComplete} eq 'Y'
          ? ( $lang eq 'en' ? 'complete, ' : 'komplett, ' )
          : ''
          )
          . $master_ref->{id}{$id}{"${detail_type}FolderCount"}
          . ( $lang eq 'en' ? ' subject folders' : ' Sach-Mappen' ) . ')';

        # main entry
        my $siglink = ZBW::PM20x::Vocab::get_siglink( $master_vocab, $id );
        my $line =
            "- [$label](i/$id/about.$lang.html) $entry_note"
          . "<a name='$siglink'></a>";
        ## indent for Sondermappe
        if ( $label =~ m/ Sm\d/ and $firstletter ne 'q' ) {
          $line = "  $line";
        }
        push( @lines, $line );
      }

      # TODO for multiple details on one category page, this have to move one
      # level higher
      my $tmpl = HTML::Template->new(
        filename => $TEMPLATE_ROOT->child('category_overview.md.tmpl'),
        utf8     => 1
      );
      $tmpl->param( \%tmpl_var );
      ## q & d: add lines as large variable
      $tmpl->param( lines => join( "\n", @lines ), );

      my $out = $WEB_ROOT->child($category_type)->child("about.$lang.md");
      ##$out = path("/tmp/$category_type/about.$lang.md");
      $out->spew_utf8( $tmpl->output );
    }
  }
}

# individual category pages
foreach my $category_type ( keys %{$definitions_ref} ) {

  # master vocabulary reference
  my $master_vocab = $definitions_ref->{$category_type}{vocab};
  $master_ref = $vocab_all{$master_vocab};

  # loop over detail types
  foreach
    my $detail_type ( keys %{ $definitions_ref->{$category_type}{detail} } )
  {
    my $def_ref = $definitions_ref->{$category_type}->{detail}{$detail_type};

    # detail vocabulary reference
    my $detail_vocab = $def_ref->{vocab};
    $detail_ref = $vocab_all{$detail_vocab};

    foreach my $lang (@LANGUAGES) {

      # read json input (all folders for all categories)
      my $file =
        $FOLDERDATA_ROOT->child( $def_ref->{result_file} . ".$lang.json" );
      my @unsorted_entries =
        @{ decode_json( $file->slurp )->{results}->{bindings} };

      # sort entries by relevant notation
      my $key = "${category_type}Nta";
      my @entries =
        sort { $a->{$key}{value} cmp $b->{$key}{value} } @unsorted_entries;

      # main loop
      my $count_ref = {
        folder_count_first   => 0,
        document_count_first => 0,
      };
      my @lines;
      my $master_id_old   = '';
      my $detail_id_old   = '';
      my $firstletter_old = '';
      foreach my $entry (@entries) {
        ##print Dumper $entry;exit;

        # extract ids for master and detail from folder id
        my $folder_id;
        if ( $entry->{pm20}->{value} =~ m/(\d{6},\d{6})$/ ) {
          $folder_id = $1;
        }
        my ( $master_id, $detail_id ) =
          get_master_detail_ids( $category_type, $detail_type, $folder_id );

        my $label =
          ZBW::PM20x::Vocab::get_termlabel( $lang, $detail_vocab, $detail_id,
          1 );

        # first level control break - new category page
        if ( $master_id_old ne '' and $master_id ne $master_id_old ) {
          output_category_page( $lang, $category_type, $master_id_old, \@lines,
            $count_ref );
          @lines = ();
        }
        $master_id_old = $master_id;

        # second level control break (label starts with signature)
        my $firstletter = substr( $label, 0, 1 );
        if ( $firstletter ne $firstletter_old ) {

          # subheading
          my $subheading = $detail_ref->{subhead}{$firstletter}{$lang}
            || $detail_ref->{subhead}{$firstletter}{de};
          push( @lines, '', "### $subheading", '' );
          $firstletter_old = $firstletter;
        }

        # main entry
        my $uri          = $entry->{pm20}->{value};
        my $catpage_link = "../../../$detail_type/about.$lang.html#"
          . ZBW::PM20x::Vocab::get_siglink( $detail_vocab, $detail_id );
        my $entry_note =
            '(<a href="'
          . view_url( $lang, $uri )
          . '" target="_blank">'
          . $entry->{docs}->{value}
          . ( $lang eq 'en' ? ' documents' : ' Dokumente' ) . '</a>)' . ' (['
          . ( $lang eq 'en' ? 'folder'     : 'Mappe' )
          . "]($uri))";
        my $line = "- [$label]($catpage_link) $entry_note";

        # additional indent for Sondermappen
        # (label starts with notation - has also to deal with first element,
        # e.g., n Economy)
        if ( $label =~ m/ Sm\d/ and $firstletter ne 'q' ) {
          if ( get_firstsig($detail_id_old) ne get_firstsig($detail_id)
            and not $label =~ m/^[a-z]0/ )
          {
            ## insert non-linked intermediate item
            my $id_broader = $detail_ref->{id}{$detail_id}{broader};
            my $sig_label =
              ZBW::PM20x::Vocab::get_termlabel( $lang, $detail_vocab,
              $id_broader, 1 );
            push( @lines, "- [$sig_label]{.gray}" );
          }
          $line = "  $line";
        }
        $detail_id_old = $detail_id;
        push( @lines, $line );

        # statistics
        $count_ref->{folder_count_first}++;
        $count_ref->{document_count_first} += $entry->{docs}{value};
      }

      # output of last category
      output_category_page( $lang, $category_type, $master_id_old, \@lines,
        $count_ref );
    }
  }
}

############

sub output_category_page {
  my $lang          = shift or croak('param missing');
  my $category_type = shift or croak('param missing');
  my $id            = shift or croak('param missing');
  my $lines_ref     = shift or croak('param missing');
  my $count_ref     = shift or croak('param missing');

  my $provenance =
    $PROV{ $definitions_ref->{$category_type}{prov} }{name}{$lang};
  my $master_vocab = $definitions_ref->{$category_type}{vocab};
  my $title = ZBW::PM20x::Vocab::get_termlabel( $lang, $master_vocab, $id, 1 );
  my $backlinktitle =
    $lang eq 'en'
    ? 'Category Overview'
    : 'Systematik-Übersicht';
  my %tmpl_var = (
    "is_$lang" => 1,
    title      => $title,
    etr        => "category/$category_type/$master_ref->{id}{$id}{notation}",
    modified   => $definitions_ref->{$category_type}{last_modified},
    backlink   => "../../about.$lang.html",
    backlink_title  => $backlinktitle,
    provenance      => $provenance,
    folder_count1   => $count_ref->{folder_count_first},
    document_count1 => $count_ref->{document_count_first},
    scope_note      => $master_ref->{id}{$id}{scopeNote}{$lang},
  );

  if ( defined $master_ref->{id}{$id}{foldersComplete}
    and $master_ref->{id}{$id}{foldersComplete} eq 'Y' )
  {
    $tmpl_var{complete} = 1;
  }
  $count_ref->{folder_count_first}   = 0;
  $count_ref->{document_count_first} = 0;

  my $tmpl = HTML::Template->new(
    filename => $TEMPLATE_ROOT->child('category.md.tmpl'),
    utf8     => 1
  );
  $tmpl->param( \%tmpl_var );
  ## q & d: add lines as large variable
  $tmpl->param( lines => join( "\n", @{$lines_ref} ), );

  my $out_dir =
    $WEB_ROOT->child($category_type)->child('i')->child($id);
  ##$out_dir = path("/tmp/$category_type/i/$id");
  $out_dir->mkpath;
  my $out = $out_dir->child("about.$lang.md");
  $out->spew_utf8( $tmpl->output );

  return;
}

# should work for subject, ware and geo
sub count_folders_per_category {
  my $category_type = shift or croak('param missing');
  my $detail_type   = shift or croak('param missing');

  my %count_data;
  my $total_folder_count;

  # folder data
  # read json input (all folders for all categories)
  my $file = $FOLDERDATA_ROOT->child(
    $definitions_ref->{$category_type}{detail}{$detail_type}{result_file}
      . '.de.json' );
  my @folders =
    @{ decode_json( $file->slurp )->{results}->{bindings} };

  foreach my $folder (@folders) {
    my $folder_id;
    if ( $folder->{pm20}->{value} =~ m/(\d{6},\d{6})$/ ) {
      $folder_id = $1;
    }
    my ( $master_id, $detail_id ) =
      get_master_detail_ids( $category_type, $detail_type, $folder_id );

    $count_data{$master_id}{$detail_id}++;

  }
  foreach my $id ( keys %count_data ) {
    my $count = scalar( keys %{ $count_data{$id} } );
    $master_ref->{id}{$id}{"${detail_type}FolderCount"} = $count;
    $total_folder_count += $count;
  }
  my $category_count = scalar( keys %count_data );
  return $category_count, $total_folder_count;
}

sub view_url {
  my $lang       = shift or croak('param missing');
  my $folder_uri = shift or croak('param missing');

  my $viewer_stub =
    'https://dfg-viewer.de/show/?tx_dlf[id]=https://pm20.zbw.eu/mets/';

  my ( $collection, $folder_id );
  if ( $folder_uri =~ m;/(pe|co|sh|wa)/(\d{6}(,\d{6})?)$; ) {
    $collection = $1;
    $folder_id  = $2;
  }

  my $view_url =
      $viewer_stub
    . ZBW::PM20x::Folder::get_folder_hashed_path( $collection, $folder_id )
    . "/public.mets.$lang.xml";

  return $view_url;
}

sub get_firstsig {
  my $id = shift or croak('param missing');

  my $signature = $detail_ref->{id}{$id}->{notation};
  my $firstsig  = ( split( / /, $signature ) )[0];

  return $firstsig;
}

# set last modification of all category types
# to the maximum of the modification dates of the underlying vocabs
sub set_last_modified {

  foreach my $category_type ( keys %{$definitions_ref} ) {
    my $def_ref = $definitions_ref->{$category_type};

    # modification daté of the master
    my $last_modified = $vocab_all{ $def_ref->{vocab} }{modified};

    # iterate over details and replace date if later
    foreach my $detail_type ( keys %{ $def_ref->{detail} } ) {
      if ( $vocab_all{ $def_ref->{detail}{$detail_type}{vocab} }{modified}
        gt $last_modified )
      {
        $last_modified =
          $vocab_all{ $def_ref->{detail}{$detail_type}{vocab} }{modified};
      }
    }
    $def_ref->{last_modified} = $last_modified;
  }
  return;
}

sub get_master_detail_ids {
  my $category_type = shift or croak('param missing');
  my $detail_type   = shift or croak('param missing');
  my $folder_id     = shift or croak('param missing');

  $folder_id =~ m/^(\d{6}),(\d{6})$/
    or confess "irregular folder id $folder_id";

  my ( $master_id, $detail_id );
  if ( $category_type eq 'geo' and $detail_type eq 'subject' ) {
    $master_id = $1;
    $detail_id = $2;
  } elsif ( $category_type eq 'subject' and $detail_type eq 'geo' ) {
    $master_id = $2;
    $detail_id = $1;
  } else {
    croak "combination of category: $category_type"
      . " and detail: $detail_type not defined";
  }
  return ( $master_id, $detail_id );
}

