# Egress Gateway on an EKS Cluster

This repo intents to guide you step-by-step on the process of creating a EKS cluster, install Calico OSS, register on Calico Cloud and create an egress gateway for your applications to leave the cluster with an specific IP address different from the node IP address.

## Instructions

> NOTE: In the following sections we'll be generating and setting some environment variables. If you're terminal session restarts you may need to reset these variables. You can use that via the following command: <p>
`source ~/egwLabVars.env`

1. Define the variables:

   ```bash
   export CLUSTERNAME=rmart-egw
   export REGION=sa-east-1
   export K8SVERSION=1.23
   export INSTANCETYPE=t3.large
   export KEYPAIRNAME=rmart-egw-key
   ```

   ```bash
   # Persist for Later Sessions in Case of Timeout
   echo "# Start Egress Gateway Lab Params" > ~/egwLabVars.env
   echo export CLUSTERNAME=$CLUSTERNAME >> ~/egwLabVars.env
   echo export REGION=$REGION >> ~/egwLabVars.env
   echo export K8SVERSION=$K8SVERSION >> ~/egwLabVars.env
   echo export INSTANCETYPE=$INSTANCETYPE >> ~/egwLabVars.env
   echo export KEYPAIRNAME=$KEYPAIRNAME >> ~/egwLabVars.env
   ```

2. Create a keypair if you don't have one or don't want to reuse any.

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

   ```bash
   -r--------  1 regis  staff  1675 24 Nov 09:01 /Users/regis/.ssh/rmart-egw-key.pem
   ```

3. Create an EKS cluster with no node group.

   As we will only use 2 AZ in this tutorial, let's get them mapped into the environmnet variables AZ1 and AZ2:
   
   ```bash
   AZ1=$(aws ec2 describe-availability-zones --region $REGION --query 'AvailabilityZones[0].ZoneName' --out text)
   # Persist for Later Sessions in Case of Timeout
   echo export AZ1=$AZ1 >> ~/egwLabVars.env
   ```
   
   ```bash
   AZ2=$(aws ec2 describe-availability-zones --region $REGION --query 'AvailabilityZones[1].ZoneName' --out text)
   # Persist for Later Sessions in Case of Timeout
   echo export AZ2=$AZ2 >> ~/egwLabVars.env
   ```
   
   Create the cluster to using only the 2 availability zones.
   
   ```bash
   eksctl create cluster \
     --name $CLUSTERNAME \
     --region $REGION \
     --zones $AZ1,$AZ2 \
     --version $K8SVERSION \
     --vpc-cidr 192.168.0.0/22 \
     --without-nodegroup
   ```
   For this workshop, we will not need many IP addresses, so a /22 network is enough for demonstrating the concept.

