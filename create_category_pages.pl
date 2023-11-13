#!/bin/env perl
# nbt, 15.7.2020

# create category overview pages from data/rdf/*.jsonld and
# data/klassdata/*.json

# TODO clean up mess
# - use check_missing_level for overview pages (needs tracking old id)
# - use master_detail_ids() for overview pages
# - all scope notes (add/prefer direct klassifikator fields)
# - for dedicated categories (B43), set "folders complete" if present
# POSTPONED
# - deeper hierarchies (too many forms beyond simple sub-Sm hierarchies)

use strict;
use warnings;
use utf8;

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

binmode( STDOUT, ":encoding(UTF-8)" );

##Readonly my $WEB_ROOT        => path('/tmp/category');
Readonly my $WEB_ROOT        => path('../web/category');
Readonly my $KLASSDATA_ROOT  => path('../data/klassdata');
Readonly my $FOLDERDATA_ROOT => path('../data/folderdata');
Readonly my $TEMPLATE_ROOT   => path('html_tmpl');
Readonly my $TO_ROOT         => path('../../../..');

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
  vocab: geo
  uri_field: country
  detail:
    subject:
      result_file: subject_folders
      vocab: subject
      title:
        en: Subject archives
        de: Sacharchiv
    ware:
      result_file: ware_folders
      vocab: ware
      title:
        en: Commodities/wares archives
        de: Warenarchiv
subject:
  prov: hwwa
  title:
    en: Folders by Subject Category System
    de: Mappen nach Sachsystematik
  result_file: subject_by_signature
  vocab: subject
  uri_field: category
  detail:
    geo:
      result_file: subject_folders
      vocab: geo
      title:
        en: Countries-subject archives
        de: Länder-Sacharchiv
ware:
  prov: hwwa
  title:
    en: Folders by Commodity/ware Category System
    de: Mappen nach Warensystematik
  result_file: ware_by_signature
  vocab: ware
  uri_field: category
  detail:
    geo:
      result_file: ware_folders
      vocab: geo
      title:
        en: Commodities/wares archives
        de: Warenarchiv
EOF

my %linktitle = (
  about_hint => {
    de => 'über',
    en => 'about',
  },
  all_about_hint => {
    de => 'Alles über',
    en => 'All about',
  },
  folder => {
    de => 'Mappe',
    en => 'folder',
  },
  documents => {
    de => 'Dokumente',
    en => 'documents',
  },
  subject_cat => {
    de => '(in der ganzen Welt)',
    en => '(all over the world)',
  },
  geo_cat => {
    de => '(alle Mappen)',
    en => '(all folders)',
  },
  ware_cat => {
    de => '(XXX in der ganzen Welt)',
    en => '(xXX all over the world)',
  },
  subject_sys => {
    de => 'Sachsystematik',
    en => 'Subject category system',
  },
  ware_sys => {
    de => 'Warensystematik',
    en => 'Ware category system',
  },
  geo_sys => {
    de => 'Ländersystematik',
    en => 'Country category system',
  },
);

# category overview pages
my ( $master_voc, $detail_voc );

