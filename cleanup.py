#!/usr/bin/python

import os, shutil, glob

dist_qsub_dir = os.path.dirname(os.path.realpath(__file__))

if os.path.exists("finished.txt"):
    os.remove("finished.txt")

run_list = open("run_list")

dest_dir = ""

for line in run_list:
    if "set dest_dir" in line:
        dest_dir = line.split()[-1]
        break

run_list.close()

for filename in glob.glob(dest_dir+"/*message.log*"):
    os.remove(filename)

if os.path.exists(dist_qsub_dir+"/qsub_files"):
    shutil.rmtree(dist_qsub_dir+"/qsub_files")
