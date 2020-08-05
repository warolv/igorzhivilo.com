---
title: "Running Workflows on windows with Jenkins pipeline and Kubernetes"
date: 2020-06-29 12:24
comments: true
categories:
  - jenkins
tags:
  - jenkins
description: AWS EKS, windows workflows on EKS, windows workflows in Jenkins, windows workflows in Jenkins pipeline
keywords: 
  - aws eks windows
  - windows workflow
  - jenkins windows workflow
  - jenkins pipeline windows 
sharing: true
draft: false
thumbnail: "/assets/images/jenkins-windows/1.jpeg"
---

<img src="/assets/images/jenkins-windows/1.jpeg" align="center"/> 

As a DevOps engineer at [Cloudify.co](http://www.cloudify.co), I am building a new CI/CD pipeline based on Kubernetes and Jenkins. Recently working on one of the workflows I was in need to build artifacts (executables) on windows, and you can run pods(containers) with windows based images only on windows worker nodes. I will share my experience in this post about how to add windows worker nodes to your EKS cluster and then run windows workflows on the top of it.

Let’s start.

### What is Jenkins?

Jenkins is a self-contained, open source automation server which can be used to automate all sorts of tasks related to building, testing, and delivering or deploying software. 

[jenkins.io](https://jenkins.io/doc/)

### What is Jenkins Pipeline?

Jenkins Pipeline (or simply “Pipeline” with a capital “P”) is a suite of plugins which supports implementing and integrating continuous delivery pipelines into Jenkins.

[pipeline](https://www.jenkins.io/doc/book/pipeline/)

### What is the Kubernetes plugin for Jenkins?

Jenkins plugin to run dynamic agents in a Kubernetes cluster.
The plugin creates a Kubernetes Pod for each agent started, defined by the Docker image to run, and stops it after each build.

[kubernetes plugin](https://plugins.jenkins.io/kubernetes/)

### What is Amazon EKS?

Amazon Elastic Kubernetes Service (Amazon EKS) is a managed service that makes it easy for you to run Kubernetes on AWS without needing to stand up or maintain your own Kubernetes control plane. Kubernetes is an open-source system for automating the deployment, scaling, and management of containerized applications.

[amazon eks](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html)

## Add windows worker nodes to existing EKS cluster with linux nodes only

### Create a new node group (AWS autoscaling group) with windows nodes using eksctl utility directly, without the use of config

``` bash
eksctl create nodegroup \
--cluster your_cluster_name \
--region us-west-2 \
--version 1.15 \
--name ng-windows \
--node-type t3.medium \
--nodes 3 \
--nodes-min 1 \
--nodes-max 4 \
--node-ami-family WindowsServer2019FullContainer
```

The most important parameter here is node-ami-family: WindowsServer2019FullContainer

### Create a node group with windows nodes from config file and using the eksctl utility

``` bash
eksctl create nodegroup \
--cluster your_cluster_name \
--region us-west-2 \
--version 1.15 \
--name ng-windows \
--node-type t3.medium \
--nodes 3 \
--nodes-min 1 \
--nodes-max 4 \
--node-ami-family WindowsServer2019FullContainer
```

#### eks_cluster_config.yaml
``` yaml
- name: ng-windows
  amiFamily: WindowsServer2019FullContainer
  desiredCapacity: 3
  minSize: 1
  maxSize: 4
  instanceType: t3.medium
  privateNetworking: true
  availabilityZones: ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  labels:
    instance-type: windows
```

``` bash
eksctl create nodegroup --config-file=eks_cluster_config.yaml --include=ng-windows
```

### You may have also a more advanced configuration, for example running the windows nodes on spot instances

``` yaml
- name: ng-spot-windows
  amiFamily: WindowsServer2019FullContainer
  desiredCapacity: 0
  minSize: 0
  maxSize: 10
  privateNetworking: true
  instancesDistribution:
    instanceTypes: ["t2.large", "t3.large", "m3.large"]
    onDemandBaseCapacity: 0
    onDemandPercentageAboveBaseCapacity: 0
    spotInstancePools: 3
  tags:
    k8s.io/cluster-autoscaler/node-template/label/instance-type: spot-windows
  availabilityZones: ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  labels:
    instance-type: spot-windows
  iam:
    withAddonPolicies:
      autoScaler: true
```

In this case, I am using the cluster Cluster Autoscaler to automatically adjusts the size of the Kubernetes cluster

[cluster autoscaler](https://github.com/kubernetes/autoscaler/tree/master/cluster-autoscaler)

Also, read the [Consideration](https://docs.aws.amazon.com/eks/latest/userguide/windows-support.html), which has important info like
Amazon EC2 instance types C3, C4, D2, I2, M4 (excluding m4.16xlarge), and R3 instances are not supported for Windows workloads.

### Installing VPC Resource Controller and VPC Admission Webhook into the cluster

These components run on Linux nodes and are responsible for enabling networking for incoming pods on Windows nodes. To use the tool we run the following command.

``` bash
eksctl utils install-vpc-controllers --name your_cluster_name --approve
```

### Deploy a Windows sample application

https://docs.aws.amazon.com/eks/latest/userguide/windows-support.html#windows-sample-application

I encourage you to deploy a windows sample application to validate your cluster configured properly.

### Setting properly Node Selectors in your application

So the cluster is configured and able to run windows workflows, now you must specify node selectors on your applications so that the pods land on a node with the appropriate operating system.

### Targeting Windows
``` yaml
  nodeSelector:
    beta.kubernetes.io/os: windows
    beta.kubernetes.io/arch: amd64
```

### Targeting Linux
``` yaml
  nodeSelector:
    beta.kubernetes.io/os: linux
    beta.kubernetes.io/arch: amd64
```

This is the most important part based on my experience, because if you using labels you created to select the needed nodes and not attaching ‘beta.kubernetes.io/os: windows’ selector like recommended to your app, you might get into trouble, and your pod may stuck in pending state with the error similar to this one: Failed create pod sandbox: rpc error: code = Unknown desc = [failed to set up sandbox container "…" network for pod "…": NetworkPlugin cni failed to set up pod "…" network: failed to parse Kubernetes args: pod does not have label vpc.amazonaws.com/PrivateIPv4Address...

Check you set node Selectors properly in this case, also if you have some problems you can read [this](https://github.com/aws/containers-roadmap/issues/542)

## Running the workflows on windows with Jenkins pipeline

In this example, I am using the ‘windows server core’ image and PowerShell to create a sample file and upload it to the s3 bucket, which you need to define.

I also store credentials for AWS in the ‘Vault’, I described in the previous post [how to read Vault’s secrets in Jenkins pipeline](http://igorzhivilo.com/jenkins/how-to-read-vault-secrets-from-declarative-pipeline/)

``` groovy
def secrets = [
  [path: 'secret/jenkins/aws', engineVersion: 2, secretValues: [
    [envVar: 'AWS_ACCESS_KEY_ID', vaultKey: 'aws_access_key_id'],
    [envVar: 'AWS_SECRET_ACCESS_KEY', vaultKey: 'aws_secret_access_key']]],
]
def configuration = [vaultUrl: "${env.VAULT_URL}",  vaultCredentialId: 'vault-approle', engineVersion: 2]
pipeline {
  agent {
    kubernetes {
      label 'workflow-example'
      defaultContainer 'jnlp'
      yaml """
kind: Pod
spec:
  containers:
  - name: jnlp
    image: jenkins/inbound-agent:windowsservercore-1809
  - name: shell
    image: mcr.microsoft.com/powershell:preview-windowsservercore-1809
    command:
    - powershell
    args:
    - Start-Sleep
    - 999999
  nodeSelector:
    beta.kubernetes.io/os: windows
    beta.kubernetes.io/arch: amd64
"""
    }
  }
  
  environment {
    branch = 'master' 
    workspace = '/home/jenkins/agent/workspace/workflow-example'
    s3_path = "s3://path_to_your_s3_bucket"
  }
  
  stages {
    stage('prepare') {
      steps {
        container('shell'){
          dir("${workspace}") {
            withVault([configuration: configuration, vaultSecrets: secrets]) {  
              powershell """
       
              echo "### Install chocolatey package manager ###"
              Set-ExecutionPolicy Bypass -Scope Process -Force;   [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))
              
              echo "### Install AWS cli ###"
              choco install awscli -y
              echo "### Create sample data for upload ###"
              echo 'Data sample' > data-sample.txt
              
              echo "### Upload to S3 ###"
              aws s3 cp .\\ ${s3_path} --acl public-read --recursive
              """
            }
          }
        }
      }
    }
  }
  
  options {
    buildDiscarder(logRotator(numToKeepStr:'30'))
    timeout(time: 60, unit: 'MINUTES')
    timestamps()
  }
}
```

## Conclusion

In this post, I showed you how to attach a windows worker nodes to already existing EKS cluster with Linux nodes and to run workflows on Windows with Jenkins pipeline. Of course, we also may create more advanced workflows when we running multiple stages in parallel using the Linux and Windows nodes and a lot of cool stuff. Thank you for reading and I hope it will be useful for you.

## References

[Amazon EKS Windows Container Support now Generally Available](https://aws.amazon.com/blogs/aws/amazon-eks-windows-container-support-now-generally-available/)

[Windows Worker Nodes](https://eksctl.io/usage/windows-worker-nodes/)

[Launching Amazon EKS Windows worker nodes](https://docs.aws.amazon.com/eks/latest/userguide/launch-windows-workers.html)

[Windows support](https://docs.aws.amazon.com/eks/latest/userguide/windows-support.html#windows-sample-application)

[kubernetes-plugin examples for windows](https://github.com/jenkinsci/kubernetes-plugin/blob/master/src/main/resources/org/csanchez/jenkins/plugins/kubernetes/pipeline/samples/windows.groovy)