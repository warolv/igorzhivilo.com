---
title: "Building the CI/CD of the Future, creating the VPC for EKS cluster"
date: 2020-07-15 12:24
comments: true
categories:
  - jenkins
tags:
  - jenkins
description: aws vpc, kubernetes jenkins,k8s jenkins, AWS EKS, CI-CD, k8s
keywords: 
  - aws vpc
  - aws eks ci-cd
  - kubernetes jenkins
  - k8s jenkins
  - jenkins pipeiline k8s
  - ci-cd k8s
sharing: true
draft: false
thumbnail: "/assets/images/jenkins-eks/vpc/1.png"
excerpt: "
<img src='/assets/images/jenkins-eks/vpc/1.png' align='center'/>  


This is the first post of tutorial in which I will describe how to create VPC for EKS cluster of our CI/CD based on Jenkins."

---

<img src="/assets/images/jenkins-eks/vpc/1.png" align="center"/> 

In this tutorial, I will share my experience as a DevOps engineer at Cloudify.co, this is the first post of tutorial in which I will describe how to create VPC for EKS cluster of our CI/CD based on Jenkins.

### Building the CI/CD of the Future published posts:

* [Introduction](https://igorzhivilo.com/jenkins/ci-cd-future-k8s-jenkins/)
* Creating the VPC for EKS cluster
* [Creating the EKS cluster](https://igorzhivilo.com/jenkins/ci-cd-future-k8s-jenkins-eks/)
* [Adding the Cluster Autoscaler](https://igorzhivilo.com/jenkins/ci-cd-future-k8s-jenkins-ca)
* [Add Ingress Nginx and Cert-Manager](https://igorzhivilo.com/jenkins/ci-cd-future-k8s-jenkins-ingress-cm/)
* [Install and configure Jenkins](https://igorzhivilo.com/jenkins/ci-cd-future-k8s-jenkins-install)
* [Create your first pipeline](https://igorzhivilo.com/jenkins/ci-cd-future-k8s-jenkins-pipeline)

## What is Amazon VPC?

Amazon Virtual Private Cloud (Amazon VPC) enables you to launch AWS resources into a virtual network that you've defined. This virtual network closely resembles a traditional network that you'd operate in your own data center, with the benefits of using the scalable infrastructure of AWS.

[AWS VPC](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html)

## Amazon VPC concepts

Subnet - A range of IP addresses in your VPC.

Route table - A set of rules, called routes, that are used to determine where network traffic is directed.

Internet gateway - A gateway that you attach to your VPC to enable communication between resources in your VPC and the internet.

VPC endpoint - Enables you to privately connect your VPC to supported AWS services and VPC endpoint services powered by PrivateLink without requiring an internet gateway, NAT device, VPN connection, or AWS Direct Connect connection. Instances in your VPC do not require public IP addresses to communicate with resources in the service. Traffic between your VPC and the other service does not leave the Amazon network.

[VPC concepts](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Subnets.html)

## Two options for creating VPC for EKS cluster

* Provision first your VPC using tools like CloudFormation or Terraform and then create an EKS cluster on top of it.

* Create a VPC using tools like 'eksctl' which creates automatically VPC for your EKS cluster.

Second option less preferred because you don't have full control over all the process, you can't be sure about aspects like worker nodes you provision will be a part of public subnet with attached public IP or in a private subnet.

You can read on the [AWS website](https://docs.aws.amazon.com/eks/latest/userguide/create-public-private-vpc.html
) more info about this

*If you deployed a VPC using eksctl or by using either of the Amazon EKS AWS CloudFormation VPC templates:
On or after 03/26/2020 - Public IPv4 addresses are automatically assigned by public subnets to new worker nodes deployed to public subnets.
Before 03/26/2020 - Public IPv4 addresses are not automatically assigned by public subnets to new worker nodes deployed to public subnets.*

Of course, if you do the provision of VPC using the 'eksctl' utility, you not completely understand what components created on AWS eventually, so I encourage you to do it manually, meaning first create the VPC and only then the EKS cluster.

## Another important consideration if VPC have

* Private subnets only
* Public subnets only
* Private and Public subnets

For the CI/CD case, the third option will be the best, I need private and public subnets, our Jenkins master will have a public IP and will be reachable through web hooks of Github. 

The workloads will be executed on worker nodes provisioned in private subnets which don't have a public IP and SSH access, according to security best practices.

### Recommended by AWS

*We recommend a VPC with public and private subnets so that Kubernetes can create public load balancers in the public subnets that load balance traffic to pods running on worker nodes that are in private subnets.*

I guess VPC with public subnets only used for demonstration purposes only, cause it does not feels very secure to have a public IP for each worker node you provision.

## Resiliency

Amazon EKS requires subnets in at least two Availability Zones, for resiliency, it is advisable to always have 2 public and 2 private subnets and ensure they are both in different availability zones.

Of course, more availability zones event better and more suitable for production cluster, but to simplify all the process I will create EKS cluster with two availability zones.

## Creating a VPC for EKS cluster

<img src="/assets/images/jenkins-eks/vpc/2.png" align="center"/>

To create VPC for our EKS cluster I will use AWS CloudFormation template

https://amazon-eks.s3.us-west-2.amazonaws.com/cloudformation/2020-06-10/amazon-eks-vpc-private-subnets.yaml

## VPC components of EKS cluster

* VPC: 192.168.0.0/16 (65534 hosts), [IP calculator](http://jodies.de/ipcalc?host=192.168.0.0&mask1=16&mask2=)
* 2 public subnets: 192.168.0.0/18 and 192.168.64.0/18, (16382 hosts in each subnet), [IP calculator](http://jodies.de/ipcalc?host=192.168.0.0&mask1=18&mask2=)
* 2 private subnets: 192.168.128.0/18 and 192.168.192.0/18 (16382 hosts in each subnet), [IP calculator](http://jodies.de/ipcalc?host=192.168.128.0&mask1=18&mask2=)
* InternetGateway connected to VPC and public subnets
* 2 NAT gateways with 2 Elastic IPs in public subnets, one in each public subnet. Each private subnet connected to NAT gateway via routing table
* Other components like RouteTables and RouteTableAssociation …

## Creating VPC for EKS cluster

### Prerequisites

* You must have an AWS account

### Creating IAM user on AWS with programmatic access

In AWS account go to Services -> IAM -> Users -> Add User

<img src="/assets/images/jenkins-eks/vpc/3.png" align="center"/>

Attach 'AdministratorAccess' policy

<img src="/assets/images/jenkins-eks/vpc/4.png" align="center"/>

I used 'AdministratorAccess' policy to simplify the process, otherwise you need to attach a lot of different policies for VPC/EKS creation and that not something I want to focus on in this tutorial.

Create the user and download .csv file with credentials for programmatic access to AWS

<img src="/assets/images/jenkins-eks/vpc/5.png" align="center"/>

### Install AWS Cli

https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html

### AWS configuration

``` bash
aws configure
```

Set your AWS Access Key ID / AWS Secret Access Key / Default region name from csv file you downloaded

### Create the VPC using the cloud formation template and AWS Cli

Download CloudFormation template from [here](https://amazon-eks.s3.us-west-2.amazonaws.com/cloudformation/2020-06-10/amazon-eks-vpc-private-subnets.yaml) , I assume file in 'downloads' folder, name of stack you creating is 'eks-vpc' and region is 'us-east-1'

``` bash
aws cloudformation create-stack --stack-name eks-vpc --template-body file:///Users/igor/downloads/eks-cluster/eks-cluster/amazon-eks-vpc-private-subnets.yaml --region=eu-west-1
```

In AWS account go to Services -> CloudFormation -> Stacks, you must see

<img src="/assets/images/jenkins-eks/vpc/6.png" align="center"/>

<img src="/assets/images/jenkins-eks/vpc/7.png" align="center"/>

<img src="/assets/images/jenkins-eks/vpc/8.png" align="center"/>

Please follow me on [Twitter (@warolv)](https://twitter.com/warolv)

For consulting gigs you can reach me on [Upwork](https://www.upwork.com/freelancers/warolv)

I will save all configuration created in this tutorial in my [Github](https://github.com/warolv/jenkins-eks)

This post on my [medium](https://medium.com/@warolv/building-the-ci-cd-of-the-future-creating-the-vpc-for-eks-cluster-a69b085441d1)
