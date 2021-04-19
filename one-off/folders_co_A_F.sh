#!/bin/sh

# creates /pm20/film/co, a directory tree of symlinks to A and F

for part in "A" "F" ; do
  pushd /pm20/folder/$part
  for hash in * ; do
    if [ ! -d $hash ]; then
      continue
    fi
    pushd /pm20/folder/$part/$hash
    for dir in * ; do
      if [ ! -d $dir ]; then
        continue
      fi
      source=../../$part/$hash/$dir
      target_root=/pm20/folder/co/$hash
      mkdir -p $target_root
      pushd $target_root
      if [ -d $dir ]; then
        echo $target_root/$dir already exists
        exit
      fi
      ln -s $source $dir
      popd
    done
    popd
  done
  popd
done
