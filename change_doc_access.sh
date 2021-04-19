#!/bin/bash

# After a change in the access status in one or more documents
# of a folder, this scripts rebuilds the according .htaccess 
# file and the intern and public METS files

# check param
if [ "$#" -ne 1 ]; then
  echo Invoke with folder id
  exit 2
fi
FID="$1"

# parse folder id
FID_PATTERN='^(co|pe|sh|wa)/([0-9]{4})([0-9]{2})(,([0-9]{4})([0-9]{2}))?$'
[[ $FID =~ $FID_PATTERN ]]

if [[ "${BASH_REMATCH[0]}" = "" ]]; then
  echo $FID is not a valid folder id
  exit 2
fi

#echo "${BASH_REMATCH[1]}"
#echo "${BASH_REMATCH[2]}"
#echo "${BASH_REMATCH[3]}"
#echo "${BASH_REMATCH[4]}"
#echo "${BASH_REMATCH[5]}"
#echo "${BASH_REMATCH[6]}"

holding="${BASH_REMATCH[1]}"
id1_start="${BASH_REMATCH[2]}"
id1_end="${BASH_REMATCH[3]}"
id2_start="${BASH_REMATCH[5]}"
id2_end="${BASH_REMATCH[6]}"

# recreate document locks
if [[ $holding =~ ^(co|pe)$ ]]; then
  path=/pm20/folder/$holding/${id1_start}xx/$id1_start$id1_end
  perl recreate_document_locks.pl $path
else
  path=/pm20/folder/$holding/${id1_start}xx/$id1_start$id1_end/${id2_start}xx/$id2_start$id2_end
  perl recreate_document_locks.pl $path
fi

# recreate METS files
perl create_mets.pl $FID



