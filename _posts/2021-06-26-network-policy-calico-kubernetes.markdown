---
title: "Network policy and Calico CNI to Secure a Kubernetes cluster"
date: 2021-06-26 09:24
comments: true
categories:
  - saas
tags:
  - saas
description: network policy, calico, cloudify, kubernetes, k8s, aws eks, AWS EKS
keywords: 
  - network policy
  - calico
  - cloudify
  - kubernetes
  - k8s
  - aws eks
sharing: true
draft: false
excerpt: "
<img src='/assets/images/network-policy/1.png' align='center'/> 



The main purpose of this post is to share my knowledge related to Calico CNI installation to the already existing EKS cluster and the **creation of Network Policies** to secure the cluster."

---

<img src="/assets/images/network-policy/1.png" align="center"/> 

As a DevOps engineer at Cloudify.co, I am working on the migration of the CaaS (Cloudify as a Service) solution to Kubernetes (EKS), previously it was running directly on AWS’s EC2 instances and my main goal was to migrate it to Kubernetes, which includes:

* Helm Chart creation for Cloudify as a Service solution.

* Creation of Kubernetes (EKS) cluster with all needed components like Ingress Nginx, Cert Manager for certificate issuing from Let’s encrypt and generating of self-signed certificates, securing the EKS cluster using the Network Policies, cluster monitoring with Prometheus/Grafana and ELK stack, and a lot of different other components.

* Deployment of CaaS environment to EKS cluster for each customer on demand, which is triggered when a customer fills the minimalistic registration form and managed by Cloudify Manager.

<img src="/assets/images/network-policy/2.png" align="center"/> 

https://cloudify.co/download

The **main purpose of this post** is to **share my knowledge** related to **Calico CNI** installation to the already existing EKS cluster and the **creation of Network Policies** to secure the cluster.

Let’s start.

### Cloudify

<img src="/assets/images/network-policy/3.png" align="center"/> 

Cloudify is an open source, multi-cloud orchestration platform featuring a unique ‘Environment as a Service’ technology that has the power to connect, automate and manage new & existing infrastructure and networking environments of entire application pipelines. Using Cloudify, DevOps teams (& infrastructure & operations groups) can effortlessly make a swift transition to public cloud and cloud-native architecture, and have a consistent way to manage all private & public environments. Cloudify is driven by a multidisciplinary team of industry experts and hero-talent.

https://cloudify.co/

### Cloudify as a Service (CaaS)

Cloudify As A Service — Hosted Trial
Experience Cloudify Premium with no installation and no downloads. Access ‘Cloudify as a Service’ and test our premium orchestration solution without the hassle… and on us for the first 30 days.

https://cloudify.co/download/

## What I am trying to achieve?

### How the EKS cluster with Multiple CaaS environments looks like?

To explain better what I am trying to achieve, I will show you first how the EKS cluster with multiple CaaS deployments looks like:

<img src="/assets/images/network-policy/4.png" align="center"/> 

* Each CaaS environment (one environment for each customer) has its own namespace in the EKS cluster, in this example, we have 3 CaaS environments (for 3 customers).

* Each CaaS environment in a separate namespace has three running pods: cloudify-manager / postgress / rabbitmq. The main component is clodify-manager which uses external DB (Postgres deployed via public helm chart to the same namespace) and external message broker (rabbitMQ deployed via public helm chart to the same namespace).

### So what I am trying to achieve?

1. Install Calico CNI to the existing EKS cluster and validate EKS still works properly.

2. Full isolation of CaaS environments (namespaces), by deploying **deny-all** policy to each namespace with CaaS, which drops all connections between pods inside of the namespace.

3. Whitelist ingress/egress connections for cloudify-manager pod on top of the **deny-all** network policy.

4. Whitelist ingress/egress connections for postgres pod on top of the **deny-all** network policy.

5. Whitelist ingress/egress connections for rabbitmq pod on top of the **deny-all** network policy.

6. Drop connections from cloudify-manager to any pod in a cluster outside of the namespace, permit external connections.( Internet, need it for different services of cloudify to work properly)

7. Permit connection to DNS (coredns) from cloudify-manager / postgress / rabbitmq pods.

## Installing Calico CNI to existing EKS cluster

Using this tutorial from AWS it was all pretty straightforward:

https://docs.aws.amazon.com/eks/latest/userguide/calico.html



``` bash
$ kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-operator.yaml 

$ kubectl apply -f https://raw.githubusercontent.com/aws/amazon-vpc-cni-k8s/master/config/master/calico-crs.yaml
```

### Creating EKS cluster for testing purposes

Of course, before running those ‘kubectl’ commands on the production cluster I tested it properly on ‘testing’ EKS cluster I created specifically for this purpose.

``` bash
# create calico-test EKS cluster with 3 nodes of t3.medium
$ eksctl create cluster \
  --region us-west-2 \
  --node-type t3.medium \
  --nodes 3 \
  --nodes-min 1 \
  --nodes-max 4 \
  --name calico-test
```

After the creation of the cluster for testing, I deployed CaaS to 3 namespaces and installed calico CNI by running the command I wrote above, then I validated everything still works properly.

My main fear was related to some connectivity problems which installation may cause because EKS by default use VPC CNI (Networking plugin for pod networking)

Amazon EKS supports native VPC networking with the Amazon VPC Container Network Interface (CNI) plugin for Kubernetes. This plugin assigns an IP address from your VPC to each pod.

