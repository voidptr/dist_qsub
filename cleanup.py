#!/usr/bin/python
import os, shutil, glob, sys
from optparse import OptionParser

parser = OptionParser()
parser.add_option("-l", "--run_list", action = "store", dest = "rl_fpath", default = "run_list", help = "Use this to set a custom run_list file to use during cleanup.")
(options, args) = parser.parse_args()

run_list = open(options.rl_fpath)

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
