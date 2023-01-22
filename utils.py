import os
import json


def delete_file_if_exists(file_path):
    if os.path.exists(file_path):
        os.remove(file_path)


def write_file(file_path, content=""):
    delete_file_if_exists(file_path)

    with open(file_path, "w") as f:
        f.write(content)


def read_file(file_path):
    with open(file_path, "r") as f:
        dict_perf = json.load(f)
    return dict_perf
