# Deploy Egress Gateway with an AWS elastic IP

Let's create another egress gateway.

1. Create the `IPPool's` for the egress gateway `green`.
    
   ```yaml
   kubectl apply -f - <<EOF
   apiVersion: projectcalico.org/v3
   kind: IPPool
   metadata:
     name: egress-green-1a
   spec:
     cidr: 192.168.0.84/31
     allowedUses: ["Workload"]
     awsSubnetID: $SUBNETPUBEGW1AID
     blockSize: 32
     nodeSelector: "!all()"
     disableBGPExport: true
   ---
   apiVersion: projectcalico.org/v3
   kind: IPPool
   metadata:
     name: egress-green-1b
   spec:
     cidr: 192.168.0.116/31
     allowedUses: ["Workload"]
     awsSubnetID: $SUBNETPUBEGW1BID
     blockSize: 32
     nodeSelector: "!all()"
     disableBGPExport: true
   EOF
   ```
   
   Verify the created  `IPPOOL's`

   ```bash
   kubectl get ippools -o=custom-columns='NAME:.metadata.name,CIDR:.spec.cidr'
   ```
   
2. Create the egress gateway `green`. This egress gateway has on its annotation, the IP addresses of the Elastic IPs previously created. Thus the egress gateway will use the Elastic IPs addresses when sending traffic to the Internet.

   ```yaml
   kubectl apply -f - <<EOF
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: egress-gateway-green
     namespace: default
     labels:
       egress-code: green
   spec:
     replicas: 2
     selector:
       matchLabels:
         egress-code: green
     template:
       metadata:
         annotations:
           cni.projectcalico.org/ipv4pools: '["egress-green-1a","egress-green-1b"]'
           cni.projectcalico.org/awsElasticIPs: '["$EIPADDRESS1", "$EIPADDRESS2"]'
         labels:
           egress-code: green
       spec:
         topologySpreadConstraints:
         - maxSkew: 1
           topologyKey: topology.kubernetes.io/zone
           whenUnsatisfiable: DoNotSchedule
           labelSelector: 
             matchLabels:
               egress-code: green
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
      
   Verify the pods created for the egress gateway `green`.
  
   ```bash
   kubectl get pods --output=custom-columns='NAME:.metadata.name,IP ADDRESS:.status.podIP'
   ```

## Testing the egress gateway with a the perPod selector.

1. Create the pod `netshoot-browser`.
   
   ```yaml
   kubectl create -f - <<EOF
   apiVersion: v1
   kind: Pod
   metadata:
     name: netshoot-browser
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

### Test 1 - Acess to the internet from the netshoot-browser pod without using the egress gateway.

Create test traffic to the internet from the pod `netshoot-browser` without using the egress gateway.

1. From the second terminal, execute the shell in the pod `netshoot-browser`.

   ```bash
   kubectl exec -it netshoot-browser -- /bin/bash
   ```

2. Use the curl command to access the ipconfig.io webserver. The ipconfig.io will respond your HTTP GET with your public IP address.
   
   ```bash
   curl ipconfig.io
   ```

The response will be some public IP address mapped from AWS to route traffic to your node. It's ephemeral and can change at any moment.

### Test 2 - Acess to the internet from the netshoot-browser pod using the `egress-gateway-green`.
        
1. On the third terminal, create the following annotations to the namespace `app-test`.

   ```bash 
   kubectl annotate pods netshoot-browser egress.projectcalico.org/selector="egress-code == 'green'"
   ```
      
2. Use the curl command to access the ipconfig.io webserver. The ipconfig.io will respond your HTTP GET with your public IP address.
   
   ```bash
   curl ipconfig.io
   ```

The response will be some public IP address mapped from AWS to route traffic to your node. It's ephemeral and can change at any moment.
            
3. Look into the terminal connected to the test host. The packets captured with `tcpdump` shows the egress gateway IP address as source IP for the incoming packets. 
           
You can stop the pod of using the egress gateway by removing the annotation previously done.
 
```bash
kubectl annotate pods netshoot-browser egress.projectcalico.org/selector-
```

---

[:arrow_right: Module 10 - Clean up](/modules/module-10-clean-up.md)   <br>

[:arrow_left: Module 8 - Deploy Egress Gateway for a per namespace selector](/modules/module-8-egw-pernamespace.md)
[:leftwards_arrow_with_hook: Back to Main](/README.md) 