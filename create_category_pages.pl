#!/bin/env perl
# nbt, 15.7.2020

# create category overview pages from data/rdf/*.jsonld and
# data/klassdata/*.json

# TODO clean up mess
# - link directly to county/subject page from entries in overview pages
#   - catpage_link to be moved to the detail page heading (up arrow)
# - use check_missing_level for overview pages (needs tracking old id)
# - use master_detail_ids() for overview pages
# - all scope notes (add/prefer direct klassifikator fields)
# - for dedicated categories (B43), set "folders complete" if present
# POSTPONED
# - deeper hierarchies (too many forms beyond simple sub-Sm hierarchies)

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

# category overview pages
my ( $master_voc, $detail_voc );

# loop over category types
foreach my $category_type ( keys %{$definitions_ref} ) {
  my $def_ref = $definitions_ref->{$category_type};

  # master vocabulary reference
  my $master_vocab_name = $def_ref->{vocab};
  $master_voc = ZBW::PM20x::Vocab->new($master_vocab_name);

  # loop over detail types
  foreach my $detail_type ( keys %{ $def_ref->{detail} } ) {

    # detail vocabulary reference
    my $detail_vocab_name =
      $def_ref->{detail}{$detail_type}{vocab};
    $detail_voc = ZBW::PM20x::Vocab->new($detail_vocab_name);

    foreach my $lang (@LANGUAGES) {
      my @lines;
      my $title = $def_ref->{title}{$lang};
      my $provenance =
        $PROV{ $def_ref->{prov} }{name}{$lang};
      my $category_count     = 0;
      my $total_folder_count = 0;

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
        modified            => last_modified( $master_voc, $detail_voc ),
        backlink            => "../about.$lang.html",
        backlink_title      => $backlinktitle,
        provenance          => $provenance,
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
            "### "
              . $master_voc->subheading( $lang, $firstletter )
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
        my $label        = $master_voc->label( $lang, $id );
        my $signature    = $master_voc->signature($id);
        my $folder_count = $master_voc->folder_count( $category_type, $id );
        my $entry_note   = (
          ( $master_voc->geo_category_type($id) )
          ? $master_voc->geo_category_type($id) . ' '
          : ''
          )
          . '('
          . (
            ( $master_voc->folders_complete($id) )
          ? ( $lang eq 'en' ? 'complete, ' : 'komplett, ' )
          : ''
          )
          . $folder_count
          . ( $lang eq 'en' ? ' subject folders' : ' Sach-Mappen' ) . ')';

        # main entry
        my $siglink = $master_voc->siglink($id);
        my $line =
            "- [$signature $label](i/$id/about.$lang.html) $entry_note"
          . "<a name='$siglink'></a>";
        ## indent for Sondermappe
        if ( $signature =~ $SM_QR and $firstletter ne 'q' ) {

          # TODO check_missing_level
          $line = "  $line";
        }
        if ( $signature =~ $DEEP_SM_QR ) {

          # TODO check_missing_level
          $line = "  $line";
        }
        push( @lines, $line );
        $category_count++;
        $total_folder_count += $folder_count;
      }

      # TODO for multiple detail sections on one category page, this has to
      # move one level higher
      my $tmpl = HTML::Template->new(
        filename => $TEMPLATE_ROOT->child('category_overview.md.tmpl'),
        utf8     => 1
      );
      $tmpl->param( \%tmpl_var );
      ## q & d: add lines as large variable
      $tmpl->param(
        lines              => join( "\n", @lines ),
        category_count     => $category_count,
        total_folder_count => $total_folder_count,
      );

      my $out = $WEB_ROOT->child($category_type)->child("about.$lang.md");
      $out = path("$WEB_ROOT/$category_type/about.$lang.md");
      $out->spew_utf8( $tmpl->output );
    }
  }
}