# loop over category types
foreach my $category_type ( sort keys %{$definitions_ref} ) {
  my $def_ref = $definitions_ref->{$category_type};

  # master vocabulary reference
  my $master_vocab_name = $def_ref->{vocab};
  $master_voc = ZBW::PM20x::Vocab->new($master_vocab_name);

  # loop over detail types
  my %total_folder_count;
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
      my $category_count = 0;

      # some header information for the page
      my $backlinktitle =
        $lang eq 'en'
        ? 'Folders by Category system'
        : 'Mappen nach Systematik';
      my %tmpl_var = (
        "is_$lang"          => 1,
        "is_$category_type" => 1,
        title               => $title,
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
      my $firstletter     = '';
      my $firstletter_old = '';
      foreach my $category (@categories) {

        # skip result if no folders exist
        next
          if not( exists $category->{shCountLabel}
          or exists $category->{waCountLabel}
          or exists $category->{countLabel} );

        # control break?
        $firstletter =
          $category_type eq 'ware'
          ? substr( $category->{categoryLabel}->{value}, 0, 1 )
          : substr( $category->{signature}->{value},     0, 1 );
        if ( $firstletter ne $firstletter_old ) {
          my $subhead =
              $category_type eq 'ware'
            ? $firstletter
            : $master_voc->subheading( $lang, $firstletter );
          push( @lines, '', "### $subhead <a name='$firstletter'></a>", '' );
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
        my $label     = $master_voc->label( $lang, $id );
        my $signature = $master_voc->signature($id);

        my $folder_count =
          $master_voc->folder_count( $category_type, $detail_type, $id ) || 0;
        my $count_label =
          $category_type eq 'ware'
          ? ( $lang eq 'en' ? ' ware folders'    : ' Waren-Mappen' )
          : ( $lang eq 'en' ? ' subject folders' : ' Sach-Mappen' );

        my $entry_body = "$folder_count $count_label"
          . (
            ( $master_voc->folders_complete($id) )
          ? ( $lang eq 'en' ? ' (complete)' : ' (komplett)' )
          : ''
          );

        # q&d extension for geo categories
        if ( $category_type eq 'geo' ) {
          $entry_body =
            ( $master_voc->folder_count( $category_type, 'subject', $id ) || 0 )
            . ( $lang eq 'en' ? ' subject folders' : ' Sach-Mappen' )
            . (
              ( $master_voc->folders_complete($id) )
            ? ( $lang eq 'en' ? ' (complete)' : ' (komplett)' )
            : ''
            )
            . ', '
            . ( $master_voc->folder_count( $category_type, 'ware', $id ) || 0 )
            . ( $lang eq 'en' ? ' ware folders' : ' Waren-Mappen' );
        }

        my $entry_note = (
          ( $master_voc->geo_category_type($id) )
          ? $master_voc->geo_category_type($id) . ' '
          : ''
        ) . "($entry_body)";

        # main entry
        my $siglink = $master_voc->siglink($id);
        my $entry_label =
          $category_type eq 'ware' ? $label : "$signature $label";
        my $line =
            "- [$entry_label](i/$id/about.$lang.html) $entry_note"
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
        if ( $lang eq 'en' ) {
          $total_folder_count{$detail_type} += $folder_count || 0;
        }
      }

      # for overview pages, which have only one level, we are done here
      my $tmpl = HTML::Template->new(
        filename => $TEMPLATE_ROOT->child('category_overview.md.tmpl'),
        utf8     => 1
      );
      $tmpl->param( \%tmpl_var );
      ## q & d: add lines as large variable
      $tmpl->param(
        lines          => join( "\n", @lines ),
        category_count => $category_count,
      );

      foreach my $detail_type ( keys %{ $def_ref->{detail} } ) {
        $tmpl->param( "${detail_type}_total_folder_count" =>
            $total_folder_count{$detail_type}, );
      }
      my $out = $WEB_ROOT->child($category_type)->child("about.$lang.md");
      $out = path("$WEB_ROOT/$category_type/about.$lang.md");
      $out->spew_utf8( $tmpl->output );

      $firstletter     = '';
      $firstletter_old = '';
    }
  }
}

