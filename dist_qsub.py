#!/usr/bin/python

##########################
# Read the run_list file
##########################

# system includes
import glob
import os
from optparse import OptionParser
import sys
import time

# Set up options
usage = """usage: %prog [options] [run_list] 
"""
parser = OptionParser(usage)
parser.add_option("-v", "--verbose", action = "store_true", dest = "verbose",
                  default = False, help = "print extra messages to stdout")
parser.add_option("-d", "--debug_messages", action = "store_true", 
                  dest = "debug_messages",
                  default = False, help = "print debug messages to stdout")
## fetch the args
(options, args) = parser.parse_args()

run_list = "run_list"
if (len(args) > 0):
    run_list = args[0]

if run_list[-3:] == ".gz":
    fd = gzip.open(run_list)
else:
    fd = open(run_list)

settings = {}
processes = []
for line in fd:
    line = line.strip().lstrip() ## strip off the leading and following whitespace. 

    if len(line) == 0 or line[0] == "#":
        continue

    if (line[:3] == "set"):
        bits = line.split(" ");
        settings[bits[1]] = bits[2];
    else:
        processes.append(line.split(" ", 2))
if options.debug_messages:
    for command in processes:
        print command

for command in processes:
    bits = command[2].split(";")
    newcomm = []
    for bit in bits:
        newcomm.append(bit.lstrip() + " 2>&1 | cat >> run.log")

    command[2] = "\n".join(newcomm)


l_string = []

p_string = []
if ('ppn' in settings.keys()):
    pstring.append( "ppn=" + settings['ppn'] )
if ('nodes' in settings.keys()):
    pstring.append( "nodes=" + settings['nodes'] )
if len(p_string) > 0:
    lstring.append( ":".join(p_string) )

feature = []
if ('feature' in settings.keys()):
    feature_str = settings['feature'].split(',')
    for ftr in feature_str:
        feature.append("feature=" + ftr) 

if ('class_pref' in settings.keys()):
    if settings['class_pref'] == '91': # amd05
        feature.append("feature=amd05")
    elif settings['class_pref'] == '92': # intel07
        feature.append("feature=intel07")
    elif settings['class_pref'] == '95': # intel10
        feature.append("feature=intel10")
    elif settings['class_pref'] == '150': # intel14
        feature.append("feature=intel14")

if len(feature) > 0:
    l_string.append(":".join(feature))

if ('walltime' in settings.keys()):
    l_string.append( "walltime=" + settings['walltime'] + ":00:00" )
if ('mem_request' in settings.keys()):
    l_string.append( "mem=" + str(int(float(settings['mem_request']) * 1024)) + "mb" )


script_template = """
#!/bin/bash -login
#PBS -q main
#PBS -l %lstring%
#PBS -N %jobname%
#PBS -o %dest_dir%/message.log
#PBS -j oe
#PBS -t %job_seeds%

TARGETDIR=%dest_dir%
STARTSEED=%start_seed%
seed=$(($STARTSEED + $PBS_ARRAYID))
JOBTARGET=%jobname%"_"$seed


echo "seed="$seed "jobtarget="$JOBTARGET "targetdir="$TARGETDIR "pbs_arrayid="$PBS_ARRAYID "pbs_jobname="$PBS_JOBNAME "tmpdir="$TMPDIR;

#change directory to the directory this was run from
cd $PBS_O_WORKDIR
mkdir $TMPDIR/$JOBTARGET
cp -r config/* $TMPDIR/$JOBTARGET
cd $TMPDIR/$JOBTARGET

touch $JOBTARGET".here"

%job_command%

mkdir $TARGETDIR/$JOBTARGET

gzip -r .
tar czf dist_transfer.tar.gz .

mv dist_transfer.tar.gz $TARGETDIR/$JOBTARGET
cd $TARGETDIR/$JOBTARGET
tar xzf dist_transfer.tar.gz
rm dist_transfer.tar.gz
"""

if not os.path.exists(settings['dest_dir']):
        os.makedirs(settings['dest_dir'])

def strdiff(str1, str2):
    for i in range(len(str1)):
        if str1[i] != str2[i]:
            return i

script_template = script_template.replace( "%lstring%", ",".join(l_string))

for command in processes:
    command_final = script_template
    command_final = command_final.replace( "%jobname%", command[1] )
    command_final = command_final.replace( "%dest_dir%", settings['dest_dir'])
    command_final = command_final.replace( "%job_command%", command[2] )

    job_seeds = ""
    (start_seed, end_seed) = [ int(v) for v in command[0].split("..") ]
    job_ct = end_seed - start_seed
    job_seeds = "0-"+str(job_ct) # inclusive

    if job_ct > 99999 or job_ct < 1:
        exit("Seeds defined in " + command[0] + " are negative or invalid")

    command_final = command_final.replace( "%start_seed%", str(start_seed))
    command_final = command_final.replace( "%job_seeds%", job_seeds)

    print command_final
    print


    f = open("DELETE.ME", "w")
    f.write(command_final)

    os.system("qsub DELETE.ME")
    time.sleep(2)
