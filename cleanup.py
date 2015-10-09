import os, shutil

dist_qsub_dir = os.path.dirname(os.path.realpath(__file__))

os.remove("finished.txt")
run_list = open(run_list)

dest_dir = ""

for line in run_list:
    if "set dest_dir" in line:
        dest_dir = line.split()[-1]
        break


os.remove(dest_dir+"/*done_arrayjobs.txt")
os.remove(dest_dir+"/*message.log*")
shutil.rmtree(dist_qsub_dir+"/qsub_files")
