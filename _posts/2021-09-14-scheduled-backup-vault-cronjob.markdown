---
title: "Scheduled backup of Vault secrets with CronJob of Kubernetes"
date: 2021-09-14 09:24
comments: true
categories:
  - vault
tags:
  - vault
description: vault, cronjob, python, kubernetes, k8s, hvac
keywords: 
  - vault
  - cronjob
  - python
  - kubernetes
  - k8s
  - hvac
sharing: true
draft: false
thumbnail: "/assets/images/vault-cronjob/1.png"
excerpt: "
<img src='/assets/images/vault-cronjob/1.png' align='center'/> 



I will share in this post my experience related to automation of Vault backup creation using Kubernetes CronJob.

This post is a continuation of the previous [post](https://igorzhivilo.com/vault/scheduled-backup-vault-secrets/)"

---

<img src='/assets/images/vault-cronjob/1.png' align='center'/> 

I am a DevOps engineer at Cloudify.co and I will share in this post my experience related to automation of Vault backup creation using Kubernetes CronJob. 

This post is a continuation of the previous post: [https://igorzhivilo.com/vault/scheduled-backup-vault-secrets](https://igorzhivilo.com/vault/scheduled-backup-vault-secrets)

The repository with all the code: [https://github.com/warolv/vault-backup](https://github.com/warolv/vault-backup)

## What is HashiCorp's Vault?

Vault is a tool for securely accessing secrets. A secret is anything that you want to tightly control access to, such as API keys, passwords, certificates, and more. Vault provides a unified interface to any secret while providing tight access control and recording a detailed audit log.

https://www.vaultproject.io/


## My Setup

* EKS Kubernetes cluster
* Vault runs on EKS cluster

## What you will learn from this post?

* How to create a scheduled backup for Vault secrets with CronJob of Kubernetes.

* How to add Prometheus alerts for failed jobs.

You can find all the code presented in my repository: [https://github.com/warolv/vault-backup](https://github.com/warolv/vault-backup)

Let's start.

## Building the docker container

First, need to build a docker container based on python3 and include the code of vault_handler.py

Need clone the [repo](https://github.com/warolv/vault-backup) first with Docker file: 'git clone https://github.com/warolv/vault-backup'

Docker file:

``` yaml
FROM python:3

COPY requirements.txt /

RUN pip install -r requirements.txt

COPY vault_handler.py /

CMD [ "python", "./vault_handler.py" ]
```

### Building image

``` bash
# login to dockerhub
$ docker login -u YOUR_USERNAME -p YOUR_PASSWORD

# Build Docker
$ docker build -t vault-backup .
```

### Validate docker container working properly

``` bash
$ docker run --name test-vault-backup --rm vault-backup
Specify one of the commands below
print
print-dump
dump
populate
```

It's working, we got a list of commands from vault-backup:-)

### Pushing vault-backup docker container to docker hub

``` bash
$ docker tag vault-backup <Your Docker ID>/vault-backup:latest
$ docker push <Your Docker ID>/vault-backup:latest
```

In my case, it's 'warolv/vault-backup:latest', you can find an already built image [there](https://hub.docker.com/r/warolv/vault-backup).

## CronJob to run vault-backup on a daily basis

[https://github.com/warolv/vault-backup/blob/main/examples/cronjob/cronjob.yaml](https://github.com/warolv/vault-backup/blob/main/examples/cronjob/cronjob.yaml)

``` yaml
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: vault-backup
spec:
  schedule: "0 1 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: Never
          nodeSelector:
            instance-type: spot
          containers:
            - name: awscli
              image: amazon/aws-cli:latest
              command:
                - "aws"
                - "s3"
                - "cp"
                - "/data/vault_secrets.enc"
                - "s3://jenkins-backups/vault_secrets.enc"
              imagePullPolicy: Always
              envFrom:
                - secretRef:
                    name: aws-creds-secret
              volumeMounts:
              - name: backup-dir
                mountPath: /data
          initContainers:
            - name: vault-backup
              image: warolv/vault-backup
              command: 
                - "python3"
                - "vault_handler.py"
                - "dump"
                - "-dp"
                - "/data/vault_secrets.enc"
              imagePullPolicy: Always
              envFrom:
                - secretRef:
                    name: vault-backup-secret
              volumeMounts:
              - name: backup-dir
                mountPath: /data
          volumes:
          - name: backup-dir
            emptyDir: {}
```

### Explanation

* First 'vault_backup.py' script will run from InitContainer and secrets dump will be created (vault_secrets.enc) and saved to */data* folder which is a shared folder for both containers.

* The second will run 'awscli' container which will be used to push the secrets dump to a private S3 bucket (AWS CLI is used to copy the secrets dump to the privare S3 bucket). Of course, S3 private bucket must exist.

* Credentials for AWS CLI (AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY) and for vault_backup script exported to the environment as k8s secrets.

* In this example, I am copying the dump to 's3://jenkins-backups/vault_secrets.enc', in the production use case I suggest adding a timestamp to dump of secrets to be something like vault_secrets_${timestamp}.enc

### Creating secrets for CronJob

``` bash
# create k8s secret for AWS
$ kubectl create secret generic aws-creds-secret \
--from-literal=AWS_ACCESS_KEY_ID=YOUR_AWS_ACCESS_KEY_ID \
--from-literal=AWS_SECRET_ACCESS_KEY=YOUR_AWS_SECRET_ACCESS_KEY

# create k8s secret with all needed data for vault-backup
$ kubectl create secret generic vault-backup-secret \
--from-literal=VAULT_ADDR=http://vault.vault.svc.cluster.local:8200 \
--from-literal=ROLE_ID=YOUR_ROLE_ID \
--from-literal=SECRET_ID=YOUR_SECRET_ID \
--from-literal=ENCRYPTION_KEY=ENCRYPTION_KEY \
--from-literal=VAULT_PREFIX=jenkins
```

It's only an example, you need to put *real values*.

### Deploy vault-backup cronjob

``` bash
$ kubectl apply -f examples/cronjob/cronjob.yaml
```

### How to trigger a Job from CronJob?
In case you want to test your job is working properly:

``` bash
$ kubectl create job --from=cronjob/vault-backup vault-backup-001
```

## Adding alerts to Prometheus
I am using [kube-state-metrics](https://github.com/kubernetes/kube-state-metrics) with Prometheus and we have these metrics available: [https://github.com/kubernetes/kube-state-metrics/blob/master/docs/cronjob-metrics.md](https://github.com/kubernetes/kube-state-metrics/blob/master/docs/cronjob-metrics.md)

Let's add an alert for *'failed job'* and for cronjob which *'takes too much time'*, of course, it's only an example to give you an idea.

``` yaml
groups:
- name: cronjob.rules
  rules:
  - alert: SlowCronJob
    expr: time()-kube_cronjob_next_schedule_time > 1800
    for: 30m
    labels:
      severity: warning
    annotations:
      description: CronJob {{$labels.namespaces}}/{{$labels.cronjob}} is taking more than 30m to complete
      summary: CronJob taking more than 30m
  - alert: FailedJob
    expr: kube_job_status_failed  > 0
    for: 30m
    labels:
      severity: warning
    annotations:
      description: Job {{$labels.namespaces}}/{{$labels.job}} failed
      summary: Job failure
```

In this post, I described how to automate Vault backup creation using Kubernetes CronJob and a simple python script that I built.

Thank you for reading, I hope you enjoyed it, see you in the next post.

If you want to be notified when the next post of this tutorial is published, please follow me on Twitter [@warolv](https://twitter.com/warolv).

For consulting gigs you can reach me on [Upwork](https://www.upwork.com/freelancers/warolv)

Instagram: [@warolv](https://www.instagram.com/warolv)

Medium account: warolv.medium.com
