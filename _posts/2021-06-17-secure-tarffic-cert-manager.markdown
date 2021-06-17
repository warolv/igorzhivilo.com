---
title: "Secure traffic to your application with Kubernetes and cert-manager"
date: 2021-06-17 09:24
comments: true
categories:
  - saas
tags:
  - saas
description: aws eks, kubernetes, ingress, ingress-nginx, cert-manager, let's encrypt, k8s, AWS EKS, saas
keywords: 
  - aws eks
  - kubernetes
  - k8s
  - ingress
  - ingress-nginx
  - cert-manager
  - tls
  - let's encrypt
sharing: true
draft: false
thumbnail: "/assets/images/saas-certs/1.png"
---

<img src="/assets/images/saas-certs/1.png" align="center"/> 

As a DevOps engineer at Cloudify.co, I am working on the creation of the Production Kubernetes (EKS) cluster with all needed mechanisms for our SaaS, including the TLS certificates issuing for secure communication to and within the k8s cluster.

In this tutorial, I will show how to secure external and internal traffic coming to your application on the Kubernetes cluster by issuing the TLS certificates with the Cert-Manager.

To simplify things let’s introduce the **‘simply’** web app which sits on the Kubernetes cluster, gets external traffic, and talks to DB (internal traffic) which also installed on the same k8s cluster.
Let’s make an assumption that we are able to reach the **‘simply’** app on this **simply.app.my-company.com** domain using the HTTP protocol (port 80).

## What I am trying to achieve?

1. Secure all external traffic to the ‘simply’ app using TLS certificate from Let’s Encrypt and adding communication through port 443 (HTTPS)
2. Secure internal traffic between the ‘simply’ app and DB using the self-signed certificate.


### What is NGINX Ingress?

> ingress-nginx is an Ingress controller for Kubernetes using NGINX as a reverse proxy and load balancer.

https://github.com/kubernetes/ingress-nginx

<img src="/assets/images/saas-certs/2.png" align="center"/> 

To install Nginx Ingress we will use the Helm package manager.

### What is cert-manager?

> cert-manager is a native Kubernetes certificate management controller. It can help with issuing certificates from a variety of sources, such as Let’s Encrypt, HashiCorp Vault, Venafi, a simple signing key pair, or self signed.
> It will ensure certificates are valid and up to date, and attempt to renew certificates at a configured time before expiry.
> It is loosely based upon the work of kube-lego and has borrowed some wisdom from other similar projects such as kube-cert-manager.

## So how to achieve this?

### Prerequisites

* Kubernetes cluster (EKS in my case)

* Ingress-Nginx installed to Kubernetes cluster

* Cert-Manager Installed to Kubernetes cluster

* Configured ‘A’ record which points to your Load Balancer created by Ingress, basically, an alias which points to created LB by Ingress.

