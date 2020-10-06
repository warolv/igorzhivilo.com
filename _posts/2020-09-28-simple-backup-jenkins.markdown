---
title: "Simple Backup for Jenkins on Kubernetes"
date: 2020-09-28 12:24
comments: true
categories:
  - jenkins
tags:
  - jenkins
description: jenkins backup, jenkins pipieline, Jenkins, cicd backup
keywords: 
  - jenkins
  - backup jenkins
  - ci-cd backup
  - jenkins pipieline
sharing: true
draft: false
thumbnail: "/assets/images/jenkins-backup/1.png"
---

<img src="/assets/images/jenkins-backup/1.png" align="center"/> 

As a DevOps engineer at Cloudify.co, I am building a new CI/CD pipeline based on Kubernetes and Jenkins. Recently I was dealing with the existent backup mechanism for Jenkins which stopped to work and I was in need of another solution. In this post, I will share my solution.

Let’s start.

## What is Jenkins?

Jenkins is a self-contained, open source automation server which can be used to automate all sorts of tasks related to building, testing, and delivering or deploying software.

https://jenkins.io/doc/

## What is Jenkins Pipeline?

Jenkins Pipeline (or simply “Pipeline” with a capital “P”) is a suite of plugins that supports implementing and integrating continuous delivery pipelines into Jenkins.

https://www.jenkins.io/doc/book/pipeline/

## Prerequisites

* Kubernetes cluster must be installed with Jenkins on top of it.
* Jenkins Kubernetes plugin must be installed on Jenkins.
* Service account with access to the Kubernetes cluster must be configured.

## Problem definition

When I installed Jenkins through the helm chart to my EKS cluster I enabled backups in my custom values.yaml.

The backup mechanism was based on https://github.com/maorfr/kube-tasks and scheduled Kubernetes job which runs a backup job on a daily basis and copies my /var/jenkins_home folder file by file to s3 bucket on AWS.

It worked for some time in the beginning till I found that 3 last jobs in a failed state and logs revealed ‘error in Stream: command terminated with exit code 1 src: file:”, you can read about this issue [here](https://github.com/nuvo/kube-tasks/issues/2). You can see this was opened on Feb 5, 2019, and not being solved.

## Solution

To solve the backups problem I created a simple scheduled job in Jenkins
which creates jenkins_backup.tar.gz file from /var/jenkins_home folder of Jenkins POD and uploads this archived backup to s3 bucket (s3://jenkins-backups) daily. Of course, I understand there are many solutions, but I wanted a simple solution with full control.

### The workflow in details

All commands executed on awscli container, which I used to have preinstalled awscli

1. Install kubectl on awscli container

2. Get Jenkins pod ID

3. Create backup on jenkins POD as /var/jenkins_backup/jenkins_backup.tar.gz

4. Upload jenkins_backup.tar.gz to s3 bucket (s3://jenkins-backups).

5. Remove /var/jenkins_backup folder with the backup on Jenkins POD

### The declarative pipeline of the job

``` groovy
def configuration = [vaultUrl: "${VAULT_URL}",  vaultCredentialId: "vault-app-role", engineVersion: 2]

def secrets = [
  [path: 'secret/jenkins/aws', engineVersion: 2, secretValues: [
    [envVar: 'AWS_ACCESS_KEY_ID', vaultKey: 'aws_access_key_id'],
    [envVar: 'AWS_SECRET_ACCESS_KEY', vaultKey: 'aws_secret_access_key']]],
]

pipeline {
  agent {
    kubernetes {
      label 'jenkins-backup-job'
      defaultContainer 'jnlp'
      yamlFile 'build-pod.yaml'
    }
  }
  
  options {
    buildDiscarder(logRotator(numToKeepStr:'30'))
    timeout(time: 60, unit: 'MINUTES')
  }
stages {
    stage('Backup Jenkins'){
      steps {
        container('awscli'){
          withVault([configuration: configuration, vaultSecrets: secrets]){
            sh '''
              echo 'Install kubectl'
              curl -LO "https://storage.googleapis.com/kubernetes-release/release/\$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
              chmod +x ./kubectl
              mv ./kubectl /usr/local/bin/kubectl
function get_jenkins_pod_id {
                kubectl get pods -n jenkins -l app.kubernetes.io/component=jenkins-master -o custom-columns=PodName:.metadata.name | grep jenkins-
              }
  
              echo 'Create jenkins backup'
              kubectl exec $(get_jenkins_pod_id) -- bash -c 'cd /var; \
                rm -rf jenkins_backup; \
                mkdir -p jenkins_backup; \ 
                cp -r jenkins_home jenkins_backup/jenkins_home; \
                tar -zcvf jenkins_backup/jenkins_backup.tar.gz jenkins_backup/jenkins_home'
              
              cd && kubectl cp jenkins/$(get_jenkins_pod_id):/var/jenkins_backup/jenkins_backup.tar.gz jenkins_backup.tar.gz
              
              echo 'Upload jenkins_backup.tar to S3 bucket'
              aws s3 cp jenkins_backup.tar.gz s3://jenkins-backups/$(date +%Y%m%d%H%M)/jenkins_backup.tar.gz
              
              echo 'Remove files after succesful upload to S3'
              kubectl exec $(get_jenkins_pod_id) -- bash -c 'rm -rf /var/jenkins_backup'
            '''
          }
        }
      }
    }
  }
}
```

https://gist.github.com/warolv/1dbe6efed66d3111decae825b7b73241

### build-pod.yaml

``` yaml
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: awscli
      image: amazon/aws-cli
      command:
      - cat
      tty: true
```

I am using HashiCorp’s Vault to store secrets if you want to understand more about how to read the vault’s secrets from Jenkin’s declarative pipeline:

https://codeburst.io/read-vaults-secrets-from-jenkin-s-declarative-pipeline-50a690659d6

<img src="/assets/images/jenkins-backup/2.png" align="center"/> 

<img src="/assets/images/jenkins-backup/3.png" align="center"/> 

I explained in this post how to build a simple scheduled job with a declarative pipeline in Jenkins on Kubernetes which stores backups of your Jenkins configuration on daily basis.

I hope this post was helpful and thank you for reading.

Please follow me on [Twitter (@warolv)](https://twitter.com/warolv)

and [Medium](https://medium.com/@warolv)