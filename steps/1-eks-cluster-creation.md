# EKS Installation with Calico OSS

1. Define the variables

   ```bash 
   export INSTANCETYPE=t3.large
   export CLUSTERNAME=regis-eks-cluster
   export REGION=ca-central-1
   export K8SVERSION=1.23
   export KEYPAIRNAME=regis-egw-key
   ```

2. First, create an Amazon EKS cluster without any nodes.

   ```bash
   eksctl create cluster \
     --name $CLUSTERNAME \
     --region $REGION \
     --version $K8SVERSION \
     --without-nodegroup
   ```

3. Since this cluster will use Calico for networking, you must delete the aws-node daemon set to disable AWS VPC networking for pods.

   ```bash
   kubectl delete daemonset -n kube-system aws-node
   ```

4. Now that you have a cluster configured, you can install Calico.

   ```bash
   kubectl create -f https://projectcalico.docs.tigera.io/archive/v3.23/manifests/tigera-operator.yaml
   ```

5. Configure the Calico installation.

   ```bash
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

6. Finally, add nodes to the cluster.

   ```bash
   eksctl create nodegroup \
     --cluster $CLUSTERNAME \
     --region $REGION \
     --node-type $INSTANCETYPE \
     --nodes 3 \
     --max-pods-per-node 100 \
     --ssh-public-key $KEYPAIRNAME
   ```

7. Configure storage class

    >[Amazon CSI driver](https://docs.aws.amazon.com/eks/latest/userguide/ebs-csi.html) is required to be configured when using Amazon EBS storage since EKS 1.23 version.

    ```bash
    # install driver
    kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.12"

    # check driver pods status
    kubectl get pods -n kube-system | grep -i ebs-csi
    ```

8. Connect your cluster to Calico Cloud.

9. Deploy demo applications.

    ```bash
    # deploy boutiqueshop app stack
    kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/microservices-demo/release/v0.3.8/release/kubernetes-manifests.yaml
    ```

10. Clean up

    ```bash
    eksctl delete cluster --name $CLUSTERNAME --region $REGION
    ```

---

[Back to README.md](/README.md)