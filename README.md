# Calico Cloud Egress Gateway on AWS EKS Cluster Workshop

## Welcome

Controlling the source IP seen when traffic leaves the cluster allows groups of pods to be identified by external firewalls, appliances and services (even as the groups are scaled up/down or pods restarted). Calico Cloud controls the source IP by directing traffic through one or more **egress gateway** pods, which change the source IP of the traffic to their own IP. The egress gateways used can be chosen at the pod or namespace scope allowing for flexibility in how the cluster is seen from outside.

This workshop intends to guide you step-by-step on creating an AWS EKS cluster, installing Calico as CNI, registering the cluster on Calico Cloud and creating an egress gateway for your applications to leave the Kubernetes cluster with a different IP address than the nodes or even with a fixed public IP address towards the Internet.

### Time Requirements

The estimated time to complete this workshop is 60-90 minutes.

### Target Audience

- Cloud Professionals
- DevSecOps Professional
- Site Reliability Engineers (SRE)
- Solutions Architects
- Anyone interested in Calico Cloud :)

### Learning Objectives

1. Learn how to configure the Calico Cloud Egress Gateway on an AWS EKS cluster.
2. Learn the main use cases for Egress Gateway.

## Modules

This workshop is organized in sequential modules. One module will build up on top of the previous module, so please, follow the order as proposed below.

Module 1 - [Prerequisites](/modules/module-1-prereq.md)  
Module 2 - [Getting Started](/modules/module-2-getting-started.md)  
Module 3 - [Deploy an AWS EKS cluster using Calico CNI](/modules/module-3-deploy-eks.md)  
Module 4 - [Connect the AWS EKS cluster to Calico Cloud](/modules/module-4-connect-calicocloud.md)  
Module 5 - [Create the test environment](/modules/module-5-test-environment.md)  
Module 6 - [Enable egress gateway support](/modules/module-6-egw-support.md)  
Module 7 - [Deploy Egress Gateway and use a pod selector](/modules/module-7-egw-perpod.md)  
Module 8 - [Deploy Egress Gateway and use a namespace selector](/modules/module-8-egw-pernamespace.md)  
Module 9 - [Deploy Egress Gateway with an AWS elastic IP](/modules/module-9-egw-elastic-ip.md)  
Module 10 - [Clean up](/modules/module-10-clean-up.md)  

> **Note**: The examples and sample code provided in this workshop are intended to be consumed as instructional content. These will help you understand how Calico Cloud can be configured to build a functional solution. These examples are not intended for use in production environments.