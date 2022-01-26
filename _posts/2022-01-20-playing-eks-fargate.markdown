---
title: "Playing with EKS Fargate"
date: 2022-01-20 09:24
comments: true
categories:
  - saas
tags:
  - saas
description: eks fargate, aws eks fargate, aws fargate, fargate, aws eks, kubernetes, k8s, AWS EKS, saas
keywords:
  - eks fargate
  - aws eks fargate
  - aws fargate
  - aws eks
  - kubernetes
  - k8s
sharing: true
draft: false
thumbnail: "/assets/images/eks-fargate/1.png"
excerpt: "
<img src='/assets/images/eks-fargate/1.png' align='center'/>  



The purpose of this tutorial is to deploy a 'simple' application to EKS Fargate.
In this tutorial, I will try to be practical as possible and deploy 'httpbin' application to EKS Fargate."

---

<img src='/assets/images/eks-fargate/1.png' align='center'/> 

The purpose of this tutorial is to deploy a 'simple' application to EKS Fargate.
In this tutorial, I will try to be practical as possible and deploy 'httpbin' application to EKS Fargate.

First, a regular EKS cluster with node groups will be created, then I will add the Fargate profile as 'play-with-fargate' namespace and every application deployed to this namespace will use Fargate.

> Hi, my name is Igor, I am a DevOps engineer from Cloudify

### AWS Fargate

