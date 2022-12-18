# Module 1 - Prerequisites

1. For this workshop we recommend you to install the following tools:

- AWS CLI upgrade to v2

  [Installation instructions](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
  
   
  Linux installation:
  
  ```bash
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
  unzip awscliv2.zip
  sudo ./aws/install
  aws --version
  ```

- eksctl

  [Installation instructions](https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html)
  
  Linux installation

  ```bash
  curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
  sudo mv /tmp/eksctl /usr/local/bin
  eksctl version
  ```

- EKS kubectl

  [Installation instructions](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html)
  
  Linux installation:

  ```bash
  curl -o /tmp/kubectl https://s3.us-west-2.amazonaws.com/amazon-eks/1.23.7/2022-06-29/bin/linux/amd64/kubectl
  sudo chmod +x /tmp/kubectl
  sudo mv /tmp/kubectl /usr/local/bin
  kubectl version --short --client
  ```

- git

  [Installation instructions](https://git-scm.com/book/en/v2/Getting-Started-Installing-Git)

  Linux Amazon/Centos:

  ```bash
  sudo yum install git-all -y
  git --version
  ```

2. Clone this repository and change directory to it.
   
   ```bash
   git clone git@github.com:tigera-solutions/cc-eks-egress-gw.git && \
   cd cc-eks-egress-gw
   ```
<!--   git clone --branch v0.0.2 git@github.com:regismartins/cc-eks-egress-gw.git && \ -->
---

[:arrow_right: Module 2 - Getting Started](/modules/module-2-getting-started.md) <br> 

[:leftwards_arrow_with_hook: Back to Main](/README.md)
