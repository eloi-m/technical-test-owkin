import datetime
import os
import json
import logging
import subprocess

from werkzeug.utils import secure_filename

from flask import abort, Flask, request, render_template

from utils import read_file, write_file

app = Flask(__name__)

mnt_dir = os.environ.get("MNT_DIR", "/data")


@app.route("/")
def hello_world():
    message = "Welcome to the Image Builder. To get started, check the README of the project: https://github.com/eloi-m/technical-test-owkin"
    return message


@app.route("/job/build", methods=["POST", "PUT"])
def build_job():
    """
    The goal of this route is to launch a `docker build && docker run` command, and to return a job_id.

    This route first fetches the Dockerfile from the parameters,
    then it writes a file in /data/perf.json containing only the key "started".
    The route finally builds and runs the Dockerfile asynchronously before exiting and returning the job_id.
    """

    try:
        # TODO: implement the possibilty for several jobs in parallel
        job_id = 1
        logging.info(f"Launching job {job_id}")

        file = request.files["file"]
        file_data = file.read().decode("latin-1")
        filename = secure_filename(file.filename)

        write_file(
            f"{mnt_dir}/perf.json",
            content=json.dumps({"started": str(datetime.datetime.now())}),
        )

        write_file("/tmp/Dockerfile", file_data)

        image_tag = f"job_{job_id}"

        subprocess.Popen(
            f"docker build -t {image_tag} /tmp && docker run --volume /data:/data {image_tag}",
            shell=True,
        )

        return {"id": job_id, "filename": filename}

    except Exception as e:
        return {"error": f"An error happened : {e}"}, 500


@app.route("/job/performance/<job_id>")
def get_performance(job_id):
    """
    The goal of the route is to check whether a build/run job is finished or not.

    This route first reads from the /data/perf.json file.
    Then, based on the state of the file, it returns different messages.
    """

    try:
        dict_perf = read_file(f"{mnt_dir}/perf.json")
    except FileNotFoundError:
        logging.error(f"The job {job_id} does not exist")
        return {"error": "The job ID is not found."}
    except Exception as e:
        return {"error": f"An error happened : {e}"}, 500

    if "started" in dict_perf:
        logging.info(f"The job {job_id} has started, but is not finished")
        return {"job": job_id, "info": "The job has started, but is not finished"}

    if "perf" in dict_perf:
        logging.info(f"The job {job_id} is finished")
        performance = dict_perf["perf"]
        return {"job": job_id, "perf": performance}

    return {"error": "An unkown error occured"}


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=80)