4. Cloudformation will create a VPC with 2 networks that will be used to allocate IPs for the nodes and pods.

   As we will use Calico CNI, let's create subnets for the default ippool. Also, lets create subnets to be used for the egress gateway.
   
   The final ip subnet distribution will look like:
   
   <pre>
   192.168.0.0/25        eks-pub-1a \
   192.168.0.128/25      eks-pub-1b | Created by eksctl
   192.168.1.0/25        eks-pvt-1a | using cloud formation
   192.168.1.128/25      eks-pvt-1b /
   192.168.2.0/25        calico-pvt-1a \ Subnet for Calico CNI ippool
   192.168.2.128/25      calico-pvt-1b /
   192.168.3.0/25        egw-pvt-1a \ Subnets for the egress gw 
   192.168.3.128/25      egw-pvt-1b / (secondary ifs and e-gws)
   </pre>

   To create the new subnets we need to retrieve the VPC id from the VPC created by EKS.

   ```bash
   VPCID=$(aws eks describe-cluster \
             --name $CLUSTERNAME \
             --query 'cluster.resourcesVpcConfig.vpcId' \
             --output text) && echo $VPCID
   # Persist for Later Sessions in Case of Timeout
   echo export VPCID=$VPCID >> ~/egwLabVars.env   
   ```
   
   Now, create the subnets:

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
   # Persist for Later Sessions in Case of Timeout
   echo export SUBNETIDCALICO1A=$SUBNETIDCALICO1A >> ~/egwLabVars.env
   echo export SUBNETIDCALICO1B=$SUBNETIDCALICO1B >> ~/egwLabVars.env
   echo export SUBNETIDEGW1A=$SUBNETIDEGW1A >> ~/egwLabVars.env
   echo export SUBNETIDEGW1B=$SUBNETIDEGW1B >> ~/egwLabVars.env
   ```


5. Uninstall the AWS VPC CNI and install Calico CNI
   
   Uninstall AWS VPN CNI

   ```bash
   kubectl delete daemonset -n kube-system aws-node
   ```

   Install Calico cni
 
   ```bash
   kubectl create -f https://projectcalico.docs.tigera.io/archive/v3.23/manifests/tigera-operator.yaml
   ```

6. Create the installation configurarion.

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

7. Create the nodegroup and the nodes

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

8. Install the EBS driver for the EKS cluster

   ```bash
   # install EBS driver
   kubectl apply -k "github.com/kubernetes-sigs/aws-ebs-csi-driver/deploy/kubernetes/overlays/stable/?ref=release-1.12"
   ```

   ```bash
   # check driver pods status
   kubectl get pods -n kube-system | grep -i ebs-csi
   ```

9. Connect to Calico Cloud.

   Connect your EKS cluster to [Calico Cloud](https://www.calicocloud.io/)

10. Create the IP reservations for the AWS reserved ips

    ```yaml
    kubectl create -f - <<EOF
    apiVersion: projectcalico.org/v3
    kind: IPReservation
    metadata:
      name: aws-ip-reservations
    spec:
      reservedCIDRs:
      - 192.168.2.0/30
      - 192.168.2.127
      - 192.168.2.128/30
      - 192.168.2.255
      - 192.168.3.0/30
      - 192.168.3.127
      - 192.168.3.128/30
      - 192.168.3.255
    EOF
    ```

11. Enable the support for the egress gateway per pod and per namespace. 

    ```bash
    kubectl patch felixconfiguration default --type='merge' -p \
        '{"spec":{"egressIPSupport":"EnabledPerNamespaceOrPerPod"}}'
    ```
    
    ```bash
    kubectl patch felixconfiguration.p default --type='merge' -p \
        '{"spec":{"policySyncPathPrefix":"/var/run/nodeagent"}}'
    ```

12. Enable the support for the secondary eni on the nodes.

    ```bash
    kubectl patch felixconfiguration default --type='merge' -p \
        '{"spec":{"awsSecondaryIPSupport":"Enabled"}}'
    ```

    ```bash
    # verify the nodes for aws-seconday-ipv4 support: 
    kubectl describe node `kubectl get nodes -o=jsonpath='{.items[0].metadata.name}'` | grep aws-secondary
    ```

13. Create the IPpools to be used by the second eni on the nodes and by the egress gateway.

    ```yaml
    kubectl create -f - <<EOF
    apiVersion: projectcalico.org/v3
    kind: IPPool
    metadata:
      name: hosts-1a
    spec:
      cidr: 192.168.3.0/26
      allowedUses: ["HostSecondaryInterface"]
      awsSubnetID: $SUBNETIDEGW1A
      blockSize: 32
      disableBGPExport: true
    ---
    apiVersion: projectcalico.org/v3
    kind: IPPool
    metadata:
      name: egress-red-1a
    spec:
      cidr: 192.168.3.64/31
      allowedUses: ["Workload"]
      awsSubnetID: $SUBNETIDEGW1A
      blockSize: 32
      nodeSelector: "!all()"
      disableBGPExport: true
    ---
    apiVersion: projectcalico.org/v3
    kind: IPPool
    metadata:
      name: hosts-1b
    spec:
      cidr: 192.168.3.128/26
      allowedUses: ["HostSecondaryInterface"]
      awsSubnetID: $SUBNETIDEGW1B
      blockSize: 32
      disableBGPExport: true
    ---
    apiVersion: projectcalico.org/v3
    kind: IPPool
    metadata:
      name: egress-red-1b
    spec:
      cidr: 192.168.3.192/31
      allowedUses: ["Workload"]
      awsSubnetID: $SUBNETIDEGW1B
      blockSize: 32
      nodeSelector: "!all()"
      disableBGPExport: true
    EOF
    ```

    ```bash
    # check the ippools creation
    kubectl get ippools -o wide
    ```

14. Copy the pull secret from calico-system ns to the default ns to authorize the download of the egw image

    ```bash
    kubectl get secret tigera-pull-secret --namespace=calico-system -o yaml | \
       grep -v '^[[:space:]]*namespace:[[:space:]]*calico-system' | \
       kubectl apply --namespace=default -f -
    ```

15. Install the egress gw red in the default ns.

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

16. Create a test host to see the how the packets details from outside the eks cluster.

    ```bash
    # get the subnet id of the host az1 subnet
    HOSTSUBNETID=$(aws ec2 describe-subnets \
        --filters "Name=cidrBlock,Values=192.168.0.0/25" \
        --query 'Subnets[0].SubnetId' \
        --output text) && export HOSTSUBNETID
    # Persist for Later Sessions in Case of Timeout
    echo export HOSTSUBNETID=$HOSTSUBNETID >> ~/egwLabVars.env
    ```
    
    Create a segurity group
    ```bash
    aws ec2 create-security-group \
      --group-name rmart-sg-test-host \
      --description "Security group for the test host" \
      --vpc-id $VPCID \
      --output yaml | export HOSTSGID=$(awk '{print $2}') \
      && echo $HOSTSGID
    # Persist for Later Sessions in Case of Timeout
    echo export HOSTSGID=$HOSTSGID >> ~/egwLabVars.env
    ```
    
    Open a port for ssh access
    ```bash
    aws ec2 authorize-security-group-ingress \
      --group-id $HOSTSGID \
      --protocol tcp \
      --port 22 \
      --cidr 0.0.0.0/0 \
      --no-cli-pager
    ```
    
    Open a port for testing egress gw
    ```bash
    aws ec2 authorize-security-group-ingress \
      --group-id $HOSTSGID \
      --protocol tcp \
      --port 7777 \
      --cidr 0.0.0.0/0 \
      --no-cli-pager
    ```

    ```bash
    # create the instance
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
    ```

    ```bash
    # retrive the host ip address
    HOSTIPADDRESS=$(aws ec2 describe-instances \
      --instance-ids $HOSTINSTANCEID \
      --query "Reservations[*].Instances[*].PublicIpAddress" \
      --output text) && echo $HOSTIPADDRESS
    ```
    
    ```bash
    # log in to the text host
    ssh -i ~/.ssh/$KEYPAIRNAME.pem ec2-user@$HOSTIPADDRESS
    ```

    ```bash
    # run
    sudo tcpdump -v -ni eth0 tcp port 7777 
    ```

17. Create a pod for testing

    - Open another terminal
    
    ```yaml
    # create the pod
    
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
        name: netshoot
        command: ["/bin/bash"]
        args: ["-c", "while true; do ping localhost; sleep 60; done"]
    EOF
    ```
    
    a. Test w/o egress-gw
    
       ```bash
       # get the pvt ip from the test host:
       
       aws ec2 describe-instances \
         --instance-ids $INSTANCEIDHOST \
         --query "Reservations[*].Instances[*].PrivateIpAddress" \
         --output table \
         --no-cli-pager
       ```

       example output:
       
       <pre>
       -------------------
       |DescribeInstances|
       +-----------------+
       |  192.168.0.113  |
       +-----------------+
       </pre>

       ```bash      
       # connect to the pod
       kubectl exec -it netshoot-default -- /bin/bash
       ```

       ```bash
       # nc to the test host ip
       nc -zv 192.168.0.113 7777
       ```

       The packet captured with tcpdump in the test host shows the cluster IP as source IP. 
       
    
    b. Test w/ egress-gw
    
       - Open a third terminal
       
       ```bash
       # annotate the pod
       kubectl annotate pods netshoot-default egress.projectcalico.org/selector="egress-code == 'red'"
       ```

       Go back to the pod bash prompt and repeat the nc command.
       
       ```bash
       nc -zv 192.168.0.113 7777
       ```
       
       Now the packet captured with tcpdump in the test host shows the egress gateway IP as source IP. 
              
       ```bash
       # if you want to stop the pod of using the egress-gateway, remove the annotation:  
       kubectl annotate pods net egress.projectcalico.org/selector-
       ```

18. Create another egress gateway

    a. Create an IP pool for the blue egress gw
    
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
       
       ```bash
       kubectl get ippools
       ```

    
    b. Create the blue egw

       ```bash
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
       
       ```bash
       kubectl get pods --output=custom-columns='NAME:.metadata.name,IP ADDRESS:.status.podIP'
       ```

