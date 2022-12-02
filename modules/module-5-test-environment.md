# Create the test environment

Create a test host to see the details of the packets received outside the EKS cluster.

1. Create a segurity group for the test host opening the ports 22 for ssh connection and 7777 to receive test traffic.

   ```bash
   aws ec2 create-security-group \
     --group-name rmart-sg-test-host \
     --description "Security group for the test host" \
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

2. Create the test host to receive and analyze the packets outside the EKS cluster.

   ```bash
   aws ec2 run-instances \
     --key-name $KEYPAIRNAME \
     --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2 \
     --subnet-id $SUBNETPUBEKS1AID \
     --security-group-ids $HOSTSGID \
     --associate-public-ip-address \
     --instance-type t3.nano \
     --count 1 \
     --tag-specifications ResourceType=instance,Tags=\[\{Key=Name,Value=$CLUSTERNAME-test-host\}\] \
     --output yaml \
       | export HOSTINSTANCEID=$(grep InstanceId | awk '{print $2}')
   # Persist for later sessions in case of disconnection.
   echo export HOSTINSTANCEID=$HOSTINSTANCEID >> ~/egwLabVars.env
   ```
    
3. Once the test host is create, you should have the following picture of your AWS infrastructure:
    
   ![egress-gateway-v0 0 1-Adding the Test Server](https://user-images.githubusercontent.com/104035488/204860124-b49d3673-9bd6-4a91-81b2-6b85532ccd2f.png)

   Retrive the test host ip address, so you can ssh into it in a future module.

   ```bash
   HOSTIPADDRESS=$(aws ec2 describe-instances \
     --instance-ids $HOSTINSTANCEID \
     --query "Reservations[*].Instances[*].PublicIpAddress" \
     --output text) && echo $HOSTIPADDRESS
   # Persist for later sessions in case of disconnection.
   echo export HOSTIPADDRESS=$HOSTIPADDRESS >> ~/egwLabVars.env
   ```

--- 

[:arrow_right: Module 6 - Deploy an Egress Gateway for a per pod selection](/modules/module-6-egw-perpod.md) <br>
[:arrow_left: Module 4 - Connect the AWS EKS cluster to Calico Cloud](/modules/module-4-connect-calicocloud.md)  
[:leftwards_arrow_with_hook: Back to Main](/README.md)  