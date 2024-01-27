#!/bin/sh
# nbt, 11.12.2023
#
# Rebuild all pages after changes in the data
# (e.g., after execution of recreate_document_locks.pl for moving wall)
#
set -e

# overview pages / lists / categories (in markdown)
# (it is possible that new entries occur,
# e.g. when new persons/companies are added which had no documents before
for set in "pe" "co" ; do
  perl create_folder_list.pl $set
done
# creates overview and individual pages for geo, subject and ware
# (used for collections sh and wa)
perl create_category_pages.pl

# page markdown and image viewer input for individual folders
for set in "pe" "co" "sh" "wa" ; do
  perl create_folder_pages.pl $set
  perl create_iiif_manifest.pl $set
  perl create_mets.pl $set
done

# recrate html from markdown pages
./web_make_all.sh

