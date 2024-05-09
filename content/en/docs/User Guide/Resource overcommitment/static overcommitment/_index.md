---
title: "Static Overcommitment"
linkTitle: "Static Overcommitment"
weight: 1
keywords: ["Resource overcommit"]
description: ""
---
Static resource overcommitment applys a static overcommit ratio to the overcommit node pool.

## Installation

### Prerequisite
- Katalyst >= v0.4.0
- A running kubernetes cluster

### Install Katalyst resource overcommitment
```bash
helm repo add kubewharf https://kubewharf.github.io/charts
helm install overcommit -n katalyst-system --create-namespace kubewharf/katalyst-overcommit --set katalyst-agent.customArgs.sysadvisor-plugins="-overcommit-aware"
```

## Use static resource overcommitment
1. Label the nodes we apply resource overcommitment to
```bash
kubectl label node worker worker2 worker3 katalyst.kubewharf.io/overcommit_node_pool=overcommit-demo
``` 

2. Create a deployment with 20 replicas
```bash
kubectl create -f - <<EOF
kind: Deployment
apiVersion: apps/v1
metadata:
  name: busybox-deployment-overcommit
spec:
  replicas: 20
  selector:
    matchLabels:
      app: busybox
  template:
    metadata:
      labels:
        app: busybox
    spec:
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: katalyst.kubewharf.io/overcommit_node_pool
                operator: In
                values:
                - overcommit-demo
      containers:
      - name: busybox
        image: busybox
        command: ["sleep", "36000"]
        resources:
          requests:
            cpu: "1500m"
            memory: "1Gi"
EOF
```

3. Check the running status of the pods
```bash
kubectl get pod -o wide |grep busybox-deployment-overcommit |awk '{print $3}' |sort |uniq -c
```
Since each pod request for `1500m` of CPU millicores and `1Gi` of memory, and we only have 3 node with `4` CPU cores and `8Gi` memory each. Most of the pods will be in `pending` status.
```console
 14 Pending
  6 Running
```
However, all of the `busybox` containers are executing `sleep 36000` which barely cost you any CPU time, and hence very low overall resource usage.

4. Configure resource overcommitment, and set the `overcommitRatio` of both CPU and memory to `2.5`
```bash
kubectl create -f - <<EOF
apiVersion: overcommit.katalyst.kubewharf.io/v1alpha1
kind: NodeOvercommitConfig
metadata:
  name: overcommit-demo
spec:
  nodeOvercommitSelectorVal: overcommit-demo
  resourceOvercommitRatio:
    cpu: "2.5"
    memory: "2.5"
EOF
```
This essentially means that Katalyst oversells node resource to allow more pods to be scheduled.
If we take a look at the node annotation and status, we can see the orignial and the new allocatable/capacity resource.
```yaml
apiVersion: v1
kind: Node
metadata:
  annotations:
    katalyst.kubewharf.io/cpu_overcommit_ratio: "2.5"
    katalyst.kubewharf.io/memory_overcommit_ratio: "2.5"
    katalyst.kubewharf.io/original_allocatable_cpu: "4"
    katalyst.kubewharf.io/original_allocatable_memory: 8151352Ki
    katalyst.kubewharf.io/original_capacity_cpu: "4"
    katalyst.kubewharf.io/original_capacity_memory: 8151352Ki
  labels:
    katalyst.kubewharf.io/overcommit_node_pool: overcommit-demo
  name: kind-worker
status:
  allocatable:
    cpu: "10"
    memory: 20378380Ki
  capacity:
    cpu: "10"
    memory: 20378380Ki
    ...
```

5. Check the running status of the pods again
```bash
kubectl get pod -o wide |grep busybox-deployment-overcommit |awk '{print $3}' |sort |uniq -c
```
We can verify that more pods are able to get scheduled.
```console
   2 Pending
  18 Running
```