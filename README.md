# Calico Cloud Egress Gateway on an EKS Cluster 

This repo intends to guide you step-by-step on creating an EKS cluster, installing Calico OSS, registering the cluster on Calico Cloud and creating an egress gateway for your applications to leave the Kubernetes cluster with a different IP address than the nodes.

## Instructions

> **Note**: During this workshop, we'll set up some environment variables. If you're terminal session restarts, you may need to reset these variables. You can use that via the following command: <p>
`source ~/egwLabVars.env`

1. Define the initial environment variables for your EKS cluster:

   ```bash
   export CLUSTERNAME=rmart-egw
   export REGION=sa-east-1
   export K8SVERSION=1.23
   export INSTANCETYPE=t3.large
   export KEYPAIRNAME=rmart-egw-key
   ```

   Persist the enviroment variables for later sessions in case of disconnetion.
   
   ```bash
   echo "# Start Egress Gateway Lab Params" > ~/egwLabVars.env
   echo export CLUSTERNAME=$CLUSTERNAME >> ~/egwLabVars.env
   echo export REGION=$REGION >> ~/egwLabVars.env
   echo export K8SVERSION=$K8SVERSION >> ~/egwLabVars.env
   echo export INSTANCETYPE=$INSTANCETYPE >> ~/egwLabVars.env
   echo export KEYPAIRNAME=$KEYPAIRNAME >> ~/egwLabVars.env
   ```

2. Create a keypair if you don't have one or don't want to reuse any. Otherwise, just make sure that the KEYPAIRNAME environment variable is set with the name of your existing key pair.

   ```bash
   aws ec2 create-key-pair \
     --key-name $KEYPAIRNAME \
     --key-type rsa \
     --region $REGION \
     --query 'KeyMaterial' \
     --output text > ~/.ssh/$KEYPAIRNAME.pem
   ```

   Change the permissions of the private key.

   ```bash
   chmod 400 ~/.ssh/$KEYPAIRNAME.pem && \
   ls -la ~/.ssh/$KEYPAIRNAME.pem
   ```

   The expect output is:

   <pre>
   -r--------  1 regis  staff  1675 24 Nov 09:01 /Users/regis/.ssh/rmart-egw-key.pem
   </pre>

3. Create an EKS cluster with no node group.

   As we will only use 2 AZ in this workshop, let's get them mapped into the environment variables AZ1 and AZ2:
   
   ```bash
   AZ1=$(aws ec2 describe-availability-zones --region $REGION --query 'AvailabilityZones[0].ZoneName' --out text)
   # Persist for later sessions in case of disconnection.
   echo export AZ1=$AZ1 >> ~/egwLabVars.env
   ```
   
   ```bash
   AZ2=$(aws ec2 describe-availability-zones --region $REGION --query 'AvailabilityZones[1].ZoneName' --out text)
   # Persist for later sessions in case of disconnection.
   echo export AZ2=$AZ2 >> ~/egwLabVars.env
   ```
   
   Create the cluster to using only the 2 availability zones mapped in the previous step:
   
   ```bash
   eksctl create cluster \
     --name $CLUSTERNAME \
     --region $REGION \
     --zones $AZ1,$AZ2 \
     --version $K8SVERSION \
     --vpc-cidr 192.168.0.0/22 \
     --without-nodegroup
   ```
   
   For this workshop, we will not need many IP addresses, so a `/22` network is enough for demonstrating the concept.

