## Egress gateway creation and configuration.

   > **Note**: The steps explained here are oriented to this practical exercise of creating and using a calico cloud egress gateway in your EKS cluster. If you are interested in learning more about the theory behind the following steps, please refer to the [Calico Cloud documentation](https://docs.calicocloud.io/networking/egress/egress-gateway-aws).

9. Create the `IPReservation` for the AWS reserved IPs. This will avoid the Calico IPAM to allocate those IPs reserved by AWS to workloads.

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

10. Enable the support for the egress gateway per pod and per namespace. 

    ```bash
    kubectl patch felixconfiguration default --type='merge' -p \
        '{"spec":{"egressIPSupport":"EnabledPerNamespaceOrPerPod"}}'
    ```
    
    ```bash
    kubectl patch felixconfiguration.p default --type='merge' -p \
        '{"spec":{"policySyncPathPrefix":"/var/run/nodeagent"}}'
    ```

11. Enable the support for the secondary ENI on the nodes.

    ```bash
    kubectl patch felixconfiguration default --type='merge' -p \
        '{"spec":{"awsSecondaryIPSupport":"Enabled"}}'
    ```

    ```bash
    # verify the nodes for aws-seconday-ipv4 support: 
    kubectl describe node `kubectl get nodes -o=jsonpath='{.items[0].metadata.name}'` | grep aws-secondary
    ```

12. Create the `IPPool's` to be used by the second ENI on the nodes and by the egress gateway.

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
      name: egress-red-1a
    spec:
      cidr: 192.168.0.80/31
      allowedUses: ["Workload"]
      awsSubnetID: $SUBNETPUBEGW1AID
      blockSize: 32
      nodeSelector: "!all()"
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
    ---
    apiVersion: projectcalico.org/v3
    kind: IPPool
    metadata:
      name: egress-red-1b
    spec:
      cidr: 192.168.0.112/31
      allowedUses: ["Workload"]
      awsSubnetID: $SUBNETPUBEGW1BID
      blockSize: 32
      nodeSelector: "!all()"
      disableBGPExport: true
    EOF
    ```

    Check the `IPPool's` creation

    ```bash
    kubectl get ippools -o=custom-columns='NAME:.metadata.name,CIDR:.spec.cidr'
    ```

13. Copy the pull secret from `calico-system` namespace to the `default` namespace to authorize the download of the egress gateway image.

    ```bash
    kubectl get secret tigera-pull-secret --namespace=calico-system -o yaml | \
       grep -v '^[[:space:]]*namespace:[[:space:]]*calico-system' | \
       kubectl apply --namespace=default -f -
    ```





Creating the Egress Gatewey to test a perPod configuration







14. Create the egress gateway `red` in the `default` namespace.

    ```yaml
    kubectl apply -f - <<EOF
    apiVersion: apps/v1
    kind: Deployment
    metadata:
      name: egress-gateway-red
      namespace: default
      labels:
        egress-code: red
    spec:
      replicas: 2
      selector:
        matchLabels:
          egress-code: red
      template:
        metadata:
          annotations:
            cni.projectcalico.org/ipv4pools: '["egress-red-1a","egress-red-1b"]'
          labels:
            egress-code: red
        spec:
          topologySpreadConstraints:
          - maxSkew: 1
            topologyKey: topology.kubernetes.io/zone
            whenUnsatisfiable: DoNotSchedule
            labelSelector: 
              matchLabels:
                egress-code: red
          imagePullSecrets:
          - name: tigera-pull-secret
          nodeSelector:
            kubernetes.io/os: linux
          containers:
          - name: egress-gateway
            image: quay.io/tigera/egress-gateway:v3.14.1
            env:
            - name: EGRESS_POD_IP
              valueFrom:
                fieldRef:
                  fieldPath: status.podIP
            securityContext:
              privileged: true
            volumeMounts:
            - mountPath: /var/run
              name: policysync
            resources:
              requests:
                projectcalico.org/aws-secondary-ipv4: 1
              limits:
                projectcalico.org/aws-secondary-ipv4: 1
          terminationGracePeriodSeconds: 0
          volumes:
          - flexVolume:
              driver: nodeagent/uds
            name: policysync
    EOF
    ```
    After the egress gateway creation, you will have the following:

    ![egress-gateway-v0 0 1-Egress Gateway](https://user-images.githubusercontent.com/104035488/204859792-1a03f49e-7699-4eb8-817f-9267677d4dbe.png)

   Log in to the test host

    ```bash
    ssh -i ~/.ssh/$KEYPAIRNAME.pem ec2-user@$HOSTIPADDRESS
    ```

    Run `tcpdump` on the test host to capture traffic on port 7777, so you can observe the incoming packets and their parameters.
    
    ```bash
    sudo tcpdump -v -ni eth0 tcp port 7777 
    ```

16. Testing egress gateway with a **POD**. 

    Open another terminal and load the environment variables:

    ```bash
    source ~/egwLabVars.env
    ```

    Retrive the private IP address of the test host.

    ```bash
    HOSTPVTIPADDR=$(aws ec2 describe-instances \
      --instance-ids $HOSTINSTANCEID \
      --query "Reservations[*].Instances[*].PrivateIpAddress" \
      --output text \
      --no-cli-pager)
    # Persist for later sessions in case of disconnection.
    echo export HOSTPVTIPADDR=$HOSTPVTIPADDR >> ~/egwLabVars.env
    ```
   
    Create a pod named `netshoot-default` in the `default` namespace.

    ```yaml
    kubectl create -f - <<EOF
    apiVersion: v1
    kind: Pod
    metadata:
      name: netshoot-default
      labels:
        app: netshoot
    spec:
      containers:
      - image: nicolaka/netshoot:latest
        env:
         - name: HOSTPVTIPADDR
           value: '$HOSTPVTIPADDR'
        name: netshoot
        command: ["/bin/bash"]
        args: ["-c", "while true; do ping localhost; sleep 60; done"]
    EOF
    ```
    
    - **I.** First test the acess to the test host without using the egress gateway.
    
      Access the pod's shell.
      
      ```bash      
      kubectl exec -it netshoot-default -- /bin/bash
      ```

      Use `netcat` to create a connection to the test host, on the port 7777. 
     
      ```bash
      nc -zv $HOSTPVTIPADDR 7777
      ```

      Check the test host terminal. The packets captured with tcpdump shows the **node IP address** as source IP for the incomming packet. 

      If you are confused about the IP addresses, you can run the following kubectl command to see the egress gateway and the nodes with their IP addresses.

      ```bash
      kubectl get nodes -o=custom-columns='NAME:.metadata.name,INTERNAL IPADDR:.status.addresses[?(@.type == "InternalIP")].address'
      kubectl get pods  -o=custom-columns='NAME:.metadata.name,IP ADDRESS:.status.podIP'
      ```  

    - **II.** Now let's test the acess to the test host using the egress gateway `red`, previouly created.
    
      Open a third terminal and load the environment variables:
      
      ```bash
      source ~/egwLabVars.env
      ```

      Annotate the `netshoot-default` pod as following. This will cause the pod to use the egress gateway for egress traffic.

      ```bash
      kubectl annotate pods netshoot-default egress.projectcalico.org/selector="egress-code == 'red'"
      ```
      
      Go back to the terminal with the pod bash prompt and repeat the `netcat` command.
      
      ```bash
      nc -zv $HOSTPVTIPADDR 7777
      ```
      
      Look into the terminal connected to the test host. The packets captured with `tcpdump` shows the egress gateway IP address as source IP for the incoming packets. 
             
      You can stop the pod of using the egress gateway by removing the annotation previously done.

      ```bash
      kubectl annotate pods netshoot-default egress.projectcalico.org/selector-
      ```

