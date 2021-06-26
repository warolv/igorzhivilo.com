---
title: "Use images from ECR with Jenkins pipeline on Kubernetes"
date: 2020-07-20 12:24
comments: true
categories:
  - jenkins
tags:
  - jenkins
description: AWS EKS, AWS ECR, Jenkins pipieline, Jenkins
keywords: 
  - aws eks
  - aws ecr
  - jenkins pipeiline
  - elastic container registry
sharing: true
draft: false
thumbnail: "/assets/images/jenkins-ecr/1.png"
excerpt: "
<img src='/assets/images/jenkins-ecr/1.png' align='center'/>  


I am building a new CI/CD pipeline based on Kubernetes and Jenkins. Recently I integrated Elastic Container Registry with our CI/CD based on Jenkins. In this guide, I will share the knowledge on this topic."

---

<img src="/assets/images/jenkins-ecr/1.png" align="center"/> 

As a DevOps engineer at [Cloudify.co](http://www.cloudify.co), I am building a new CI/CD pipeline based on Kubernetes and Jenkins. Recently I integrated Elastic Container Registry with our CI/CD based on Jenkins. In this guide, I will share the knowledge on this topic.

Let’s start.

### What’s ECR — Amazon Elastic Container Registry?

Amazon Elastic Container Registry (ECR) is a fully-managed Docker container registry that makes it easy for developers to store, manage, and deploy Docker container images. Amazon ECR is integrated with Amazon Elastic Container Service (ECS), simplifying your development to production workflow. Amazon ECR eliminates the need to operate your own container repositories or worry about scaling the underlying infrastructure.

[aws ecr](https://aws.amazon.com/ecr/)


### What is Jenkins?

Jenkins is a self-contained, open source automation server which can be used to automate all sorts of tasks related to building, testing, and delivering or deploying software. 

[jenkins.io](https://jenkins.io/doc/)

### What is Jenkins Pipeline?

Jenkins Pipeline (or simply “Pipeline” with a capital “P”) is a suite of plugins which supports implementing and integrating continuous delivery pipelines into Jenkins.

[pipeline](https://www.jenkins.io/doc/book/pipeline/)

### Prerequisites

* You must have an AWS account
* Jenkins on Kubernetes running on your cluster

## Creating a user on AWS with ECR full access and programmatic access

### Create a policy with full access to ECR

In AWS account go to Services -> IAM -> Policies -> Create Policy -> JSON

``` yaml
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:*",
                "cloudtrail:LookupEvents"
            ],
            "Resource": "*"
        }
    ]
}
```

Click on review and create the policy

<img src="/assets/images/jenkins-ecr/2.png" align="center"/> 

<img src="/assets/images/jenkins-ecr/3.png" align="center"/> 

### Create a user with the attached policy we created and programmatic access

In AWS account go to Services -> IAM -> Users -> Add User

Select the programmatic access

<img src="/assets/images/jenkins-ecr/4.png" align="center"/> 

Attach created policy

<img src="/assets/images/jenkins-ecr/5.png" align="center"/> 

Create the user and download .csv file with credentials for programmatic access to AWS


<img src="/assets/images/jenkins-ecr/6.png" align="center"/> 

### Install AWS CLI to your machine

https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html

### Install docker to your machine

https://docs.docker.com/engine/install/


## How to authenticate with ECR?

So basically you have two options:

### Option 1

Export AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY as environment variables to your console/terminal

``` bash
export AWS_ACCESS_KEY_ID=Your_access_key_id_from_csv
export AWS_SECRET_ACCESS_KEY=your_secret_access_ key_from_csv
```

### Option 2

Use ‘aws configure’ to set your credentials and region, it will store credentials permanently in you $HOME/.aws directory

For both options, you need to use AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY which you may find in downloaded .csv file

## Create Amazon Elastic Container Registry

In AWS account go to Services -> Elastic Container registry

Click on Get Started

<img src="/assets/images/jenkins-ecr/7.png" align="center"/> 

Create a repository with a name hello-world for testing

<img src="/assets/images/jenkins-ecr/8.png" align="center"/> 

<img src="/assets/images/jenkins-ecr/9.png" align="center"/> 

Created ECR in us-east-1 region, 796556984717 is your AWS account id

## Login with docker to AWS

``` bash
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 796556984717.dkr.ecr.us-east-1.amazonaws.com
```

## Test your access to ECR

Make sure you configured AWS like I explained or exported needed variables and did log in with docker

``` bash
aws ecr list-images --repository-name hello-world --region=us-east-1
```

If you getting a response similar to this one

``` yaml
{
  "imageIds": []
}
```

It means everything is configured properly, otherwise, you will get access denied message.

## How to create an image and push to ECR?

Let’s build an example image and will push it to ECR

Dockerfile of the example image


``` Dockerfile

FROM alpine:3.4

RUN apk update && \
    apk add curl && \
    apk add git && \
    apk add vim

```

Build a hello-world image from Dockerfile

``` bash
docker build -t hello-world .
```

### Tag the image

``` bash
docker tag hello-world:latest 796556984717.dkr.ecr.us-east-1.amazonaws.com/hello-world:1.1
```

### Push to ECR

``` bash
docker push 796556984717.dkr.ecr.us-east-1.amazonaws.com/hello-world:1.1
```

We pushed our image to hello-world repository and version is 1.1

### Checking our image exists in hello-world repository

``` bash
aws ecr list-images --repository-name hello-world --region=us-east-1
```

The response must be similar to this one

``` yaml
{
  "imageIds": [
    {
      "imageDigest": "sha256:6045a7fdc628f8764cc52f6d0fe640029a2eb9b860bfc265c3ff9a5048068546",
      "imageTag": "1.1"
    }
  ]
}
```

## So how to use images in ECR with Jenkins pipeline on Kubernetes?

I am using ‘Jenkins Kubernetes’ plugin to run workflows with Kubernetes on Jenkins

### What is the Kubernetes plugin for Jenkins?

Jenkins plugin to run dynamic agents in a Kubernetes cluster.
The plugin creates a Kubernetes Pod for each agent started, defined by the Docker image to run, and stops it after each build.

[kubernetes plugin](https://plugins.jenkins.io/kubernetes/)

**pod-template** of your pipeline must be similar to this one

``` yaml
apiVersion: v1
kind: Pod
spec:
  containers: 
    - name:  hello-world
      image: 796556984717.dkr.ecr.us-east-1.amazonaws.com/hello-world:1.1
      command:
      - cat
      tty: true

```

Meaning we using an image in a regular way with a path to ECR

``` yaml
image: 796556984717.dkr.ecr.us-east-1.amazonaws.com/hello-world:1.1
```

### So why we don’t need permissions to access ECR in our pipeline in this case?

If you using the EKS cluster like me which was created using the eksctl utility or using the AWS CloudFormation templates, by default all worker nodes created with needed IAM permission to access ECR.

Every worker node has ‘AmazonEKSWorkerNodePolicy’ attached with needed IAM policy permissions.

I that’s not the case you need to attach this policy to your worker node policy

``` json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecr:BatchCheckLayerAvailability",
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    }
  ]
}

```

https://docs.aws.amazon.com/AmazonECR/latest/userguide/ECR_on_EKS.html

## Conclusion

I explained in this guide how to configure ECR in your account, create an image and push it to an ECR repository, then pull an image from ECR with Jenkins pipeline on Kubernetes, I also explained why in many cases on Kubernetes clusters like EKS it will work by default.

I hope this guide was helpful and thank you for reading.

