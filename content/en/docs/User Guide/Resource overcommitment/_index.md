---
title: "Resource overcommitment"
linkTitle: "Resource overcommitment"
weight: 1
date: 2024-01-16
description: >

---

## Introduction
The resource usage of online business often fluctuates with variations in the number times your service gets called, showing evident tidal characteristics. To ensure the stability of operations, users typically base their resource requests on the resource consumption during peak hours, and service owners tend to over-apply for resources which leads to resource wastage.

Katalyst provides the capability of colocation as one of the ways to address the aforementioned issues. However, it may not be convenient to implement colocation in some scenarios:
- Only online services are involved, which means most of the services share the peak hours.
- Applying for reclaimed resource requires modifications to the applications or even the platform.

Katalyst offers a simple resource overcommitment solution that is transparent to the business side, facilitating users in quickly improving resource utilization.
<div align="center">
  <picture>
    <img src="./overcommit.png" width=50% title="Katalyst overcommit" loading="eager" />
  </picture>
</div>

- Over-commit Webhook：Hijacks kubelet heartbeat request and oversell allocatable resource according to user configuration.
- Over-commit Controller：Manage `nodeovercommitconfig` CRD.
- Katalyst Agent：Ensure node performance and stability using interference detection and eviction; dynamically calculate overcommit ratio according to metrics.(Not implemented yet) 
- Katalyst Scheduler：Admitting pods that binds to specific cpusets to avoid failures of running pods that requires cpusets binding.(Not implemented yet)

## Installation

### Prerequisite
- Katalyst >= v0.4.0

### Create a kind cluster

```bash
kind create cluster --config - <<EOF
# this config file contains all config fields with comments
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4

# 1 control plane node and 3 workers
nodes:
# the control plane node config
- role: control-plane
# the three workers
- role: worker
- role: worker
- role: worker
EOF
```

### Install Katalyst resource overcommitment
```bash
helm repo add https://kubewharf.github.io/charts
helm install overcommit -n katalyst-system --create-namespace kubewharf/katalyst-overcommit
```

## Use resource overcommitment
1. Label the nodes we apply resource overcommitment to
```bash
kubectl label node kind-worker kind-worker2 kind-worker3 katalyst.kubewharf.io/overcommit_node_pool=overcommit-demo
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