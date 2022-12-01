# Getting Started

In this section we will put in place the AWS infrastructure to deploy the AWS EKS cluster and the **Calico Cloud Egress Gateway**.

> **Note**: During this workshop, we'll set up some environment variables. If you're terminal session restarts, you may need to reload these variables. You can use that via the following command: <p>
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


### Build the network infrastucture by creating a VPC.

The diagram below shows all the elements that will be created in this step.

![Network Picture]()

1. Define the availability zones to ne used   
   
   As we will only use two AZ in this workshop, let's get them mapped into the environment variables AZ1 and AZ2:
   
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

1. Create a VPC.

   ```bash
   aws ec2 create-vpc \
     --region $REGION \
     --cidr-block 192.168.0.0/25 \
     --query 'Vpc.VpcId' \
     --output text \
     --tag-specification ResourceType=vpc,Tags=\[\{Key=Name,Value=$CLUSTERNAME-vpc\}\] \
        | export VPCID=$(awk '{print $1}') && echo $VPCID
   # Persist for later sessions in case of disconnection.
   echo export VPCID=$VPCID >> ~/egwLabVars.env 
   ```

2. Set the `DNS hostnames` parameter to `Enabled` in the VPC.

   ```bash
   aws ec2 modify-vpc-attribute \
     --region $REGION \
     --vpc-id $VPCID \
     --enable-dns-hostnames "{\"Value\":true}" 
   ```

3. Create an Internet Gateway

   ```bash
   aws ec2 create-internet-gateway \
     --region $REGION \
     --query 'InternetGateway.InternetGatewayId' \
     --output text \
       | export INETGWID=$(awk '{print $1}') && echo $INETGWID
   # Persist for later sessions in case of disconnection.
   echo export INETGWID=$INETGWID >> ~/egwLabVars.env 
   ```

4. Attach the Internet Gateway to the VPC

   ```bash
   aws ec2 attach-internet-gateway \
     --region $REGION \
     --internet-gateway-id $INETGWID \
     --vpc-id $VPCID
   ```

5. Create the subnets
 
   ```bash
   aws ec2 create-subnet \
     --vpc-id $VPCID \
     --cidr 192.168.0.0/27 \
     --availability-zone $AZ1 \
     --query 'Subnet.SubnetId' \
     --output text \
     --tag-specifications ResourceType=subnet,Tags=\[\{Key=Name,Value=SubnetPublicEKS1A\}\] \
       | export SUBNETPUBEKS1AID=$(awk '{print $1}') && echo $SUBNETPUBEKS1AID
   # Persist for later sessions in case of disconnection.
   echo export SUBNETPUBEKS1AID=$SUBNETPUBEKS1AID >> ~/egwLabVars.env 
   ```

   ```bash
   aws ec2 create-subnet \
     --vpc-id $VPCID \
     --cidr 192.168.0.32/27 \
     --availability-zone $AZ2 \
     --query 'Subnet.SubnetId' \
     --output text \
     --tag-specifications ResourceType=subnet,Tags=\[\{Key=Name,Value=SubnetPublicEKS1B\}\] \
       | export SUBNETPUBEKS1BID=$(awk '{print $1}') && echo $SUBNETPUBEKS1BID
   # Persist for later sessions in case of disconnection.
   echo export SUBNETPUBEKS1BID=$SUBNETPUBEKS1BID >> ~/egwLabVars.env 
   ```

   ```bash   
   aws ec2 create-subnet \
     --vpc-id $VPCID \
     --cidr 192.168.0.64/27 \
     --availability-zone $AZ1 \
     --query 'Subnet.SubnetId' \
     --output text \
     --tag-specifications ResourceType=subnet,Tags=\[\{Key=Name,Value=SubnetPublicEGW1A\}\] \
       | export SUBNETPUBEGW1AID=$(awk '{print $1}') && echo $SUBNETPUBEGW1AID
   # Persist for later sessions in case of disconnection.
   echo export SUBNETPUBEGW1AID=$SUBNETPUBEGW1AID >> ~/egwLabVars.env 
   ```

   ```bash   
   aws ec2 create-subnet \
     --vpc-id $VPCID \
     --cidr 192.168.0.96/27 \
     --availability-zone $AZ2 \
     --query 'Subnet.SubnetId' \
     --output text \
     --tag-specifications ResourceType=subnet,Tags=\[\{Key=Name,Value=SubnetPublicEGW1B\}\] \
       | export SUBNETPUBEGW1BID=$(awk '{print $1}') && echo $SUBNETPUBEGW1BID
   # Persist for later sessions in case of disconnection.
   echo export SUBNETPUBEGW1BID=$SUBNETPUBEGW1BID >> ~/egwLabVars.env 
   ```

6. Change the Auto-assign public IPv4 address to Yes

   ```bash
   aws ec2 modify-subnet-attribute \
      --subnet-id $SUBNETPUBEKS1AID \
      --map-public-ip-on-launch "{\"Value\":true}" 
   
   aws ec2 modify-subnet-attribute \
      --subnet-id $SUBNETPUBEKS1BID \
      --map-public-ip-on-launch "{\"Value\":true}" 
   
   aws ec2 modify-subnet-attribute \
      --subnet-id $SUBNETPUBEGW1AID \
      --map-public-ip-on-launch "{\"Value\":true}" 
   
   aws ec2 modify-subnet-attribute \
      --subnet-id $SUBNETPUBEGW1BID \
      --map-public-ip-on-launch "{\"Value\":true}" 
   ```

7. Retrieve the route table id from the default route table.

   ```bash
   aws ec2 describe-route-tables \
     --filters "Name=vpc-id,Values=$VPCID" \
     --query 'RouteTables[*].RouteTableId' \
     --output text \
       | export RTTABLEID=$(awk '{print $1}') && echo $RTTABLEID
   # Persist for later sessions in case of disconnection.
   echo export RTTABLEID=$RTTABLEID >> ~/egwLabVars.env 
   ```

8. Create the route for the default-gateway

   ```bash
   aws ec2 create-route \
     --route-table-id $RTTABLEID \
     --destination-cidr-block 0.0.0.0/0 \
     --gateway-id $INETGWID \
     --no-cli-pager
   ```

9. Associate all subnets with the default route table

   ```bash
   aws ec2 associate-route-table \
     --route-table-id $RTTABLEID \
     --subnet-id $SUBNETPUBEKS1AID \
     --output text \
     --no-cli-pager
   
   aws ec2 associate-route-table \
     --route-table-id $RTTABLEID \
     --subnet-id $SUBNETPUBEKS1BID \
     --output text \
     --no-cli-pager
   
   aws ec2 associate-route-table \
     --route-table-id $RTTABLEID \
     --subnet-id $SUBNETPUBEGW1AID \
     --output text \
     --no-cli-pager
   
   aws ec2 associate-route-table \
     --route-table-id $RTTABLEID \
     --subnet-id $SUBNETPUBEGW1BID \
     --output text \
     --no-cli-pager
   ```

I will create a script to automate this tasks the a future version, I promisse. :)

---

[:arrow_right: Module 2 - Getting Started](/modules/module-3-deploy-eks.md)  
[:arrow_left: Module 1 - Prerequisites](/modules/module-1-prereq.md)  
[:leftwards_arrow_with_hook: Back to Main](/README.md)  