# individual category pages
foreach my $category_type ( keys %{$definitions_ref} ) {

  # master vocabulary reference
  my $master_vocab_name = $definitions_ref->{$category_type}{vocab};
  $master_voc = ZBW::PM20x::Vocab->new($master_vocab_name);

  # loop over detail types
  foreach
    my $detail_type ( keys %{ $definitions_ref->{$category_type}{detail} } )
  {
    my $def_ref = $definitions_ref->{$category_type}->{detail}{$detail_type};

    # detail vocabulary reference
    my $detail_vocab_name = $def_ref->{vocab};
    $detail_voc = ZBW::PM20x::Vocab->new($detail_vocab_name);

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
        my $folder_numkey;
        if ( $entry->{pm20}->{value} =~ m/(\d{6},\d{6})$/ ) {
          $folder_numkey = $1;
        }
        my ( $master_id, $detail_id ) =
          get_master_detail_ids( $category_type, $detail_type, $folder_numkey );

        my $label     = $detail_voc->label( $lang, $detail_id );
        my $signature = $detail_voc->signature($detail_id);

        # first level control break - new category page
        if ( $master_id_old ne '' and $master_id ne $master_id_old ) {
          output_category_page( $lang, $category_type, $master_id_old, \@lines,
            $count_ref );
          @lines = ();
        }
        $master_id_old = $master_id;

        # second level control break
        my $firstletter = substr( $signature, 0, 1 );
        if ( $firstletter ne $firstletter_old ) {

          # subheading
          my $subheading = $detail_voc->subheading( $lang, $firstletter );
          push( @lines, '', "### $subheading", '' );
          $firstletter_old = $firstletter;
        }

        # main entry
        my $line         = '';
        my $uri          = $entry->{pm20}->{value};
        my $catpage_link = "../../../$detail_type/about.$lang.html#"
          . $detail_voc->siglink($detail_id);
        my $entry_note =
            '(<a href="'
          . view_url( $lang, $uri )
          . '" target="_blank">'
          . $entry->{docs}->{value}
          . ( $lang eq 'en' ? ' documents' : ' Dokumente' ) . '</a>)' . ' (['
          . ( $lang eq 'en' ? 'folder'     : 'Mappe' )
          . "]($uri))";

        # additional indent for Sondermappen
        if ( $signature =~ $SM_QR and $firstletter ne 'q' ) {
          check_missing_level( $lang, \@lines, $detail_voc, $detail_id,
            $detail_id_old, 1 );
          $line .= "  ";
        }

        # again, additional indent for subdivided Sondermappen
        if ( $signature =~ $DEEP_SM_QR ) {
          ## TODO fix with get_smsig and according broader
          check_missing_level( $lang, \@lines, $detail_voc, $detail_id,
            $detail_id_old, 2 );
          $line .= "  ";
        }

        $line .= "- [$signature $label]($catpage_link) $entry_note";
        push( @lines, $line );
        $detail_id_old = $detail_id;

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
  my $signature = $master_voc->signature($id);
  my $label     = $master_voc->label( $lang, $id );
  my $backlinktitle =
    $lang eq 'en'
    ? 'Category Overview'
    : 'Systematik-Übersicht';
  my %tmpl_var = (
    "is_$lang"      => 1,
    signature       => $signature,
    label           => $label,
    etr             => "category/$category_type/$signature",
    modified        => last_modified( $master_voc, $detail_voc ),
    backlink        => "../../about.$lang.html",
    backlink_title  => $backlinktitle,
    provenance      => $provenance,
    wdlink          => $master_voc->wdlink($id),
    folder_count1   => $count_ref->{folder_count_first},
    document_count1 => $count_ref->{document_count_first},
    scope_note      => $master_voc->scope_note( $lang, $id ),
  );

  if ( $master_voc->folders_complete($id) ) {
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
  $out_dir = path("$WEB_ROOT/$category_type/i/$id");
  $out_dir->mkpath;
  my $out = $out_dir->child("about.$lang.md");
  $out->spew_utf8( $tmpl->output );

  return;
}

sub view_url {
  my $lang       = shift or croak('param missing');
  my $folder_uri = shift or croak('param missing');

  my $viewer_stub =
    'https://dfg-viewer.de/show/?tx_dlf[id]=https://pm20.zbw.eu/mets/';

  my ( $collection, $folder_numkey );
  if ( $folder_uri =~ m;/(pe|co|sh|wa)/(\d{6}(,\d{6})?)$; ) {
    $collection    = $1;
    $folder_numkey = $2;
  }

  my $view_url =
      $viewer_stub
    . ZBW::PM20x::Folder::get_folder_hashed_path( $collection, $folder_numkey )
    . "/public.mets.$lang.xml";

  return $view_url;
}

sub get_master_detail_ids {
  my $category_type = shift or croak('param missing');
  my $detail_type   = shift or croak('param missing');
  my $folder_numkey = shift or croak('param missing');

  $folder_numkey =~ m/^(\d{6}),(\d{6})$/
    or confess "irregular folder id $folder_numkey";

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

sub check_missing_level {
  my $lang      = shift or croak('param missing');
  my $lines_ref = shift or croak('param missing');
  my $voc       = shift or croak('param missing');
  my $id        = shift or croak('param missing');
  my $id_old    = shift or croak('param missing');
  my $level     = shift or croak('param missing');

  # skip special signatue
  return if ( $voc->signature($id) =~ m/^[a-z]0/ );

  # skip if first part of signature is same as in last entry
  return
    if ( $voc->start_sig( $id_old, $level ) eq $voc->start_sig( $id, $level ) );

  ## insert non-linked intermediate item
  my $id_broader = $voc->broader($id);
  my $label      = $voc->label( $lang, $id_broader );
  my $signature  = $voc->signature($id_broader);
  my $line       = "- [$signature $label]{.gray}";

  # additional indent on deeper level
  if ( $level == 2 ) {
    $line = "  $line";
  }
  push( @{$lines_ref}, $line );

  return;
}

sub last_modified {
  my $master_voc = shift or croak('param missing');
  my $detail_voc = shift or croak('param missing');

  my $last_modified =
      $master_voc->modified() gt $detail_voc->modified()
    ? $master_voc->modified()
    : $detail_voc->modified();

  return $last_modified;
}
