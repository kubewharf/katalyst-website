---
title: "Dynamic Overcommitment"
linkTitle: "Dynamic Overcommitment"
weight: 2
date: 2024-01-16
---
While static resource overcommit can easily apply an overcommit ratio to resources in a node pool, a static ratio can bring risk to a production cluster:
- Due to creation and deletion of pods across nodes and changes in business traffic, the configured overcommit ratio may not meet expectations, leading to the problem of nodes being overloaded.
- When users enable CPUManager on kubelet, CPU binding behavior leads to excessive overcommit of CPU resources in the shared CPU pool.

To address the above issues, Katalyst has extended the overcommit capability, dynamically adjusting the overcommit ratio based on real-time monitoring metrics of nodes and the number of bound CPUs, to increase utilization while avoiding the risk of nodes getting overloaded."

## Installation

### Prerequisite
- Katalyst >= v0.5.0
- A running kubernetes cluster

### Install Katalyst resource overcommitment
```bash
helm repo add kubewharf https://kubewharf.github.io/charts
helm repo update

helm install malachite -n malachite-system --create-namespace kubewharf/malachite
helm install overcommit -n katalyst-system --create-namespace kubewharf/katalyst-overcommit 
```


```bash
kubectl get deployment -n katalyst-system

NAME                  READY   UP-TO-DATE   AVAILABLE
katalyst-controller   2/2     2            2           
katalyst-webhook      2/2     2            2        
katalyst-scheduler    2/2     2            2

kubectl get daemonset -n katalyst-system
NAME             DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE
katalyst-agent   3         3         3       3            3        
```
We can verify that `katalyst-webhook`, `katalyst-controller`, `katalyst-scheduler` and `katalyst-agent` is up and running.

## Use dynamic resource overcommitment

1. Tune dynamic overcommit knobs:

The default overcommit installation comes with the following setup:
```
sysadvisor-plugins: "overcommit_aware"

realtime-overcommit-sync-period: "10s"

# Target CPU load of overcommited nodes. This indicates the target CPU load we wish to get to via overcommit
realtime-overcommit-CPU-targetload: 0.6
# Target memory load of overcommited nodes.
realtime-overcommit-mem-targetload: 0.6

# The estimated overall (pod CPU usage)/(pod cpu request) ，this value affects the upper bound of CPU overcommit ratio
realtime-overcommit-estimated-cpuload: 0.4
# The estimated overall (pod memory usage)/(pod memory request) ，this value affects the upper bound of memory overcommit ratio
realtime-overcommit-estimated-memload: 0.6

# The CPU metrics to use to calculate CPU load, currently support cpu.usage.container
CPU-metrics-to-gather: "cpu.usage.container"
# The memory metrics to use to calculate memory load, currently support mem.rss.container, mem.usage.container
# We use rss usage by default
memory-metrics-to-gather: "mem.rss.container" 
```
Currently it only supports tuning these knobs at installation, i.e. create a local value.yaml file and install overcommit with it.
We have plans to add a switch so that you can tune these knobs on the fly in upcoming releases.

2. Label the nodes we apply resource overcommitment to
```bash
kubectl label node node1 node2 node3 katalyst.kubewharf.io/overcommit_node_pool=overcommit-demo
```

3. Create overcommit config

```shell
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

3. Check `KCNR` of a node in overcommit node pool

Run `kubectl describe kcnr node1` and check the node annotation

```yaml
...
Annotations: 
    # calculated cpu overcommit ratio according to node cpu load
    katalyst.kubewharf.io/cpu_overcommit_ratio: 1.54
    # calculated memory overcommit ratio according to node memory load
    katalyst.kubewharf.io/memory_overcommit_ratio: 1.93
    # number of cpus that are bound to pods
    katalyst.kubewharf.io/guaranteed_cpus: 0
    # kubelet CPUManager policy
    katalyst.kubewharf.io/overcommit_cpu_manager: static
    # kubelet memoryManager policy
    katalyst.kubewharf.io/overcommit_memory_manager: None
...
```

4. Check node object

```yaml
apiVersion: v1
kind: Node
metadata:
  annotations:
    katalyst.kubewharf.io/realtime_cpu_overcommit_ratio: "1.51"
    katalyst.kubewharf.io/realtime_memory_overcommit_ratio: "1.93"
    
spec:
  ...
status:
  # capacity/allocatable after overcommitment
  allocatable:
    cpu: 11778m
    memory: 56468160982220m
  capacity:
    cpu: 12080m
    memory: 64452751810560m
  ...
```

As we can see here, the actual overcommit ratio is calculated according to the node CPU/memory load.
As a result, it is smaller values than the ones we set. This helps to mitigate the risk of nodes getting overloaded

5. Create a pod with high CPU usage

```bash
kubectl create -f - <<EOF
apiVersion: v1
kind: Pod
metadata:
  name: testpod1
  namespace: katalyst-system
...
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: kubernetes.io/hostname
            operator: In
            values:
            - node1
  containers:
  - name: testcontainer1
    image: polinux/stress:latest
    command: ["stress"]
    args: ["--cpu", "4", "--timeout", "6000"]
    resources:
      limits:
        cpu: 8
        memory: 8Gi
      requests:
        cpu: 4
        memory: 8Gi
  tolerations:
  - effect: NoSchedule
    key: test
    value: test
    operator: Equal
EOF
```

This pod is pinned to node `node1` with a `nodeAffinity` term. Modify the node name, resource request/limit and container args based on your situation.

6. Check CPU overcommit ratio again

```bash
kubectl describe kcnr node1

Annotations:  
    # Since node CPU load goes up, a smaller overcommit ratio is set
    katalyst.kubewharf.io/cpu_overcommit_ratio: 1.00
    katalyst.kubewharf.io/guaranteed_cpus: 0
    katalyst.kubewharf.io/memory_overcommit_ratio: 1.93
    katalyst.kubewharf.io/overcommit_cpu_manager: static
    katalyst.kubewharf.io/overcommit_memory_manager: None
```
As the node CPU load goes up, Katalyst comes up with a smaller overcommit value to further discourage overcommitment on this particular node.