After installing Calico CNI on top of VPC CNI I thought it may assign another IP(not from AWS’s VPC range) to pods and this way create some connectivity problems, but everything went well and no such behavior was observed.

### Testing network policies actually working

Deploying **deny-all** network policy to one of the namespaces and checking the connectivity:

``` yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

As a result, all connections between pods inside of the namespace were dropped, I was getting timeouts for all requests between pods.

<img src="/assets/images/network-policy/5.png" align="center"/> 

Then I deployed another network policy: **allow-all**

``` yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: allow-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  
  ingress:
  - {}
  egress:
  - {}
```

And everything is back to normal.

<img src="/assets/images/network-policy/6.png" align="center"/> 

It’s working, great:-)

Let’s create now network policies to isolate CaaS environments (namespaces) in the production EKS cluster.

## Creating network policies to isolate namespaces

### Full isolation of namespace with CaaS inside

Full isolation of namespace with CaaS inside, by deploying deny-all policy which will drop all traffic between pods inside of namespace you deployed it to.

``` yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### Whitelist ingress/egress connections of cloudify-manager

``` yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: cloudify-manager
spec:
  podSelector: 
    matchLabels:
      app: cloudify-manager
  policyTypes:
  - Ingress
  - Egress
  
  ingress:
  - ports:
    - protocol: TCP
      port: 80
    - protocol: TCP
      port: 443
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: postgres
    ports:
    - protocol: TCP
      port: 5432  
  - to:
    - podSelector:
        matchLabels:
          app: rabbitmq
    ports:
    - protocol: TCP
      port: 5672
    - protocol: TCP
      port: 5671
    - protocol: TCP
      port: 15672
    - protocol: TCP
      port: 15671
  

```

Allow ingress communication to 80/443 ports and egress communication with postgres and rabbitmq pods for specific ports.

### Whitelist ingress/egress connections of rabbitmq


``` yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: rabbitmq
spec:
  podSelector:
    matchLabels:
      app: rabbitmq
  ingress:
  - from:
      - podSelector:
          matchLabels:
            app: cloudify-manager
    ports:
      - protocol: TCP
        port: 5672
      - protocol: TCP
        port: 5671
        port: 15672
      - protocol: TCP
        port: 15671
```

Allow ingress only from cloudify-manager, no egress communications allowed.

### Whitelist ingress/egress connections of postgres

``` yaml
kind: NetworkPolicy
apiVersion: networking.k8s.io/v1
metadata:
  name: postgres
spec:
  podSelector:
    matchLabels:
      app: postgres
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: cloudify-manager
      ports:
        - protocol: TCP
          port: 5432
```

Allow ingress only from cloudify-manager, no egress communications allowed.

### Drop connections to any pod inside of cluster and permit external connections (internet)

``` yaml
egress
- to:
    - ipBlock:
        cidr: 0.0.0.0/0
        except:
          - 10.0.0.0/8
          - 192.168.0.0/16
          - 172.16.0.0/20
```

It basically means block all-local CIDRs, and permit external internet traffic.

This was added to cloudify-manager , because it’s the only pod that needs external access, but at the same time, I don’t want it possible to connect any other pod which is not whitelisted inside of the EKS cluster.

### Permit connection to DNS (coredns) from cloudify-manager / postgress / rabbitmq pods

``` yaml
egress:
  - ports:
    - protocol: TCP
      port: 53
    - protocol: UDP
      port: 53

```

<img src="/assets/images/network-policy/7.png" align="center"/> 

## Testing the network policies

For testing purposes, I deployed the first ‘hello-world’ pod to a namespace with CaaS and network policies inside:


``` bash
$ kubectl create deployment web --image=gcr.io/google-samples/hello-app:1.0

$ kubectl expose deployment web --type=ClusterIP --port=8080
```

Deployed the second ‘hello-world’ pod to a newly created namespace without network policies inside:

``` bash
# kubectl create ns web-test
$ kubectl create deployment web --image=gcr.io/google-samples/hello-app:1.0

$ kubectl expose deployment web --type=ClusterIP --port=8080
```

To validate we don’t have a connection from ‘cloudify-manager’ to web pod inside of the same namespace run:

``` bash
$ kubectl exec -it cloudify-manager-worker-0 bash
$ curl http://web:8080
Connection timed out
```

You will get a timeout. The same thing happens when you trying to connect to

web pod in web-test namespace:

``` bash
$ curl http://web.web-test:8080

# Connection timed out
```

Checking we have external connections:

``` bash
$ curl http://google.com
<HTML><HEAD><meta http-equiv="content-type" content="text/html;charset=utf-8">
<TITLE>301 Moved</TITLE></HEAD><BODY>
<H1>301 Moved</H1>
The document has moved
<A HREF="http://www.google.com/">here</A>.
</BODY></HTML>

```

We do!

To validate connection from cloudify-manager-worker to rabbitmq you can run:

``` bash
$ kubectl exec -it cloudify-manager-worker-0 bash
$ curl -k https://rabbitmq:15671
```

I hope you got the idea of how to validate connections. You can see the final result of all permitted and blocked connections on the image above (EKS cluster with network policies applied)


In this post, I described my experience with the installation of Calico CNI to EKS and Network Policies implementation to isolate the namespaces with CaaS and to secure the EKS cluster in general.

Thank you for reading, I hope you enjoyed it, see you in the next post.

If you want to be notified when the next post of this tutorial is published, please follow me on Twitter [@warolv](https://twitter.com/warolv).

Medium account: [warolv.medium.com](https://warolv.medium.com)

