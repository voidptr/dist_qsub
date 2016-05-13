#!/usr/bin/python
import os, shutil, glob, sys
from optparse import OptionParser

parser = OptionParser()
parser.add_option("-l", "--run_list", action = "store", dest = "rl_fpath", default = "run_list", help = "Use this to set a custom run_list file to use during cleanup.")


dist_qsub_dir = os.path.dirname(os.path.realpath(__file__))

if os.path.exists(dist_qsub_dir + "/finished.txt"):
    os.remove(dist_qsub_dir + "/finished.txt")

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
