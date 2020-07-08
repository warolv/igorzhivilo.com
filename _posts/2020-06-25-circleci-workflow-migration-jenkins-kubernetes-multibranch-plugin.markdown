---
title: "CircleCI workflow migration to Jenkins on Kubernetes and using the Multibranch pipeline"
date: 2020-06-25 12:24
comments: true
categories:
  - jenkins
tags:
  - jenkins
description: jenkins ci, circleci, kubernetes, multibranch pipeline
keywords: 
  - jenkins
  - jenkins on k8s
  - kubernetes jenkins
  - circleci
  - jenkins pipeline
  - jenkins multibranch pipeline
sharing: true
draft: false
---

<img src="/assets/images/jenkins-circleci/1.jpeg" align="center"/> 

As a DevOps engineer at [Cloudify.co](http://www.cloudify.co) I am partially involved in migration of CicrleCI workflows to Jenkins on Kubernetes. In this article, I will try to share my knowledge on this topic and I hope it will be useful to you.

Let’s start.

### What is CircleCi?

CI/CD platform lets teams build and deliver great software, quickly and at scale, either in the cloud or on a self-hosted server.

[Circle CI](https://circleci.com/about/)

### What is Jenkins?

Jenkins is a self-contained, open source automation server which can be used to automate all sorts of tasks related to building, testing, and delivering or deploying software. 

[jenkins.io](https://jenkins.io/doc/)

### What is the Kubernetes plugin for Jenkins?

Jenkins plugin to run dynamic agents in a Kubernetes cluster.
The plugin creates a Kubernetes Pod for each agent started, defined by the Docker image to run, and stops it after each build.

[kubernetes plugin](https://plugins.jenkins.io/kubernetes/)

## CircleCI Workflow

### Used images: circleci/node:12.16

``` yaml
version: 2.1
defaults: &defaults
  docker:
    - image: circleci/node:12.16
  working_directory: ~/repo
```

### Defined Stages:

* Build: Install dependencies and run ‘npm build’
* Deploy: Publish created package to npmjs.org with ‘npm publish’
* Audit: Run security audit with ‘npm run audit’

``` yaml
jobs:
  build:
    <<: *defaults
    steps:
      - checkout
      - run:
          name: Install dependencies
          command: npm ci --prefer-offline
      - run:
          name: Build library
          command: npm run build
      - persist_to_workspace:
          root: ~/
          paths:
            - repo
  deploy:
    <<: *defaults
    steps:
      - attach_workspace:
          at: ~/
      - run:
          name: Publish package
          command: npm publish
     
  audit:
    <<: *defaults
    steps:
      -   attach_workspace:
            at: ~/
      -   run:
            name: Run npm production dependencies security audit
            command: npm run audit
```

### Defined Workflows

1. Build’ stage always runs first.
2. ‘Deploy’ stage depends on ‘build’ stage, meaning it will run after ‘build’ stage completed. Also, deploy branch runs only for branch starting with ‘publish-v’.
3. ‘Audit’ stage depends on ‘build’ stage, it will run after ‘build’ and only for the ‘master’ branch.
4. 2nd and 3rd may run in parallel after the 1st stage is finished.

``` yaml
workflows:
  version: 2
  build-deploy:
    jobs:
      - build
      - deploy:
          requires:
            - build
          filters:
            branches:
              only: /^publish-v.*/
      - audit:
          requires:
            - build
          filters:
            branches:
              only: master
```

### Let’s create this flow on Jenkins with multibranch pipeline

### Definition of pod template: build-pod.yaml

``` yaml
apiVersion: v1
kind: Pod
spec:
  containers:
  - name: node
    image: node:12.16
    command:
    - cat
    tty: true
```

### Jenkinsfile

``` groovy
pipeline {
  agent {
    kubernetes {
      label 'ci'
      defaultContainer 'jnlp'
      yamlFile 'jenkins/build-pod.yaml'
    }
  }
  
  environment {
    branch = "${env.BRANCH_NAME}"
    workspace = "${env.WORKSPACE}"
    project = "jenkins-example"
  }
options {
    checkoutToSubdirectory('jenkins-example')
  }
stages {
    stage('Build') {
      steps {
        container('node'){
          dir("${workspace}/${project}") {
            echo "Install dependencies"
            sh 'npm ci --prefer-offline'
            
            echo "Build library"
            sh 'npm run build'
          }
        }
      }
    }
    stage('Deploy') {
      when {
        expression { return branch =~ /^publish-v.*/ }
      }
      steps {
        container('node'){
          dir("${workspace}/${project}") {
            echo "Publish package"
            sh 'npm publish'
          }
        }
      }
    }
    stage('Audit'){
      when {
        branch 'master'
      }
      steps {
        container('node'){
          dir("${workspace}/${project}") {
            echo 'Run security audit'
            sh 'npm run audit'
          }
        }
      }
    }
  }
}
```

To simplify things, I am not running ‘Deploy’ and ‘Audit’ stages in parallel, which is not correct, so let’s fix that

``` groovy
stage('Run in parallel') {
  parallel {
    stage('Deploy') {
      when {
        expression { return branch =~ /^publish-v.*/ }
      }
      steps {
        container('node'){
          dir("${workspace}/${project}") {
            echo "Publish package"
            sh 'npm publish'
          }
        }
      }
    }
    stage('Audit'){
      when {
        branch 'master'
      }
      steps {
        container('node'){
          dir("${workspace}/${project}") {
            echo 'Run security audit'
            sh 'npm run audit'
          }
        }
      }
    }
  }
}
```

## Conclusion

As you can see in simple workflows like I showed we can migrate easily circleCI workflow to Jenkins on Kubernetes, you even can use the same images for the pipeline, sometimes it needs some tuning but it will work eventually.

Thank you for reading.