You can read about the installation and configuration of all those components in details in my post: [Building the CI/CD of the Future, NGINX Ingress + Cert-Manager](http://igorzhivilo.com/jenkins/ci-cd-future-k8s-jenkins-ingress-cm/)

## Configure Cluster Issuer to issue Let’s Encrypt certificates

To obtain Let’s Encrypt certificates we need to create an issuer, it may be Issuer or ClusterIssuer, the difference is that an Issuer is scoped to a single namespace and ClusterIssuer is a cluster-wide version of an [Issuer](https://docs.cert-manager.io/en/release-0.8/reference/issuers.html).


**Creation of production ‘Cluster Issuer’ for Let’s Encrypt certificates:**

``` yaml
# cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    # The ACME server URL
    server: https://acme-v02.api.letsencrypt.org/directory
    # Email address used for ACME registration
    email: admin@app.my-company.com
    # Name of a secret used to store the ACME account private key
    privateKeySecretRef:
      name: letsencrypt-prod
    # Enable the HTTP-01 challenge provider
    solvers:
    - http01:
        ingress:
          class: nginx

```
We using [HTTP Validation](https://cert-manager.io/docs/tutorials/acme/http-validation/) and [ACME protocol](https://cert-manager.io/docs/tutorials/acme/http-validation/) for ClusterIssuer

Deploy cluster-issuer.yaml

``` bash
$ kubectl create -f cluster-issuer.yaml
```

### Issue a new Let’s Encrypt certificate with cert-manager for simply.app.my-company.com

To issue a new certificate we will create the Ingress-Nginx rule for the **simply.app.my-company.com** domain, which uses cert-manager and cluster-issuer we created to issue a certificate from Let’s encrypt.

> Pay attention to ‘annotations’ and ‘tls’ parts, you can see the magic of integration between ingress and cert-manager by using annotations.

``` yaml
# simply-ingress.yaml
apiVersion: extensions/v1
kind: Ingress
metadata:
  name: simply-ing
  annotations:
    kubernetes.io/ingress.class: "nginx"
    cert-manager.io/cluster-issuer: "letsencrypt-prod"
spec:
  tls:
  - hosts:
    - simply.app.my-company.com
    secretName: simply-tls-prod
  rules:
  - host: simply.app.my-company.com
    http:
      paths:
      - path: /
        backend:
          serviceName: simply-svc
          servicePort: 80
```

I make an assumption that you can reach the ‘simply’ app inside of the cluster via the ‘simply-svc’ service and port 80.

Deploy simply-ingress.yaml


``` bash
$ kubectl create -f simply-ingress.yaml
```

Now you need to wait till Cert-Manager acquires a certificate for the **simply.app.my-company.com** domain, it may take some time. When the certificate will be acquired you will be able to reach **simply.app.my-company.com** using HTTPS.

You can check acquired certificates and status using ‘kubectl’:

``` bash
$ kubectl get certificates -n cert-manager
```

### Issue self-signed certificate (signed by CA) with cert-manager for securing internal traffic between ‘simply’ and DB

> I will make an assumption that ‘simply’ will be deployed to ‘simplyns’ namespace:

``` bash
$ kubectl create ns simplyns
```

Create self-signed certificate issuer:

> notice that Issuer is scoped to a single namespace


``` yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  name: selfsigned-issuer
spec:
  selfSigned: {}
```

Create a CA certificate that will be used to sign other certificates:

> ‘isCA’ must be true

``` yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: simplyns-ca
spec:
  secretName: simplyns-ca-tls
  commonName: simplyns.svc.cluster.local
  usages:
    - server auth
    - client auth
  isCA: true
  issuerRef:
    name: selfsigned-issuer
```

Check generated certificate/secret created:

``` bash
$ kubectl get certificate simplyns-ca -n simplyns
$ kubectl get secret simplyns-ca-tls -n simplyns
```

Create an additional Issuer to issuer certificates signed by CA

> notice that we using previously generated for CA secret

``` yaml
apiVersion: cert-manager.io/v1
kind: Issuer
metadata:
  namespace: simplyns
  name: simply-ca-issuer
spec:
  ca:
    secretName: *simplyns-ca-tls*
```

And finally, generate a certificate signed by CA for ‘simply’ and DB communication:

> simply deployed to simplyns namespace

> db deployed to dbns namespace

> ‘simply.simplyns.svc.cluster.local’ is internal dns domain of ‘simply’

> ‘db.dbns.svc.cluster.local’ is internal dns domain of DB


``` yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  namespace: simplyns
  name: simply-cert
spec:
  secretName: simply-certs
  isCA: false
  usages:
    - server auth
    - client auth
  dnsNames:
  - "simply.simplyns.svc.cluster.local"
  - "db.dbns.svc.cluster.local"
  issuerRef:
    name: simply-ca-issuer

```

You can check generated secret is created:

``` bash
$ kubectl get secret simply-cert -n simplyns
```

Please follow me on [Twitter (@warolv)](https://twitter.com/warolv)

[My Github](https://github.com/warolv)

This post on my [medium](https://faun.pub/secure-traffic-to-your-application-with-kubernetes-and-cert-manager-cc2b44d29beb)