19. Test the new egw selections a ns

    ```bash
    #create a ns
    kubectl create ns app-test
    ```

    a. Test w/o egress-gw
    
       Create a pod and test
       
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
           name: netshoot
           command: ["/bin/bash"]
           args: ["-c", "while true; do ping localhost; sleep 60; done"]
       EOF
       ```
       
       ```bash
       # connect to the pod
       kubectl exec -it -n app-test netshoot-app-test -- /bin/bash
       ```
       
       ```bash
       # nc to the test host ip
       nc -zv 192.168.0.113 7777
       ```

       The packet captured with tcpdump in the test host shows the cluster IP as source IP. 
    
    b. Annotate the ns

       ```bash 
       kubectl annotate ns app-test egress.projectcalico.org/selector="egress-code == 'blue'"
       kubectl annotate ns app-test egress.projectcalico.org/namespaceSelector="projectcalico.org/name == 'default'"
       ```
       
       ```bash
       #test again
       nc -zv 192.168.0.113 7777
       ```
       
       ```bash
       kubectl get pods --output=custom-columns='NAME:.metadata.name,IP ADDRESS:.status.podIP'
       ```

       Create another pod in the test namespace and test it again
       
       ```bash
       kubectl run -it --rm -n app-test another-pod --image nicolaka/netshoot:latest
       ````
   
===================
Cleaning Up the Env
===================

1. remove the test host

   ```bash
   aws ec2 terminate-instances \
     --instance-ids $INSTANCEIDHOST \
     --no-cli-pager
   ```

2. remove the test host sg

   ```bash
   aws ec2 delete-security-group \
     --group-id $HOSTSGID \
     --no-cli-pager 
   ```

3. remove ths nodegroup \

   ```bash
   eksclt delete np \
     --name $CLUSTERNAME-ng \
     --cluster $CLUSTERNAME
   ```

4. remove the custom subnets

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

5. remove the eks cluster

   ```bash
   eksctl delete cluster \
     --name $CLUSTERNAME \
     --region $REGION
   ```

6. remove the keypair, if you created one:

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

-----

## Congratulations you finished it!