# Clean up

This steps my be suffice to clean up all the objects created for this workshop.

1. Delete the test host

   ```bash
   aws ec2 terminate-instances \
     --instance-ids $HOSTINSTANCEID \
     --no-cli-pager
   ```

2. Delete the security group

   ```bash
   aws ec2 delete-security-group \
     --group-id $HOSTSGID \
     --no-cli-pager 
   ```

3. Delete the cluster (with the nodegroup)

   ```bash
   eksctl delete cluster \
     --name $CLUSTERNAME \
     --region $REGION
   ```

4. Detach the Internet Gateway from the VPC

   ```bash
   aws ec2 detach-internet-gateway \
     --internet-gateway-id $INETGWID \
     --vpc-id $VPCID 
   ```

5. Delete the Internet Gateway

   ```bash
   aws ec2 delete-internet-gateway \
     --internet-gateway-id $INETGWID
   ```

6. Delete the Subnets

   ```bash
   aws ec2 delete-subnet \
   --subnet-id $SUBNETPUBEKS1AID
   
   aws ec2 delete-subnet \
   --subnet-id $SUBNETPUBEKS1BID
   
   aws ec2 delete-subnet \
   --subnet-id $SUBNETPUBEGW1AID
   
   aws ec2 delete-subnet \
   --subnet-id $SUBNETPUBEGW1BID
   ```

7. Release the Elastic IP addresses.

   ```bash
   aws ec2 release-address \
     --allocation-id $EIPALLOCATION1

   aws ec2 release-address \
     --allocation-id $EIPALLOCATION2
   ```

8. Delete the VPC
   
   ```bash
   aws ec2 delete-vpc \
     --region $REGION \
     --vpc-id $VPCID 
   ```

9. Delete the keypair

   ```bash
   aws ec2 delete-key-pair \
     --key-name $KEYPAIRNAME
   ```

10. Delete the private key and the egwLabVars.env files stored locally

    ```bash
    rm -f ~/.ssh/$KEYPAIRNAME.pem
    # Remove the lab env params file.
    rm ~/egwLabVars.env
    ```

---

[:leftwards_arrow_with_hook: Back to Main](/README.md) <br>

[:arrow_left: Module 9 - Deploy Egress Gateway with an AWS elastic IP](/modules/module-9-egw-elastic-ip.md)
