# Technical test Owkin

This is a technical test I did for Owkin in January 2023.

The goal of this test is to create a service that:
* Receives a Dockerfile
* Builds and runs the Dockerfile
* Exposes a number called "perf" (assumed to be written during the execution of the Docker container) 


I chose to tackle this project by creating a Python Service inside GCE (Google Compute Engine), that serves 2 routes :

* the first route is `job/build` (`POST/PUT`). This routes receives a Dockerfile, and builds it in the background with `Subprocess.popen`. Without waiting for the build/run to finish, the route returns a `job_id`.
* the second route is `job/performance/<job_id>` (`GET`). This route scans a directory `/data`. Depending on the state of the `perf.json` file, it returns either :
  * The process was not started
  * Process started, but not yet finished
  * Process finished (with the associated performance)

# How does it work ? 

The Python service is a mix of 3 technologies :

1. Flask/Gunicorn is used to create the backend. 
2. GCSFuse is used to mount a GCS (Google Cloud Storage) bucket to the `/data` directory of the GCE VM.
3. Docker (inside Docker) is used to build the Dockerfile and run the corresponding image.


To use the service, you first need to upload a Dockerfile using this CURL command:

```bash
curl -X POST -F file=@<PATH_TO_DOCKERFILE>  http://<ID_ADRESS>/job/build
```

Here's an example of the command that uses the `test_endpoint.Dockerfile` from this repo :

```bash
curl -X POST -F file=@test_endpoint.Dockerfile  http://34.79.150.175/job/build
```

The route should return `{"id": 1, "filename": test_endpoint.Dockerfile"}`.

You can check if the build was successful and the performance associated with the job with the command:

```bash
curl http://<ID_ADRESS>/job/performance/1
```

If the build/run takes a while, you might need to refresh in a few seconds.

# Limits of the service

## Security of the container

For time reasons, I did not work on checking the vulnerabilities of the Docker Container.
This would be possible with a service like Snyk.

It would also be possible to double down and to check the vulnerabilities of the code inside the Git repo itself, using GitlabCI and tools like Bandit, Safety, or SonarQube.

## Limits of the architecture

For time and cost reasons, I chose to run a Python service that exposes an API, builds and runs Dockerfile, all in the same VM.

This is fine for a proof of concept, but I would not recommand this solution for a production environment for various reasons: 

* Security during the build : running Docker in Docker (DinD) is a bad practice since it requires the initial container to be run in privileged mode, giving the children containers access to the `/dev` filesystem (I recommand [this article](https://blog.loof.fr/2018/01/to-dind-or-not-do-dind.html) which explains the limitations of DinD)
* Security during the run: the service also **runs** the container that was built using DinD. Since the volume `/data` (mounted to a bucket) is exposed to the container, anyone can access the content of the bucket with read/write permissions.
* Scalability: the service would not be cost-effective at scale (it would require spinning more VMs)
* Maintainability: since the 3 tasks that expose the route, build and run the containers are all imbricated, the service would be hard to maintain. 

## Possible improvements

If I had more time, I would probably split the service into 3 differents parts in a Kubernetes Cluster:
* service: a Python Flask app that exposes 2 routes, just like before. The `job/build` route, instead of building and running a container, queues up a `build` job and a `run` job.
* build: this job uses Kaniko to build the Dockerfile. It uploads the resulting container to Artifact Registry.
* run: Once the build is done, the `run` job is in charge of running the container in Kubernetes. The `perf.json` file is written to `/data`, inside a Persistant Volume Claim. 


# Install 

If you want to run the service in your own GCE environment, you can use these commands. The APIs are not activated for a new project, so you might need to activate them after each command.

### Export the names of the various resources

```bash
export PROJECT_NAME=image-builder-project-tto
export BUCKET_NAME=bucket-image-builder-project-tto
export REPO_NAME=image-builder-repo
export CONTAINER_NAME=image-builder-container
export INSTANCE_NAME=image-builder-instance
export REGION=europe-west1
export ZONE=europe-west1-b
```


### Create the GCP project
```bash
gcloud projects create $PROJECT_NAME --name="$PROJECT_NAME"
gcloud config set project $PROJECT_NAME
```

Make sure to enable billing after this step.

### Create the bucket
```bash
gcloud storage buckets create gs://$BUCKET_NAME
```

### Create Artifact Registry repo

```bash
gcloud artifacts repositories create $REPO_NAME --repository-format=docker \
    --location=$REGION --description="Docker repository"
```

### Build the service

```bash
gcloud builds submit --region=$REGION --tag $REGION-docker.pkg.dev/$PROJECT_NAME/$REPO_NAME/${CONTAINER_NAME}:latest
```



### Create the compute instance

This one is quite long, but we're almost there!

First, to get the project ID:
```bash
export PROJECT_ID=$(gcloud projects list \
  --filter="$(gcloud config get-value project)" \
  --format="value(PROJECT_NUMBER)")
```

Then, create the Compute Engine instance:
```bash
gcloud compute instances create-with-container \
    $INSTANCE_NAME --project=$PROJECT_NAME --zone=$ZONE --machine-type=e2-small \
    --network-interface=network-tier=PREMIUM,subnet=default --maintenance-policy=MIGRATE \
    --provisioning-model=STANDARD --service-account=$PROJECT_ID-compute@developer.gserviceaccount.com \
    --scopes=https://www.googleapis.com/auth/servicecontrol,https://www.googleapis.com/auth/service.management.readonly,https://www.googleapis.com/auth/logging.write,https://www.googleapis.com/auth/monitoring.write,https://www.googleapis.com/auth/trace.append,https://www.googleapis.com/auth/devstorage.full_control \
    --tags=http-server,https-server --image=projects/cos-cloud/global/images/cos-stable-101-17162-40-52 --boot-disk-size=10GB --boot-disk-type=pd-balanced --boot-disk-device-name=instance-6 \
    --container-image=$REGION-docker.pkg.dev/$PROJECT_NAME/$REPO_NAME/${CONTAINER_NAME} \
    --container-restart-policy=always --container-privileged --container-env=BUCKET=$BUCKET_NAME \
    --no-shielded-secure-boot --shielded-vtpm --shielded-integrity-monitoring --labels=container-vm=cos-stable-101-17162-40-52
```

This command returns the following table:

```
NAME                    ZONE            MACHINE_TYPE  PREEMPTIBLE  INTERNAL_IP  EXTERNAL_IP    STATUS
image-builder-instance  $ZONE           e2-small                   <INTERNAL>   <EXTERNAL>  RUNNING
```

Create firewall rule to allow traffic on port 80:

```bash
gcloud compute firewall-rules create rule-allow-tcp-80 --source-ranges 0.0.0.0/0 --target-tags allow-tcp-80 --allow tcp:80
```

Add the firewall rule to the instance:
```bash
gcloud compute instances add-tags $INSTANCE_NAME --tags allow-tcp-80
```


Once this done, you can connect to the instance using SSH:

```curl
gcloud compute ssh --zone $ZONE $INSTANCE_NAME
```

or with CURL and the external IP, using the commands that are described in [this section](#how-does-it-work).
