# Deploy an AWS EKS cluster using Calico CNI

1. Create the AWS EKS cluster connected to the two subnets designated for it in the previous step.
   
   ```bash
   eksctl create cluster \
     --name $CLUSTERNAME \
     --region $REGION \
     --version $K8SVERSION \
     --vpc-public-subnets $SUBNETPUBEKS1AID,$SUBNETPUBEKS1BID \
     --without-nodegroup
   ```
2. Uninstall the AWS VPC CNI and install **Calico CNI**.
   
   To install Calico CNI we need first remove the AWS VPC CNI and then install it.
   For further information about Calico CNI installation on AWS EKS, please refer to the [Project Calico documentation](https://projectcalico.docs.tigera.io/getting-started/kubernetes/managed-public-cloud/eks)

   **Steps**
   
   - Uninstall AWS VPN CNI

     ```bash
     kubectl delete daemonset -n kube-system aws-node
     ```

   - Install Calico CNI
 
     ```bash
     kubectl create -f https://projectcalico.docs.tigera.io/archive/v3.23/manifests/tigera-operator.yaml
     ```

   - Create the installation configuration.

     ```yaml
     kubectl create -f - <<EOF
     kind: Installation
     apiVersion: operator.tigera.io/v1
     metadata:
       name: default
     spec:
       kubernetesProvider: EKS
       cni:
         type: Calico
       calicoNetwork:
         bgp: Disabled
     EOF
     ```

3. Create the nodegroup and the nodes. Two nodes are enough to demonstrate the concept.

   ```bash
   eksctl create nodegroup $CLUSTERNAME-ng \
     --cluster $CLUSTERNAME \
     --region $REGION \
     --node-type $INSTANCETYPE \
     --nodes 2 \
     --nodes-min 0 \
     --nodes-max 2 \
     --max-pods-per-node 100 \
     --ssh-access \
     --ssh-public-key $KEYPAIRNAME
   ```
   
   After the node group and the nodes creation, the AWS resources should look like the following diagram:
   
   ![egress-gateway-v0 0 2-NodeGroups](https://user-images.githubusercontent.com/104035488/205450939-96cdf05b-f88d-4e96-8506-633f2cea579b.png)

4. Install the EBS driver for the EKS cluster

   ```bash
   # install EBS driver
   kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.12"
   ```

   ```bash
   # check driver pods status
   kubectl get pods -n kube-system -w | grep -i ebs-csi
   ```

---

[:arrow_right: Module 4 - Connect the AWS EKS cluster to Calico Cloud](/modules/module-4-connect-calicocloud.md) <br>

[:arrow_left: Module 2 - Getting Started](/modules/module-2-getting-started.md)  
[:leftwards_arrow_with_hook: Back to Main](/README.md)  