# individual category pages
foreach my $category_type ( sort keys %{$definitions_ref} ) {
  ##next unless $category_type eq 'ware';
  print "\ncategory_type: $category_type\n";

  # master vocabulary reference
  my $master_vocab_name = $definitions_ref->{$category_type}{vocab};
  $master_voc = ZBW::PM20x::Vocab->new($master_vocab_name);

  foreach my $lang (@LANGUAGES) {
    print "  lang: $lang\n";

    my %category_data;
    my @lines;
    my $count_ref;

    # loop over detail types
    my @detail_types =
      sort keys %{ $definitions_ref->{$category_type}{detail} };
    foreach my $detail_type (@detail_types) {
      print "    detail_type $detail_type\n";
      my $def_ref = $definitions_ref->{$category_type}->{detail}{$detail_type};
      my $detail_title = $def_ref->{title}{$lang};

      # detail vocabulary reference
      my $detail_vocab_name = $def_ref->{vocab};
      $detail_voc = ZBW::PM20x::Vocab->new($detail_vocab_name);

      # read json input (all folders for all categories)
      my $file =
        $FOLDERDATA_ROOT->child( $def_ref->{result_file} . ".$lang.json" );
      my @unsorted_entries =
        @{ decode_json( $file->slurp )->{results}->{bindings} };

      # sort entries by relevant notation (or label)
      my @entries;
      if ( $category_type eq 'ware' ) {
        @entries =
          sort {
               $a->{'wareLabel'}{value} cmp $b->{'wareLabel'}{value}
            or $a->{'geoNtaLong'}{value} cmp $b->{'geoNtaLong'}{value}
          } @unsorted_entries;
##      print Dumper \@entries; exit;
      } else {
        my $key = "${category_type}NtaLong";
        @entries =
          sort { $a->{$key}{value} cmp $b->{$key}{value} } @unsorted_entries;
      }

      # main loop - an entry is a folder
      my $master_id_old   = '';
      my $detail_id_old   = '';
      my $firstletter     = '';
      my $firstletter_old = '';
      foreach my $entry (@entries) {

        # extract ids for master and detail from folder id
        my ( $folder_nk, $collection );
        if ( $entry->{pm20}->{value} =~ m/(sh|wa)\/(\d{6},\d{6})$/ ) {
          $collection = $1;
          $folder_nk  = $2;
        }
        my $folder = ZBW::PM20x::Folder->new( $collection, $folder_nk );

        my ( $master_id, $detail_id ) =
          get_master_detail_ids( $category_type, $detail_type, $folder_nk );

        my $label     = $detail_voc->label( $lang, $detail_id );
        my $signature = $detail_voc->signature($detail_id);

        # debug
        if ( $master_id eq '' or $master_id ne $master_id_old ) {
          print '      ',    ## $master_voc->signature($master_id), ' ',
            $master_voc->label( $lang, $master_id ), "\n";
        }
        ##print '        ', $folder->get_folderlabel($lang), "\n";

        # first level control break - new category page
        if ( $master_id_old ne '' and $master_id ne $master_id_old ) {
          my %category_type_detail = (
            "is_$lang"        => 1,
            "is_$detail_type" => 1,
            detail_title      => $detail_title,
            lines             => join( "\n", @lines ),
            folder_count1     => $count_ref->{folder_count_first},
            document_count1   => $count_ref->{document_count_first},
          );
          if ( $master_voc->folders_complete($master_id_old) ) {
            $category_type_detail{complete} = 1;
          }

          push( @{ $category_data{$master_id_old} }, \%category_type_detail );
          @lines     = ();
          $count_ref = {};
        }
        $master_id_old = $master_id;

        # second level control break
        $firstletter =
          $detail_type eq 'ware'
          ? substr( $entry->{wareLabel}->{value}, 0, 1 )
          : substr( $signature,                   0, 1 );
        if ( $firstletter ne $firstletter_old ) {
          ## subheading
          my $subheading = $detail_voc->subheading( $lang, $firstletter );
          push( @lines, '', "### $subheading", '' );
          $firstletter_old = $firstletter;
        }

        # main entry
        my $line = '';
        my $relpath =
          $TO_ROOT->child('folder')->child( $folder->get_folder_hashed_path )
          ->child("about.$lang.html");
        my $syspage_link = "../../../$detail_type/about.$lang.html#"
          . $detail_voc->siglink($detail_id);
        my $catpage_link =
          "../../../$detail_type/i/$detail_id/about.$lang.html";
        my $entry_note =
            '(<a href="'
          . $folder->get_iiifview_url()
          . '" title="'
          . "$linktitle{about_hint}{$lang}: "
          . $folder->get_folderlabel($lang)
          . '" target="_blank">'
          . "$entry->{docs}->{value} $linktitle{documents}{$lang}</a>) "
          . "([$linktitle{folder}{$lang}]($relpath))";

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

        my $syspage_title = $linktitle{"${detail_type}_sys"}{$lang};
        my $catpage_title = "$label " . $linktitle{"${detail_type}_cat"}{$lang};
        my $entry_label = $detail_type eq 'ware' ? $label : "$signature $label";
        $line .=
            "- $entry_label "
          . "[**&nearr;**]($catpage_link \"$catpage_title\") "
          . "[**&uarr;**]($syspage_link \"$syspage_title\") "
          . $entry_note;

        push( @lines, $line );
        $detail_id_old = $detail_id;

        # statistics
        $count_ref->{folder_count_first}++;
        $count_ref->{document_count_first} += $entry->{docs}{value};
      }

      # save the last category
      ## q & d: add lines as large variable
      my %category_type_detail = (
        "is_$lang"        => 1,
        "is_$detail_type" => 1,
        detail_title      => $detail_title,
        lines             => join( "\n", @lines ),
        folder_count1     => $count_ref->{folder_count_first},
        document_count1   => $count_ref->{document_count_first},
      );
      if ( $master_voc->folders_complete($master_id_old) ) {
        $category_type_detail{complete} = 1;
      }

      push( @{ $category_data{$master_id_old} }, \%category_type_detail );
      @lines     = ();
      $count_ref = {};
    }

    # actual output of all collected data for a category
    foreach my $category_id ( sort keys %category_data ) {
      my $data_ref = $category_data{$category_id};
      output_category_page( $lang, $category_type, $category_id, $data_ref );
    }

  }
}