> AWS Fargate is a technology that provides on-demand, right-sized compute capacity for containers. With AWS Fargate, you don't have to provision, configure, or scale groups of virtual machines on your own to run containers. You also don't need to choose server types, decide when to scale your node groups, or optimize cluster packing. You can control which pods start on Fargate and how they run with [Fargate profiles](https://docs.aws.amazon.com/eks/latest/userguide/fargate-profile.html). Fargate profiles are defined as part of your Amazon EKS cluster.

### httpbin

> A simple HTTP Request & Response Service.

[https://httpbin.org](https://httpbin.org/)

### Prerequisites

* AWS account with all needed permissions to create EKS cluster
* Installed [kubectl](https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/) and [eksctl](https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html)
* Installed [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)

## Let's provision the EKS cluster

Provision EKS cluster with **eksctl** to the region: **eu-west-3**, name: **fargate-cluster**

``` bash
eksctl create cluster \
 --name fargate-cluster \
 --region eu-west-3
```

<img src='/assets/images/eks-fargate/2.png' align='center'/> 

<img src='/assets/images/eks-fargate/3.png' align='center'/> 

<img src='/assets/images/eks-fargate/4.png' align='center'/> 


``` bash
kubectl get pods -A
kubectl get nodes
```

<img src='/assets/images/eks-fargate/5.png' align='center'/> 

## Add Fargate profile to an existing EKS cluster

``` bash
eksctl create fargateprofile \
 --cluster fargate-cluster \
 --name play-with-fargate \
 --namespace play-with-fargate \
 --region eu-west-3
```

<img src='/assets/images/eks-fargate/6.png' align='center'/> 

<img src='/assets/images/eks-fargate/7.png' align='center'/> 

<img src='/assets/images/eks-fargate/8.png' align='center'/> 

That is what you need to see in AWS Console -> Amazon Container Services, you need to be in the **eu-west-3** region.


### Let's test we can deploy applications to EKS Fargate

I will deploy Nginx to 'play-with-fargate' namespace:

``` bash
kubectl create ns play-with-fargate
kubectl create deployment nginx --image=nginx -n play-with-fargate
```

<img src='/assets/images/eks-fargate/9.png' align='center'/> 

Took some time to spin up the pod, almost 1 minute to be more precise before deployment status become 'ContainerCreated'. hmm, I feel some improvements are needed here:-)

<img src='/assets/images/eks-fargate/10.png' align='center'/> 

Fargate node provisioned on the fly.

<img src='/assets/images/eks-fargate/11.png' align='center'/> 

We can see Nginx indeed provisioned on Fargate node

### Let's delete the Nginx

``` bash
kubectl delete deployments nginx -n play-with-fargate
```

Next, I will deploy AWS Load Balancer Controller, to use ALB ingress with our application and make it externally accessible.

## Install AWS Load Balancer Controller to EKS

Based on this workshop: https://www.eksworkshop.com/beginner/180_fargate/prerequisites-for-alb/

### Create IAM OIDC provider

> This step is required to give IAM permissions to a Fargate pod running in the cluster using the IAM for Service Accounts feature.

``` bash
eksctl utils associate-iam-oidc-provider \
    --region eu-west-3 \
    --cluster fargate-cluster \
    --approve
```

<img src='/assets/images/eks-fargate/12.png' align='center'/> 

### Create an IAM policy

> The next step is to create the IAM policy that will be used by the AWS Load Balancer Controller.
This policy will be later associated to the Kubernetes Service Account and will allow the controller pods to create and manage the ELB's resources in your AWS account for you.

``` bash
curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.2.0/docs/install/iam_policy.json
aws iam create-policy \
    --policy-name AWSLoadBalancerControllerIAMPolicy \
    --policy-document file://iam_policy.json
rm iam_policy.json
```

### Create an IAM role and ServiceAccount for the Load Balancer controller

First, change ${ACCOUNT_ID} to your account, which you can find in the AWS console on the top -> right side

``` bash
eksctl create iamserviceaccount \
  --cluster fargate-cluster \
  --region eu-west-3 \
  --namespace kube-system \
  --name aws-load-balancer-controller \
  --attach-policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/AWSLoadBalancerControllerIAMPolicy \
  --override-existing-serviceaccounts \
  --approve
```

<img src='/assets/images/eks-fargate/13.png' align='center'/> 

> The above command deploys a CloudFormation template that creates an IAM role and attaches the IAM policy to it.

### Install the TargetGroupBinding CRDs

``` bash
kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"
```

<img src='/assets/images/eks-fargate/14.png' align='center'/> 

### Install the AWS Load Balancer Controller

You need your VPC ID first:

``` bash
aws eks describe-cluster \
  --name fargate-cluster \
  --region eu-west-3 \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text
```

Change vpcId before executing the next command.

``` bash
helm repo add eks https://aws.github.io/eks-charts
helm upgrade -i aws-load-balancer-controller eks/aws-load-balancer-controller \
--set clusterName=fargate-cluster \
--set serviceAccount.create=false \
--set region=eu-west-3 \
--set vpcId=vpc-xxxxx \
--set serviceAccount.name=aws-load-balancer-controller -n kube-system
```

<img src='/assets/images/eks-fargate/15.png' align='center'/> 

### Verify that the AWS Load Balancer Controller is installed

``` bash
kubectl get deployment -n kube-system aws-load-balancer-controller
```

## Let's deploy our application: httpbin

'httpbin' will be deployed to 'play-with-fargate' namespace

All manifests combined in all-resources.yaml:

``` yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: httpbin
  namespace: play-with-fargate
---
apiVersion: v1
kind: Service
metadata:
  name: httpbin
  namespace: play-with-fargate
  labels:
    app: httpbin
    service: httpbin
spec:
  ports:
  - name: http
    port: 8000
    targetPort: 80
  selector:
    app: httpbin
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: httpbin
  namespace: play-with-fargate
spec:
  replicas: 1
  selector:
    matchLabels:
      app: httpbin
  template:
    metadata:
      labels:
        app: httpbin
    spec:
      serviceAccountName: httpbin
      containers:
      - image: docker.io/kennethreitz/httpbin
        name: httpbin
        ports:
        - containerPort: 80
```

You can find gist with all commands and manifests here: [https://gist.github.com/warolv/e982ccce78a6b78c40cea4227c13912f](https://gist.github.com/warolv/e982ccce78a6b78c40cea4227c13912f)

``` bash
kubectl apply -f all-resources.yaml
```

<img src='/assets/images/eks-fargate/16.png' align='center'/> 

<img src='/assets/images/eks-fargate/17.png' align='center'/> 

### Let's connect to httpbin using the port-forwarding

Will use 'kubectl port-forward' to get access to httpbin

<img src='/assets/images/eks-fargate/18.png' align='center'/> 

<img src='/assets/images/eks-fargate/19.png' align='center'/> 

Looks good:-)

The only thing left is to access this application **externally**, will use 'AWS Load Balancer Controller' we installed and 'ingress' manifest.

'AWS Load Balancer Controller' will provision ALB on AWS behind the scenes.

### Ingress for httpbin

``` yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
  name: httpbin-ingress
spec:
  rules:
    http:
      paths:
      - pathType: Prefix
        path: "/"
        backend:
          service:
            name: httpbin
            port:
              number: 8000

```

<img src='/assets/images/eks-fargate/20.png' align='center'/> 

<img src='/assets/images/eks-fargate/21.png' align='center'/> 

<img src='/assets/images/eks-fargate/22.png' align='center'/> 

Provision ALB may take a couple of minutes, be patient.

Success! :-)

**annotations: 'kubernetes.io/ingress.class: alb'** instructs AWS Load Balancer Controller to create ALB on AWS for this application.

**alb.ingress.kubernetes.io/scheme: internet-facing** instructs AWS Load Balancer Controller to create external LB for this application and not internal.

You can find **gist** with all commands and manifests here: [https://gist.github.com/warolv/e982ccce78a6b78c40cea4227c13912f](https://gist.github.com/warolv/e982ccce78a6b78c40cea4227c13912f)

In this tutorial, I explained how to add a Fargate profile to an existing EKS cluster, how to deploy 'httpbin' application, and to provision AWS Load Balancer Controller to make the application accessible externally.

Thank you for reading, I hope you enjoyed it, see you in the next post.

If you want to be notified when the next post of this tutorial is published, please follow me on Twitter [@warolv](https://twitter.com/warolv).

For consulting gigs you can reach me on [Upwork](https://www.upwork.com/freelancers/warolv)

Instagram: [@warolv](https://www.instagram.com/warolv)

My medium account: warolv.medium.com