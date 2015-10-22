#!/bin/bash

for file in *_bak; 
do     
    mv "$file" "`basename $file _bak`"; 
done