############

sub output_category_page {
  my $lang          = shift or croak('param missing');
  my $category_type = shift or croak('param missing');
  my $id            = shift or croak('param missing');
  my $data_ref      = shift or croak('param missing');

  my $provenance =
    $PROV{ $definitions_ref->{$category_type}{prov} }{name}{$lang};
  my $signature = $master_voc->signature($id);
  my $label     = $master_voc->label( $lang, $id );
  my $backlinktitle =
    $lang eq 'en'
    ? 'Category Overview'
    : 'Systematik-Übersicht';
  my $uri      = "http://purl.org/pressemappe20/category/$category_type/i/$id";
  my %tmpl_var = (
    uri              => $uri,
    "is_$lang"       => 1,
    label            => $label,
    modified         => last_modified( $master_voc, $detail_voc ),
    backlink         => "../../about.$lang.html",
    backlink_title   => $backlinktitle,
    provenance       => $provenance,
    wdlink           => $master_voc->wdlink($id),
    wplink           => $master_voc->wplink( $lang, $id ),
    scope_note       => $master_voc->scope_note( $lang, $id ),
    detail_type_loop => $data_ref,
  );

  if ( $category_type ne 'ware' ) {
    $tmpl_var{signature} = $signature;
  }

  # navigation tabs for overview page?
  if (  $category_type eq 'geo'
    and $master_voc->folder_count( 'geo', 'subject', $id )
    and $master_voc->folder_count( 'geo', 'ware',    $id ) )
  {
    $tmpl_var{show_tabs} = 1;
  }

  my $tmpl = HTML::Template->new(
    filename => $TEMPLATE_ROOT->child('category.md.tmpl'),
    utf8     => 1
  );
  $tmpl->param( \%tmpl_var );

  my $out_dir =
    $WEB_ROOT->child($category_type)->child('i')->child($id);
  $out_dir = path("$WEB_ROOT/$category_type/i/$id");
  $out_dir->mkpath;
  my $out = $out_dir->child("about.$lang.md");
  $out->spew_utf8( $tmpl->output );

  return;
}

sub get_master_detail_ids {
  my $category_type = shift or croak('param missing');
  my $detail_type   = shift or croak('param missing');
  my $folder_nk     = shift or croak('param missing');

  $folder_nk =~ m/^(\d{6}),(\d{6})$/
    or confess "irregular folder id $folder_nk";

  my ( $master_id, $detail_id );
  if ( $category_type eq 'geo' and $detail_type eq 'subject' ) {
    $master_id = $1;
    $detail_id = $2;
  } elsif ( $category_type eq 'geo' and $detail_type eq 'ware' ) {
    $master_id = $2;
    $detail_id = $1;
  } elsif ( $category_type eq 'subject' and $detail_type eq 'geo' ) {
    $master_id = $2;
    $detail_id = $1;
  } elsif ( $category_type eq 'ware' and $detail_type eq 'geo' ) {
    $master_id = $1;
    $detail_id = $2;
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

sub get_canonical {
  my $category_type = shift or croak('param missing');
  my $signature     = shift or croak('param missing');

  ( my $sig = $signature ) =~ s/ /_/g;
  my $x_canonical = "https://pm20.zbw.eu/category/$category_type/s/$sig";

  return $x_canonical;
}

