---
title: "How To Read Vault’s Secrets from Jenkin’s Declarative Pipeline"
date: 2020-06-15 12:24
comments: true
categories:
  - jenkins
tags:
  - jenkins
description: vault secrets, jenkins pipeline
keywords: 
  - jenkins
  - jenkins pipeline
  - vault
  - vault secrets
  - jenkins declarative pipeline
sharing: true
draft: false
---
As a DevOps engineer at [Cloudify.co](http://cloudify.co) I am building a new CI/CD pipeline based on Kubernetes and Jenkins. I store my secrets in the vault and in this article I will describe my experience with the integration of vault into a Jenkins pipeline.



<img src="/assets/images/jenkins-vault/1.png" align="right"/> 




## What is HashiCorp’s Vault?

Vault is a tool for securely accessing secrets. A secret is anything that you want to tightly control access to, such as API keys, passwords, certificates, and more. Vault provides a unified interface to any secret, while providing tight access control and recording a detailed audit log.

[Vault project](https://www.vaultproject.io/)

## What is Jenkins Pipeline?
Jenkins Pipeline (or simply “Pipeline” with a capital “P”) is a suite of plugins which supports implementing and integrating continuous delivery pipelines into Jenkins.
<img src="/assets/images/jenkins-vault/2.png" align="right"/> 

[Jenkins pipeline](https://www.jenkins.io/doc/book/pipeline/)


## Prerequisites

* Vault Installed
* Jenkins Installed
* Basic knowledge on Jenkins

## What you will learn from this post?

* How to authenticate Jenkins to vault using AppRole and Jenkins’s HashiCorp Vault plugin
* Pull vault’s secrets from Jenkins declarative pipeline

## AppRole authentication method

How can a Jenkins server programmatically request a token so that it can read secrets from Vault?
Using the AppRole which is an authentication mechanism within Vault to allow machines or apps to acquire a token to interact with Vault and using the policies you can set access limitations for your app.

It uses RoleID and SecretID for login.

<img src="/assets/images/jenkins-vault/3.png" align="center"/> 


## Create AppRole and policy for Jenkins

AppRole creation based on my own experience and on this [tutorial](https://learn.hashicorp.com/vault/identity-access-management/approle)

[Enable approle and kv-2/secrets engine on vault](https://www.vaultproject.io/docs/secrets/kv/kv-v2)

### Enable approle on vault
``` bash
vault auth enable approle
```

###  Make sure a v2 kv secrets engine enabled
``` bash
vault secrets enable kv-v2
```

### Upgrading from Version 1 if you need it
``` bash
vault kv enable-versioning secret/
# Success! Tuned the secrets engine at: secret/
```

Make sure you understand what engine and version you are using before proceeding, because for the different version you will define your policy differently and if you are not doing it right you can waste a lot of time trying to figure why it’s not working (as I have found from my own experience).

## Create a policy for your approle, KV Secrets Engine Version2

### create jenkins-policy.hcl

``` bash
  tee jenkins-policy.hcl <<"EOF"
  path "secret/data/jenkins/*" {
    capabilities = [ "read" ]
  }
  EOF
```

### if you using KV 1 version the policy must look like

``` bash
  tee jenkins-policy.hcl <<"EOF"
  path "secret/data/jenkins/*" {
    capabilities = [ "read" ]
  }
  EOF
```

### create jenkins policy

``` bash
vault policy write jenkins jenkins-policy.hcl
```

### create approle jenkins and attached to a policy jenkins

``` bash
vault write auth/approle/role/jenkins token_policies=”jenkins” \
      token_ttl=1h token_max_ttl=4h
```

The token’s time-to-live (TTL) is set to 1 hour and can be renewed for up to 4 hours of its first creation

### Get RoleID and SecretID

``` bash
vault read auth/approle/role/jenkins/role-id
  
vault write -f auth/approle/role/jenkins/secret-id
```

Save the role-id and generated SecretID, you will need it

### Create github secret with 3 keys to read in jenkins pipeline

``` bash
  tee github.json <<"EOF"
  {
    "private-token": "76358746321876543",
    "public-token": "jhflkweb8y7432",
    "api-key": "80493286nfbds43"
  }
  EOF

  vault kv put secret/jenkins/github @github.json
```

## Read vault’s secrets from Jenkins declarative pipeline

[Install HashiCorp Vault jenkins plugin first](https://plugins.jenkins.io/hashicorp-vault-plugin/)

### Creating Vault App Role Credential in Jenkins

In Jenkins go to ‘Credentials’ -> ‘Add Credentials’, choose kind: Vault App Role Credential and add credential you created in the previous part (RoleId and SecretId)

<img src="/assets/images/jenkins-vault/4.png" align="center"/> 

### Create a simple declarative pipeline to test integration

``` groovy

  def secrets = [
  [path: 'secret/jenkins/github', engineVersion: 2, secretValues: [
    [envVar: 'PRIVATE_TOKEN', vaultKey: 'private-token'],
    [envVar: 'PUBLIC_TOKEN', vaultKey: 'public-token'],
    [envVar: 'API_KEY', vaultKey: 'api-key']]],
]
def configuration = [vaultUrl: 'http://my-vault.com:8200',  vaultCredentialId: 'vault-approle', engineVersion: 2]
                      
pipeline {
    agent any
    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds()
    }
    stages{   
      stage('Vault') {
        steps {
          withVault([configuration: configuration, vaultSecrets: secrets]) {
            sh "echo ${env.PRIVATE_TOKEN}"
            sh "echo ${env.PUBLIC_TOKEN}"
            sh "echo ${env.API_KEY}"
          }
        }  
      }
    }
}

```

If everything configured properly the output of Jenkins must look like

``` groovy
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Vault)
[Pipeline] wrap
[Pipeline] {
[Pipeline] sh
+ echo ****
****
[Pipeline] sh
+ echo ****
****
[Pipeline] sh
+ echo ****
****
[Pipeline] }
[Pipeline] // wrap
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // node
[Pipeline] End of Pipeline
Finished: SUCCESS
```

Otherwise, you will see access deny to vault message. If this the case then I recommend you go through all configuration again, check your policies and that you properly defined secret engine version. It’s also worth going through steps 4/5 of this [tutorial](https://learn.hashicorp.com/vault/identity-access-management/approle#step-4-login-with-roleid-secretid)

``` groovy
[Pipeline] {
[Pipeline] stage
[Pipeline] { (Vault)
[Pipeline] wrap
Access denied to Vault Secrets at 'secret/jenkins/github'
[Pipeline] {
[Pipeline] sh
+ echo null
null
[Pipeline] sh
+ echo null
null
[Pipeline] sh
+ echo null
null
[Pipeline] }
[Pipeline] // wrap
[Pipeline] }
[Pipeline] // stage
[Pipeline] }
[Pipeline] // node
[Pipeline] End of Pipeline
Finished: SUCCESS
```

## Conclusion ##

As you can see, integrating vault into the Jenkins pipeline is not so complex, if you do it properly and spend some time to understand exactly what engine and version you are using before proceeding. I hope this post was helpful to you and now the integration process seems more obvious.
Thank you for reading.

You can also find my article on medium: [How To Read Vault’s Secrets from Jenkin’s Declarative Pipeline](https://codeburst.io/read-vaults-secrets-from-jenkin-s-declarative-pipeline-50a690659d6)




