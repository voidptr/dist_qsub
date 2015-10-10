import glob, os, re, sys

#This script searches the current working directory for runs that did not
#get to the number of updates specified by the first command-line argument
#and creates a new run_list file to resubmit all of them. If any runs ended
#early due to natural causes (i.e. the population went to 0), they are not
#resubmitted and are instead recorded in the "extinct" file.

updates = "100000"
if len(sys.argv) > 1:
    updates = sys.argv[1]

run_list = open("run_list", "wb")
extinct = open("extinct", "wb")

header = "set description conservation\nset email dolsonem@msu.edu\nset email_when final\nset class_pref 95\nset walltime 4\nset mem_request 4\nset config_dir configs\nset dest_dir " + os.getcwd() + "\n\n"

run_list.write(header)

conditions = {}

run_logs = glob.glob("./*/run.log")

for run in run_logs:
    if "_bak" in run:
        continue

    with open(run) as logfile:
        end = logfile.readlines()[-1].split()            
        pop = end[-1]
        ud = end[1]

        rep = run.split("/")[-2]

        if ud != updates:
            if pop == "0":
                extinct.write(condition+"\n")
                continue
            
            print "resubmit: ", rep

            split_condition = rep.split("_")
            seed = split_condition[-1]
            condition = "_".join(split_condition[:-1])
            condition = condition.strip("./ ")

            if condition in conditions:
                conditions[condition]["seeds"].append(seed)
            else:
                conditions[condition] = {}
                conditions[condition]["seeds"] = [seed]
                conditions[condition]["name"] = condition

                command_file = open(rep+"/command.sh")
                command = command_file.readlines()[1]
                split_command = command.split()
                split_command[2] = "$seed"
                command = " ".join(split_command)
                command_file.close()

                conditions[condition]["command"] = command
                

                
for condition in conditions:
    seeds = conditions[condition]["seeds"]
    name = conditions[condition]["name"]
    command = conditions[condition]["command"]

    seeds.sort()
    first = 0
    second = 0
    while second < len(seeds)-1:
        second = first
        while second < len(seeds) - 1 and int(seeds[second])+1 == int(seeds[second+1]):
            if second >= len(seeds) - 1:
                break
            second += 1
            
        #We have isolated a chunk of numbers
        if second == first:
            run_list.write(seeds[first] + " " + name + " " + command + "\n")
        else:
            run_list.write(seeds[first]+".."+seeds[second] + " " + name + " " + command + "\n")
                        
        first = second + 1