4. After running the `eksctl create cluster` command, the AWS Cloudformation will create a VPC with two subnets per availability zone that will be used to allocate IPs for the nodes and pods. The subnets created are two public (one per availability zone) and two private (one per availability zone). This is done to allow you to deploy nodes in a public or private subnet according to your needs. By default, the node groups create nodes in the public subnets. 
   
   ![egress-gateway-Page-2](https://user-images.githubusercontent.com/104035488/204168127-978e4f60-c83d-4d52-bcae-4b8db4468bf9.png)

   As we will use Calico CNI, let's create subnets for its default `IPPool`. Also, let's define subnets to be used for the egress gateway.
   
   The final subnet segmentation of the VPC IP address `192.168.0.0/22` will look like:

   <pre>
   | Subnet address   |  Range of addresses | Description                                 | 
   | ---------------- | ------------------- | ------------------------------------------- |
   | 192.168.0.0/25   | 192.168.0.0 - 127   | EKS public subnet in AZ1                    |
   | 192.168.0.128/25 | 192.168.0.128 -255  | EKS public subnet in AZ2                    |
   | 192.168.1.0/25   | 192.168.1.0 - 127   | EKS private subnet in AZ1                   |
   | 192.168.1.128/25 | 192.168.1.128 - 255 | EKS private subnet in AZ2                   |
   | 192.168.2.0/25   | 192.168.2.0 - 127   | Calico default IPPool private subnet in AZ1 |
   | 192.168.2.128/25 | 192.168.2.128 - 255 | Calico default IPPool private subnet in AZ2 |
   | 192.168.3.0/25   | 192.168.3.0 - 127   | Egress gateway IPPool private subnet in AZ1 |
   | 192.168.3.128/25 | 192.168.3.128 - 255 | Egress gateway IPPool private subnet in AZ2 |
   </pre>

   To create the new subnets we need to retrieve the `VPC id` from the VPC created by EKS.

   ```bash
   VPCID=$(aws eks describe-cluster \
             --name $CLUSTERNAME \
             --query 'cluster.resourcesVpcConfig.vpcId' \
             --output text) && echo $VPCID
   # Persist for later sessions in case of disconnection.
   echo export VPCID=$VPCID >> ~/egwLabVars.env   
   ```
   
   Now, create the subnets in the EKS VPC.

   ```bash
   aws ec2 create-subnet \
     --vpc-id $VPCID \
     --cidr 192.168.2.0/25 \
     --availability-zone $AZ1 \
     --query 'Subnet.SubnetId' \
     --output text \
     --tag-specifications ResourceType=subnet,Tags=\[\{Key=Name,Value=SubnetPrivateCALICO1A\}\] \
       | export SUBNETIDCALICO1A=$(awk '{print $1}')
   ```
   ```bash
   aws ec2 create-subnet \
     --vpc-id $VPCID \
     --cidr 192.168.2.128/25 \
     --availability-zone $AZ2 \
     --query 'Subnet.SubnetId' \
     --output text \
     --tag-specifications ResourceType=subnet,Tags=\[\{Key=Name,Value=SubnetPrivateCALICO1B\}\] \
       | export SUBNETIDCALICO1B=$(awk '{print $1}')
   ```
   ```bash
   aws ec2 create-subnet \
     --vpc-id $VPCID \
     --cidr 192.168.3.0/25 \
     --availability-zone $AZ1 \
     --query 'Subnet.SubnetId' \
     --output text \
     --tag-specifications ResourceType=subnet,Tags=\[\{Key=Name,Value=SubnetPrivateEGW1A\}\] \
       | export SUBNETIDEGW1A=$(awk '{print $1}')
   ```
   ```bash
   aws ec2 create-subnet \
     --vpc-id $VPCID \
     --cidr 192.168.3.128/25 \
     --availability-zone $AZ2 \
     --query 'Subnet.SubnetId' \
     --output text \
     --tag-specifications ResourceType=subnet,Tags=\[\{Key=Name,Value=SubnetPrivateEGW1B\}\] \
       | export SUBNETIDEGW1B=$(awk '{print $1}')
   ```
   
   ```bash
   # Persist for later sessions in case of disconnection.
   echo export SUBNETIDCALICO1A=$SUBNETIDCALICO1A >> ~/egwLabVars.env
   echo export SUBNETIDCALICO1B=$SUBNETIDCALICO1B >> ~/egwLabVars.env
   echo export SUBNETIDEGW1A=$SUBNETIDEGW1A >> ~/egwLabVars.env
   echo export SUBNETIDEGW1B=$SUBNETIDEGW1B >> ~/egwLabVars.env
   ```
   
   After the custom subnets for Calico and the egress gateway were created the VPC will look like the following diagram: 

   ![subnets-created](https://user-images.githubusercontent.com/104035488/204161704-b983eec0-358d-4b17-a68c-d5698a795680.png)


5. Uninstall the AWS VPC CNI and install Calico CNI**
   
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
         hostPorts: Enabled
         ipPools:
         - blockSize: 28
           cidr: 192.168.2.0/24
           encapsulation: VXLAN
           natOutgoing: Enabled
           nodeSelector: all()
         linuxDataplane: Iptables
         multiInterfaceMode: None
         nodeAddressAutodetectionV4:
           canReach: 8.8.8.8
     EOF
     ```

6. Create the nodegroup and the nodes. For this workshop we will create only two nodes, which are enough to demonstrate the concept.

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

   ![nodegroup-deployed](https://user-images.githubusercontent.com/104035488/204168680-aed5ccbf-6470-4352-a26d-6fec906673de.png)
 
7. Install the EBS driver for the EKS cluster

   ```bash
   # install EBS driver
   kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.12"
   ```

   ```bash
   # check driver pods status
   kubectl get pods -n kube-system | grep -i ebs-csi
   ```

8. Connect your cluster to Calico Cloud.

   Connect the EKS cluster to [Calico Cloud](https://www.calicocloud.io/).
   If you don't have a Calico Cloud account, you can sign up for a free 14-day trial and get access to it immediately.

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
     - 192.168.1.0/30
     - 192.168.1.127
     - 192.168.1.128/30
     - 192.168.1.255
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
      cidr: 192.168.1.0/26
      allowedUses: ["HostSecondaryInterface"]
      awsSubnetID: subnet-0ea5e86bb9da707ff
      blockSize: 32
      disableBGPExport: true
    ---
    apiVersion: projectcalico.org/v3
    kind: IPPool
    metadata:
      name: egress-red-1a
    spec:
      cidr: 192.168.1.64/31
      allowedUses: ["Workload"]
      awsSubnetID: subnet-0ea5e86bb9da707ff
      blockSize: 32
      nodeSelector: "!all()"
      disableBGPExport: true
    ---
    apiVersion: projectcalico.org/v3
    kind: IPPool
    metadata:
      name: hosts-1b
    spec:
      cidr: 192.168.1.128/26
      allowedUses: ["HostSecondaryInterface"]
      awsSubnetID: subnet-04231c778d41e5a60
      blockSize: 32
      disableBGPExport: true
    ---
    apiVersion: projectcalico.org/v3
    kind: IPPool
    metadata:
      name: egress-red-1b
    spec:
      cidr: 192.168.1.192/31
      allowedUses: ["Workload"]
      awsSubnetID: subnet-04231c778d41e5a60
      blockSize: 32
      nodeSelector: "!all()"
      disableBGPExport: true
    EOF
    ```

    Check the `IPPool's` creation

    ```bash
    kubectl get ippools -o wide
    ```

13. Copy the pull secret from `calico-system` namespace to the `default` namespace to authorize the download of the egress gateway image.

    ```bash
    kubectl get secret tigera-pull-secret --namespace=calico-system -o yaml | \
       grep -v '^[[:space:]]*namespace:[[:space:]]*calico-system' | \
       kubectl apply --namespace=default -f -
    ```

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

    ![egress-gateway-Egress Gateway created](https://user-images.githubusercontent.com/104035488/204313504-6f2b61ed-2b66-4ed0-ab29-d057afc61504.png)

15. Create a test host to see the details of the packets received outside the EKS cluster.

    Retrieve the `subnet-id` of the public subnet with cidr block `192.168.0.0/25` created by the EKS to be used in your test host.
    
    ```bash
    HOSTSUBNETID=$(aws ec2 describe-subnets \
        --filters "Name=cidrBlock,Values=192.168.0.0/25" \
        --query 'Subnets[0].SubnetId' \
        --output text) && export HOSTSUBNETID
    # Persist for later sessions in case of disconnection.
    echo export HOSTSUBNETID=$HOSTSUBNETID >> ~/egwLabVars.env
    ```
    
    Create a segurity group for the test host opening the ports 22 for ssh connection and 7777 to receive test traffic.

    ```bash
    aws ec2 create-security-group \
      --group-name rmart-sg-test-host \
      --description "Security group for the test host" \
      --vpc-id $VPCID \
      --output yaml | export HOSTSGID=$(awk '{print $2}') \
      && echo $HOSTSGID
    # Persist for later sessions in case of disconnection.
    echo export HOSTSGID=$HOSTSGID >> ~/egwLabVars.env
    ```
    
    Open the port 22 for ssh access.

    ```bash
    aws ec2 authorize-security-group-ingress \
      --group-id $HOSTSGID \
      --protocol tcp \
      --port 22 \
      --cidr 0.0.0.0/0 \
      --no-cli-pager
    ```
    
    Open a port 7777 for testing traffic.

    ```bash
    aws ec2 authorize-security-group-ingress \
      --group-id $HOSTSGID \
      --protocol tcp \
      --port 7777 \
      --cidr 0.0.0.0/0 \
      --no-cli-pager
    ```

    Create the test host to receive and analyze the packets outside the EKS cluster.

    ```bash
    aws ec2 run-instances \
      --key-name $KEYPAIRNAME \
      --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
      --subnet-id $HOSTSUBNETID \
      --security-group-ids $HOSTSGID \
      --associate-public-ip-address \
      --instance-type t3.nano \
      --count 1 \
      --tag-specifications ResourceType=instance,Tags=\[\{Key=Name,Value=rmart-test-host\}\] \
      --output yaml \
        | export HOSTINSTANCEID=$(grep InstanceId | awk '{print $2}')
    # Persist for later sessions in case of disconnection.
    echo export HOSTINSTANCEID=$HOSTINSTANCEID >> ~/egwLabVars.env
    ```
    
    Once the test host is create, you should have the following picture of your AWS infrastructure:

    ![egress-gateway-Adding the Test Server](https://user-images.githubusercontent.com/104035488/204312482-52914dd2-0c91-44a1-ae7e-268eb701ef13.png)

    Retrive the test host ip address, so you can ssh into it.

    ```bash
    HOSTIPADDRESS=$(aws ec2 describe-instances \
      --instance-ids $HOSTINSTANCEID \
      --query "Reservations[*].Instances[*].PublicIpAddress" \
      --output text) && echo $HOSTIPADDRESS
    # Persist for later sessions in case of disconnection.
    echo export HOSTIPADDRESS=$HOSTIPADDRESS >> ~/egwLabVars.env
    ```

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
    
    Update the kubeconfig, if needed.

    ```bash
    aws eks update-kubeconfig --name $CLUSTERNAME --region $REGION 
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
      
      Update the kubeconfig, if needed.

      ```bash
      aws eks update-kubeconfig --name $CLUSTERNAME --region $REGION 
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

17. Testing egress gateway with a **NAMESPACE**

    Create another egress gateway

    - Create the `IPPool's` for the egress gateway `blue`.
    
      ```yaml
      kubectl apply -f - <<EOF
      apiVersion: projectcalico.org/v3
      kind: IPPool
      metadata:
        name: egress-blue-1a
      spec:
        cidr: 192.168.3.66/31
        allowedUses: ["Workload"]
        awsSubnetID: $SUBNETIDEGW1A
        blockSize: 32
        nodeSelector: "!all()"
        disableBGPExport: true
      ---
      apiVersion: projectcalico.org/v3
      kind: IPPool
      metadata:
        name: egress-blue-1b
      spec:
        cidr: 192.168.3.194/31
        allowedUses: ["Workload"]
        awsSubnetID: $SUBNETIDEGW1B
        blockSize: 32
        nodeSelector: "!all()"
        disableBGPExport: true
      EOF
      ```
      
      Verify the created  `IPPOOL's`

      ```bash
      kubectl get ippools
      ```
    
    - Create the egress gateway `blue`.

      ```yaml
      kubectl apply -f - <<EOF
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: egress-gateway-blue
        namespace: default
        labels:
          egress-code: blue
      spec:
        replicas: 2
        selector:
          matchLabels:
            egress-code: blue
        template:
          metadata:
            annotations:
              cni.projectcalico.org/ipv4pools: '["egress-blue-1a","egress-blue-1b"]'
            labels:
              egress-code: blue
          spec:
            topologySpreadConstraints:
            - maxSkew: 1
              topologyKey: topology.kubernetes.io/zone
              whenUnsatisfiable: DoNotSchedule
              labelSelector: 
                matchLabels:
                  egress-code: blue
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
      
      Verify the pods created for the egress gateway `blue`.
  
      ```bash
      kubectl get pods --output=custom-columns='NAME:.metadata.name,IP ADDRESS:.status.podIP'
      ```
  
    - Create the namespace `app-test` and the pod `netshoot-app-test` for the test.

      Create the namespace  `app-test`.

      ```bash
      kubectl create ns app-test
      ```
    
      Create the pod `netshoot-app-test` in the `app-test` namespace.
      
      ```yaml
      kubectl create -f - <<EOF
      apiVersion: v1
      kind: Pod
      metadata:
        name: netshoot-app-test
        namespace: app-test
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

    - **I.** First create test traffic to the test host from the pod `netshoot-app-test` in the `app-test` namespace without using the egress gateway.

      From the second terminal, execute the shell in the pod `netshoot-app-test`.

      ```bash
      kubectl exec -it -n app-test netshoot-app-test -- /bin/bash
      ```

      Use `netcat` to create a connection to the test host, on the port 7777.
      
      ```bash
      # nc to the test host ip
      nc -zv $HOSTPVTIPADDR 7777
      ```

      Check again the terminal connected to the test host. The packets captured with `tcpdump` shows the **node IP address** as source IP for the incomming packet.

        
    - **II.** Annotate the namespace `app-test` to start using the egress gateway `blue`.

      On the third terminal, create the following annotations to the namespace `app-test`.

      ```bash 
      kubectl annotate ns app-test egress.projectcalico.org/selector="egress-code == 'blue'"
      kubectl annotate ns app-test egress.projectcalico.org/namespaceSelector="projectcalico.org/name == 'default'"
      ```
      
      On the second terminal, executing the shell on the `netshoot-app-test` pod, run the following `netcat` command.
      
      ```bash
      nc -zv $HOSTPVTIPADDR 7777
      ```
            
      Look into the terminal connected to the test host. The packets captured with `tcpdump` shows the egress gateway IP address as source IP for the incoming packets. 
           
      You can stop the pod of using the egress gateway by removing the annotation previously done.
  
      ```bash
      kubectl annotate ns app-test egress.projectcalico.org/selector-
      kubectl annotate ns app-test egress.projectcalico.org/namespaceSelector-
      ```

    - **III.** Create another pod in the `app-test` namespace and repeat the tests.
      
      ```bash
      kubectl run -it --rm -n app-test another-pod --env="HOSTPVTIPADDR=$HOSTPVTIPADDR" --image nicolaka/netshoot:latest
      ```  
      
      Run the following `netcat` command and observer the packets arriving at the test host.

      ```bash
      nc -zv $HOSTPVTIPADDR 7777
      ```

      **Note that you did not need to annotated any pod. This is because the namespace has the annotations on it. So, any pod created inside the namespace will automatically use the egress gateway for egress traffic.** 

---

## Cleaning up the environment

1. Remove the test host

   ```bash
   aws ec2 terminate-instances \
     --instance-ids $HOSTINSTANCEID \
     --no-cli-pager
   ```

2. Remove the test host sg

   ```bash
   aws ec2 delete-security-group \
     --group-id $HOSTSGID \
     --no-cli-pager 
   ```
   > **Note**: If the command fails, wait a few minutes and try again.

3. Remove the nodegroup 

   ```bash
   eksctl delete nodegroup \
     --name $CLUSTERNAME-ng \
     --cluster $CLUSTERNAME \     
     --region $REGION \
     --drain false \
     --disable-eviction
   ```

4. Remove the custom subnets (wait 2-5 min after the nodegroup deletion process has ended.)

   ```bash
   aws ec2 delete-subnet \
   --subnet-id $SUBNETIDCALICO1A
   aws ec2 delete-subnet \
   --subnet-id $SUBNETIDCALICO1B
   aws ec2 delete-subnet \
   --subnet-id $SUBNETIDEGW1A
   aws ec2 delete-subnet \
   --subnet-id $SUBNETIDEGW1B
   ```

5. Remove the eks cluster

   ```bash
   eksctl delete cluster \
     --name $CLUSTERNAME \
     --region $REGION
   ```

6. Remove the keypair, if you created one:

   ```bash
   aws ec2 delete-key-pair \
     --key-name $KEYPAIRNAME
   # delete the private key stored locally
   rm -f ~/.ssh/$KEYPAIRNAME.pem
   ```

7. Remove the lab env params file:
   
   ```bash
   rm ~/egwLabVars.env
   ```