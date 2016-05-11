#!/usr/bin/python

import os, shutil, glob, sys

dist_qsub_dir = os.path.dirname(os.path.realpath(__file__))

if os.path.exists(dist_qsub_dir + "/finished.txt"):
    os.remove(dist_qsub_dir + "/finished.txt")

rl_fpath = sys.argv[1]
run_list = open(rl_fpath)

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
