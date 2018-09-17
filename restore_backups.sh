#!/bin/bash

for file in *_bak; 
do     
    if [ ! -d "`basename $file _bak`" ];
    then
	mv "$file" "`basename $file _bak`"; 
    fi
done
