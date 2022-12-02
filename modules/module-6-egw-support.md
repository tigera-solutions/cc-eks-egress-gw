# Enabling egress gateway support

   > **Note**: The steps explained here are oriented to this practical exercise of creating and using a calico cloud egress gateway in your EKS cluster. If you are interested in learning more about the theory behind the following steps, please refer to the [Calico Cloud documentation](https://docs.calicocloud.io/networking/egress/egress-gateway-aws).

1. Create the `IPReservation` for the AWS reserved IPs. This will avoid the Calico IPAM to allocate those IPs reserved by AWS to workloads.

   ```yaml
   kubectl create -f - <<EOF
   apiVersion: projectcalico.org/v3
   kind: IPReservation
   metadata:
     name: aws-ip-reservations
   spec:
     reservedCIDRs:
     - 192.168.0.64/30
     - 192.168.0.95
     - 192.168.0.96/30
     - 192.168.0.127
   EOF
   ```

2. Enable the support for the egress gateway per pod and per namespace. 

    ```bash
    kubectl patch felixconfiguration default --type='merge' -p \
        '{"spec":{"egressIPSupport":"EnabledPerNamespaceOrPerPod"}}'
    ```
    
3. Enable policy sync API. The egress gateway container image requires the policy sync API to be enabled.

    ```bash
    kubectl patch felixconfiguration.p default --type='merge' -p \
        '{"spec":{"policySyncPathPrefix":"/var/run/nodeagent"}}'
    ```

4. Enable AWS-backed IP pools using the Secondary-IP-per-workload mode. To enable Secondary-IP-per-workload mode, set the field to `Enabled` (the name `Enabled` predates the addition of the **ENI-per-workload mode**):

    ```bash
    kubectl patch felixconfiguration default --type='merge' -p \
        '{"spec":{"awsSecondaryIPSupport":"Enabled"}}'
    ```

    ```bash
    # verify the nodes for aws-seconday-ipv4 support: 
    kubectl describe node `kubectl get nodes -o=jsonpath='{.items[0].metadata.name}'` | grep aws-secondary
    ```

5. Configure IP pools backed by VPC subnets. Create the `IPPool's` to be used by the second ENI on the nodes using the existing subnets.

    ```yaml
    kubectl create -f - <<EOF
    apiVersion: projectcalico.org/v3
    kind: IPPool
    metadata:
      name: hosts-1a
    spec:
      cidr: 192.168.0.64/28
      allowedUses: ["HostSecondaryInterface"]
      awsSubnetID: $SUBNETPUBEGW1AID
      blockSize: 32
      disableBGPExport: true
    ---
    apiVersion: projectcalico.org/v3
    kind: IPPool
    metadata:
      name: hosts-1b
    spec:
      cidr: 192.168.0.96/28
      allowedUses: ["HostSecondaryInterface"]
      awsSubnetID: $SUBNETPUBEGW1BID
      blockSize: 32
      disableBGPExport: true
    EOF
    ```

    Check the `IPPool's` creation

    ```bash
    kubectl get ippools -o=custom-columns='NAME:.metadata.name,CIDR:.spec.cidr'
    ```

6. Copy the pull secret from `calico-system` namespace to the `default` namespace to authorize the download of the egress gateway image.

    ```bash
    kubectl get secret tigera-pull-secret --namespace=calico-system -o yaml | \
       grep -v '^[[:space:]]*namespace:[[:space:]]*calico-system' | \
       kubectl apply --namespace=default -f -
    ```

---

[:arrow_right: Module 7 - Deploy an Egress Gateway for a per pod selection](/modules/module-7-egw-perpod.md) <br>

[:arrow_left: Module 5 - Create the test environment](/modules/module-5-test-environment.md)   
[:leftwards_arrow_with_hook: Back to Main](/README.md) 