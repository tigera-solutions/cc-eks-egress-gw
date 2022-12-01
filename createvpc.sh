


# Create a VPC

aws ec2 create-vpc \
  --region $REGION \
  --cidr-block 192.168.0.0/25 \
  --query 'Vpc.VpcId' \
  --output text \
  --tag-specification ResourceType=vpc,Tags=\[\{Key=Name,Value=$CLUSTERNAME-vpc\}\] \
     | export VPCID=$(awk '{print $1}') && echo $VPCID

# Set the DNS hostnames to Enabled in the VPC

aws ec2 modify-vpc-attribute \
  --region $REGION \
  --vpc-id $VPCID \
  --enable-dns-hostnames "{\"Value\":true}" 

# Create an Internet Gateway

aws ec2 create-internet-gateway \
  --region $REGION \
  --query 'InternetGateway.InternetGatewayId' \
  --output text \
    | export INETGWID=$(awk '{print $1}') && echo $INETGWID

# Attach the Internet Gateway to the VPC

aws ec2 attach-internet-gateway \
  --region $REGION \
  --internet-gateway-id $INETGWID \
  --vpc-id $VPCID

# Create the subnets

aws ec2 create-subnet \
  --vpc-id $VPCID \
  --cidr 192.168.0.0/27 \
  --availability-zone $AZ1 \
  --query 'Subnet.SubnetId' \
  --output text \
  --tag-specifications ResourceType=subnet,Tags=\[\{Key=Name,Value=SubnetPublicEKS1A\}\] \
    | export SUBNETPUBEKS1AID=$(awk '{print $1}') && echo $SUBNETPUBEKS1AID

aws ec2 create-subnet \
  --vpc-id $VPCID \
  --cidr 192.168.0.32/27 \
  --availability-zone $AZ2 \
  --query 'Subnet.SubnetId' \
  --output text \
  --tag-specifications ResourceType=subnet,Tags=\[\{Key=Name,Value=SubnetPublicEKS1B\}\] \
    | export SUBNETPUBEKS1BID=$(awk '{print $1}') && echo $SUBNETPUBEKS1BID

aws ec2 create-subnet \
  --vpc-id $VPCID \
  --cidr 192.168.0.64/27 \
  --availability-zone $AZ1 \
  --query 'Subnet.SubnetId' \
  --output text \
  --tag-specifications ResourceType=subnet,Tags=\[\{Key=Name,Value=SubnetPublicEGW1A\}\] \
    | export SUBNETPUBEGW1AID=$(awk '{print $1}') && echo $SUBNETPUBEGW1AID

aws ec2 create-subnet \
  --vpc-id $VPCID \
  --cidr 192.168.0.96/27 \
  --availability-zone $AZ2 \
  --query 'Subnet.SubnetId' \
  --output text \
  --tag-specifications ResourceType=subnet,Tags=\[\{Key=Name,Value=SubnetPublicEGW1B\}\] \
    | export SUBNETPUBEGW1BID=$(awk '{print $1}') && echo $SUBNETPUBEGW1BID

# Change the Auto-assign public IPv4 address to Yes

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

# 

aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=$VPCID" \
  --query 'RouteTables[*].RouteTableId' \
  --output text \
    | export RTTABLEID=$(awk '{print $1}') && echo $RTTABLEID

# Create the route for the default-gateway

aws ec2 create-route \
  --route-table-id $RTTABLEID \
  --destination-cidr-block 0.0.0.0/0 \
  --gateway-id $INETGWID \
  --no-cli-pager

# Associate all subnets with the default route table

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

# Create the cluster

eksctl create cluster \
  --name $CLUSTERNAME \
  --region $REGION \
  --version $K8SVERSION \
  --vpc-public-subnets $SUBNETPUBEKS1AID,$SUBNETPUBEKS1BID \
  --without-nodegroup

# Delete the AWS VPC CNI

# Install Calico CNI

# Create the configuration installation

# Create the nodegroup

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



