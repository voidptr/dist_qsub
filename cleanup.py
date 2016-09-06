#!/usr/bin/python

import os, shutil, glob

run_list = open("run_list")

dest_dir = ""

for line in run_list:
    if "set dest_dir" in line:
        dest_dir = line.split()[-1]
        break

if dest_dir == "":
    dest_dir = "."

run_list.close()

for filename in glob.glob(dest_dir+"/*message.log*"):
    os.remove(filename)

if os.path.exists(dest_dir+"/qsub_files"):
    shutil.rmtree(dest_dir+"/qsub_files")
