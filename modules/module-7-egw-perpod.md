# Deploy Egress Gateway for a per pod selection

1. Create the `IPPool's` to be used by the egress gateway.

    ```yaml
    kubectl create -f - <<EOF
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

2. Create the egress gateway `red` in the `default` namespace.

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


## Testing the egress gateway with a the perPod selector.


1. Log in to the test host

   ```bash
   ssh -i ~/.ssh/$KEYPAIRNAME.pem ec2-user@$HOSTPUBIPADDR
   ```

   Run `tcpdump` on the test host to capture traffic on port 7777, so you can observe the incoming packets and their parameters.
   
   ```bash
   sudo tcpdump -v -ni eth0 tcp port 7777 
   ```

2. Open another terminal and load the environment variables:

   ```bash
   source ~/egwLabVars.env
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
    
### Test 1 - Acess to the test host from the netshoot-default pod without using the egress gateway.
    
1. Access the pod's shell.
      
   ```bash      
   kubectl exec -it netshoot-default -- /bin/bash
   ```

2. Use `netcat` to create a connection to the test host, on the port 7777. 
     
   ```bash
   nc -zv $HOSTPVTIPADDR 7777
   ```

3. Check the test host terminal. The packets captured with tcpdump shows the **node IP address** as source IP for the incomming packet. 

   If you are confused about the IP addresses, you can run the following kubectl command to see the egress gateway and the nodes with their IP addresses.

   ```bash
   kubectl get nodes -o=custom-columns='NAME:.metadata.name,INTERNAL IPADDR:.status.addresses[?(@.type == "InternalIP")].address'
   kubectl get pods  -o=custom-columns='NAME:.metadata.name,IP ADDRESS:.status.podIP'
   ```  

### Test 2 - Acess to the test host from the netshoot-default pod using the `egress-gateway-red`.

1. Open a third terminal and load the environment variables:
      
   ```bash
   source ~/egwLabVars.env
   ```

2. Annotate the `netshoot-default` pod as following. This will cause the pod to use the egress gateway for egress traffic.

   ```bash
   kubectl annotate pods netshoot-default egress.projectcalico.org/selector="egress-code == 'red'"
   ```
   
3. Go back to the terminal with the pod bash prompt and repeat the `netcat` command.
   
   ```bash
   nc -zv $HOSTPVTIPADDR 7777
   ```
   
4. Look into the terminal connected to the test host. The packets captured with `tcpdump` shows the egress gateway IP address as source IP for the incoming packets. 
          
You can stop the pod of using the egress gateway by removing the annotation previously done.

```bash
kubectl annotate pods netshoot-default egress.projectcalico.org/selector-
```

---

[:arrow_right: Module 8 - Deploy Egress Gateway for a per namespace selector](/modules/module-8-egw-pernamespace.md) <br>

[:arrow_left: Module 6 - Enabling egress gateway support](/modules/module-6-egw-support.md)   
[:leftwards_arrow_with_hook: Back to Main](/README.md) 
