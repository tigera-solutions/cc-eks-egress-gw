# Module 8 - Deploy Egress Gateway and use a namespace selector

Let's create another egress gateway.

1. Create the `IPPool's` for the egress gateway `blue`.
    
   ```yaml
   kubectl apply -f - <<EOF
   apiVersion: projectcalico.org/v3
   kind: IPPool
   metadata:
     name: egress-blue-1a
   spec:
     cidr: 192.168.0.82/31
     allowedUses: ["Workload"]
     awsSubnetID: $SUBNETPUBEGW1AID
     blockSize: 32
     nodeSelector: "!all()"
     disableBGPExport: true
   ---
   apiVersion: projectcalico.org/v3
   kind: IPPool
   metadata:
     name: egress-blue-1b
   spec:
     cidr: 192.168.0.114/31
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
   
2. Create the egress gateway `blue`.

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

## Testing the egress gateway with a the perPod selector.

1. Create the namespace `app-test` and the pod `netshoot-app-test` for the test.

   Create the namespace  `app-test`.

   ```bash
   kubectl create ns app-test
   ```
   
2. Create the pod `netshoot-app-test` in the `app-test` namespace.
   
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

### Test 1 - Acess to the test host from the netshoot-app-test pod without using the egress gateway.

- If you disconnected from the test host, login again.

  ```bash
  ssh -i ~/.ssh/$KEYPAIRNAME.pem ec2-user@$HOSTPUBIPADDR
  ```

  Run `tcpdump` on the test host to capture traffic on port 7777, so you can observe the incoming packets and their parameters.
   
  ```bash
  sudo tcpdump -v -ni eth0 tcp port 7777 
  ```

Create test traffic to the test host from the pod `netshoot-app-test` in the `app-test` namespace without using the egress gateway.

1. From the second terminal, execute the shell in the pod `netshoot-app-test`.

   ```bash
   kubectl exec -it -n app-test netshoot-app-test -- /bin/bash
   ```

2. Use `netcat` to create a connection to the test host, on the port 7777.
   
   ```bash
   # nc to the test host ip
   nc -zv $HOSTPVTIPADDR 7777
   ```

3. Run the following kubectl command in another terminal window to see the egress gateway and the nodes with their IP addresses.

   ```bash
   kubectl get nodes -o=custom-columns='NAME:.metadata.name,INTERNAL IPADDR:.status.addresses[?(@.type == "InternalIP")].address'
   kubectl get pods  -o=custom-columns='NAME:.metadata.name,IP ADDRESS:.status.podIP'
   ```  

Check the terminal connected to the test host. The packets captured with `tcpdump` shows the **node IP address** as source IP for the incomming packet.

### Test 2 - Acess to the test host from the netshoot-app-test pod using the `egress-gateway-blue`.
        
1. On the third terminal, create the following annotations to the namespace `app-test`.

   ```bash 
   kubectl annotate ns app-test egress.projectcalico.org/selector="egress-code == 'blue'"
   kubectl annotate ns app-test egress.projectcalico.org/namespaceSelector="projectcalico.org/name == 'default'"
   ```
      
2. On the second terminal, executing the shell on the `netshoot-app-test` pod, run the following `netcat` command.
      
   ```bash
   nc -zv $HOSTPVTIPADDR 7777
   ```
            
3. Look into the terminal connected to the test host. The packets captured with `tcpdump` shows the egress gateway IP address as source IP for the incoming packets. 
           
### Test 3 - Create another pod in the `app-test` namespace and repeat the tests.
      
1. Create `another-pod`:

   ```bash
   kubectl run -it --rm -n app-test another-pod --env="HOSTPVTIPADDR=$HOSTPVTIPADDR" --image nicolaka/netshoot:latest
   ```  
      
2. Run the following `netcat` command and observer the packets arriving at the test host.

   ```bash
   nc -zv $HOSTPVTIPADDR 7777
   ```

You can stop the pod of using the egress gateway by removing the annotation previously done.
 
```bash
kubectl annotate ns app-test egress.projectcalico.org/selector-
kubectl annotate ns app-test egress.projectcalico.org/namespaceSelector-
```

**Note that you did not need to annotated any pod. This is because the namespace has the annotations on it. So, any pod created inside the namespace will automatically use the egress gateway for egress traffic.** 

---

[:arrow_right: Module 9 - Deploy Egress Gateway with an AWS elastic IP](/modules/module-9-egw-elastic-ip.md)  <br>

[:arrow_left: Module 7 - Deploy Egress Gateway for a per pod selection](/modules/module-7-egw-perpod.md)  
[:leftwards_arrow_with_hook: Back to Main](/README.md) 
