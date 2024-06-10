---
title: "Colocate your application using Katalyst"
linkTitle: "Colocate your application using Katalyst"
weight: 2
keywords: ["Colocation", "Quick Start"]
---
This is a quick start guide to get a taste of what you can achieve with Katalyst colocation capabilities. It is highly suggested that you read through [core concepts](../../overview/core-concepts/) before you begin, so that you won't get confused on some terminologies in this guide.

## Prerequisites
As of v0.5.0, Katalyst colocation capability can run both on vanilla kubernetes and Kubewharf enhanced kubernetes. If you choose to run colocation on Kubewharf enhanced kubernetes, please follow [this guide](../install-enhanced-k8s/) to install one first and continue with this guide.

## Installation
### Add helm repo
```bash
helm repo add kubewharf https://kubewharf.github.io/charts
helm repo update
```

### Install Malachite
```bash
helm install malachite -n malachite-system --create-namespace kubewharf/malachite
```

### Install Katalyst colocation
#### Option 1: Install Katalyst colocation on Kubewharf enhanced kubernetes
```bash
helm install katalyst-colocation -n katalyst-system --create-namespace kubewharf/katalyst-colocation
```
#### Option 2: Install Katalyst colocation on vanilla kubernetes
```bash
helm install katalyst-colocation -n katalyst-system --create-namespace kubewharf/katalyst-colocation-orm
```

## A colocation example
Before going to the next step, let's assume that we have the following setup:

- Total resources are set as 48 cores and 195924424Ki per node;
- Reserved resources for pods with shared_cores are set as 4 cores and 5Gi. This means that we'll always keep at least this amount of resources for those pods for bursting requirements.
  
Based on the assumption above, you can follow the steps to deep dive into the colocation workflow.

### Reporting reclaimed resource 
After installing, resource reporting module will report reclaimed resources. Since there are no pods running, reclaimed resource will be calculated as:
`reclaimed_resources = total_resources - reserve_resources`

Katalyst defines a CRD `CustomNodeResource` to keep the extended per-node resources including reclaimed resources. If we check `CustomNodeResource` with `kubectl get kcnr`, reclaimed resources will be shown as follows. It indicates the amount of reclaimed resources this node offers that can be allocated to pods with `reclaimed_cores` QoS class.

```yaml
status:
    resourceAllocatable:
        katalyst.kubewharf.io/reclaimed_memory: "195257901056"
        katalyst.kubewharf.io/reclaimed_millicpu: 44k
    resourceCapacity:
        katalyst.kubewharf.io/reclaimed_memory: "195257901056"
        katalyst.kubewharf.io/reclaimed_millicpu: 44k
```

Create a `shared_cores` pods with the following yaml, and generate some CPU workloads to make reclaimed resources fluctuate along with the running state of workload. We can think of it as an online service like a web server.

```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    "katalyst.kubewharf.io/qos_level": shared_cores
  name: shared-normal-pod
  namespace: default
spec:
  containers:
    - name: stress
      image: joedval/stress:latest
      command:
        - stress
        - -c
        - "1"
      imagePullPolicy: IfNotPresent
      resources:
        requests:
          cpu: "2"
          memory: 1Gi
        limits:
          cpu: "2"
          memory: 1Gi
  schedulerName: katalyst-scheduler
```

After successfully scheduled, the pod starts running with cpu-usage ~= 1cores and cpu-load ~= 1, and the reclaimed resources will be changed according to the formula below. We skip memory here since it's more difficult to reproduce with accurate value than cpu, but the principle is familiar.
`reclaim cpu = allocatable - round(ceil(reserve + max(usage,load.1min,load.5min))`

```yaml
status:
    resourceAllocatable:
        katalyst.kubewharf.io/reclaimed_millicpu: 42k
    resourceCapacity:
        katalyst.kubewharf.io/reclaimed_millicpu: 42k
```
   
Now we put pressure on those pods to simulate peak hours of online services with `stress`, and the cpu-load will rise to approximately 3 to make the reclaimed cpu shrink to 40k.

```bash
kubectl exec shared-normal-pod -it -- stress -c 2
```

If we check the `CustomNodeResource` again, we can verify that the allocatable reclaimed CPU reduces to `40k`.
```yaml
status:
    resourceAllocatable:
        katalyst.kubewharf.io/reclaimed_millicpu: 40k
    resourceCapacity:
        katalyst.kubewharf.io/reclaimed_millicpu: 40k
```

### Enhanced QoS capabilities
After pods get successfully scheduled, katalyst will apply resource isolation strategies for various resource dimension (e.g. CPU, memory, network, disk io etc) and dynamically adjust resource allocation for pods with different QoS classes. These strategies are to ensure the QoS of `shared_cores` workloads are met while reclaiming as much resource as possible. In this guide we will see how Katalyst manages CPU for `shared_cores` and `reclaimed_cores` workloads.

Before going into the next step, remember to remove previous pods to make a clean environment.

In a nutshell, Katalyst use cpuset to isolate interference between pods from different QoS classes. It allocates separate cpuset pool for `shared_cores` and `reclaimed_cores` workloads so that no `shared_cores` pod will scheduled to run on a same cpu core with `reclaimed_cores` pods at the same time. Let's verify this with an example:

Create a pod with `shared_cores` QoS class with the yaml below. 
```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    "katalyst.kubewharf.io/qos_level": shared_cores
  name: shared-normal-pod
  namespace: default
spec:
  containers:
    - name: stress
      image: joedval/stress:latest
      command:
        - stress
        - -c
        - "1"
      imagePullPolicy: IfNotPresent
      resources:
        requests:
          cpu: "2"
          memory: 1Gi
        limits:
          cpu: "2"
          memory: 1Gi
  schedulerName: katalyst-scheduler
```

After a short ramp-up period, the cpuset for shared-pool will be 6 cores in total:
- 4 cores are reserved as buffer for bursting request.
- 2 cores for regular requirements. This number is derived from algorithm which takes the current CPU usage/load of `shared_cores` pods into consideration.

The rest of the cores are considered suitable for reclaimed pods.

Let's login to the node to check the cpuset allocation result:
```bash
cat<<'EOF' > /tmp/get_cpuset.sh
id=$1
cid=$(crictl ps |grep "$id"|awk '{print $1}')
if [ "${cid}x" == "x" ]; then
exit
fi

cp=$(crictl inspect "$cid"|grep cgroupsPath|awk '{print $2}'|tr -d "\""|tr -d ',')
if [ "${cp}x" == "x" ]; then
exit
fi

date
cat /sys/fs/cgroup"$cp"/cpuset.cpus
EOF

chmod 700 /tmp/get_cpuset.sh
```

The script above get the allocated cpuset of a specific pod. Let's check the cpuset allocated to `shared-normal-pod`.
```bash
./tmp/get_cpuset.sh shared-normal-pod

Tue Jan  3 16:18:31 CST 2023
11,22-23,35,46-47
```

Now create a pod with `reclaimed_cores` QoS class with the yaml below, and the cpuset for `reclaimed_cores` pods will be 40 cores in total.

```yaml
apiVersion: v1
kind: Pod
metadata:
  annotations:
    "katalyst.kubewharf.io/qos_level": reclaimed_cores
  name: reclaimed-normal-pod
  namespace: default
spec:
  containers:
    - name: stress
      image: joedval/stress:latest
      command:
        - stress
        - -c
        - "1"
      imagePullPolicy: IfNotPresent
      resources:
        requests:
          resource.katalyst.kubewharf.io/reclaimed_millicpu: 2k
          resource.katalyst.kubewharf.io/reclaimed_memory: 1Gi
        limits:
          resource.katalyst.kubewharf.io/reclaimed_millicpu: 2k
          resource.katalyst.kubewharf.io/reclaimed_memory: 1Gi
  schedulerName: katalyst-scheduler
```
Check the cpuset allocated for `reclaimed_cores`
```bash
./tmp/get_cpuset.sh reclaimed-normal-pod

Tue Jan  3 16:23:20 CST 2023
0-10,12-21,24-34,36-45
```

Now if the cpu load of `shared-normal-pod` rises to 3, the cpuset for all `shared_cores` pods will be 8 cores in total (i.e. 4 cores are reserved as buffer for bursting request, plus 4 cores for regular requirements). And cpuset allocated for `reclaimed_cores` pods will shrink to 48.

```bash
kubectl exec reclaimed-normal-pod -it -- stress -c 2
```
```bash
./tmp/get_cpuset.sh shared-normal-pod

Tue Jan  3 16:25:23 CST 2023
10-11,22-23,34-35,46-47
```

```bash
./tmp/get_cpuset.sh reclaimed-normal-pod

Tue Jan  3 16:28:32 CST 2023
0-9,12-21,24-33,36-45
```

### Pod Eviction
Eviction is usually used as a fallback measure in case that the QoS fails to be satisfied, and we should always make sure that the QoS of pods with higher priority (i.e. `shared_cores` pods) is met by evicting pods with lower priority (i.e. `reclaimed_cores` pods). Katalyst provides both per-node and centralized evictions to meet different requirements.

Before going to the next step, remember to clear previous pods to make a clean environment.

#### Per-node Eviction
Per-node eviction is performed by a daemonset agent. Currently, Katalyst provides several in-tree agent eviction implementations.

##### Resource Overcommit
Since allocatable reclaimed resources are always fluctuating according to the running state of pods with `shared_cores`, there are cases where allocatable reclaimed resource gets very tight due to the rise of resource usage of `shared_cores` pods. In this case, katalyst will evict `reclaimed_cores` pods to have them rescheduled to a node with more resource. The trigger for this kind of eviction can be described as:
`sum(requested_reclaimed_resource) > alloctable_reclaimed_resource * threshold`

Create several pods (including `shared_cores` and `reclaimed_cores`)

```bash
curl https://raw.githubusercontent.com/kubewharf/katalyst-core/main/examples/shared-large-pod.yaml | kubectl create -f -
curl https://raw.githubusercontent.com/kubewharf/katalyst-core/main/examples/reclaimed-large-pod.yaml | kubectl create -f -
```

Now add some loads to `shared_cores` pods to reduce allocatable reclaimed resources until it is below the threshold. Eventually, it will trigger the eviction of pod `reclaimed-large-pod-2`.

```bash
kubectl exec shared-large-pod-2 -it -- stress -c 40
```

Check `CustomNodeResource` of the node, we can see that allocatable reclaimed cpu is reduced to `4k`:
```yaml
status:
    resourceAllocatable:
        katalyst.kubewharf.io/reclaimed_millicpu: 4k
    resourceCapacity:
        katalyst.kubewharf.io/reclaimed_millicpu: 4k
```

Check the eviction events:
```bash
kubectl get event -A | grep evict

default     43s         Normal   EvictCreated     pod/reclaimed-large-pod-2   Successfully create eviction; reason: met threshold in scope: katalyst.kubewharf.io/reclaimed_millicpu from plugin: reclaimed-resource-pressure-eviction-plugin
default     8s          Normal   EvictSucceeded   pod/reclaimed-large-pod-2   Evicted pod has been deleted physically; reason: met threshold in scope: katalyst.kubewharf.io/reclaimed_millicpu from plugin: reclaimed-resource-pressure-eviction-plugin
```

The default threshold for reclaimed resources 5, we can dynamically configure the threshold with KCC:
```bash
kubectl create -f - <<EOF
apiVersion: config.katalyst.kubewharf.io/v1alpha1
kind: KatalystCustomConfig
metadata:
  name: eviction-configuration
spec:
  targetType:
    group: config.katalyst.kubewharf.io
    resource: evictionconfigurations
    version: v1alpha1

---
apiVersion: config.katalyst.kubewharf.io/v1alpha1
kind: EvictionConfiguration
metadata:
  name: default
spec:
  config:
    evictionPluginsConfig:
      reclaimedResourcesEvictionPluginConfig:
        evictionThreshold:
          "katalyst.kubewharf.io/reclaimed_millicpu": 10
          "katalyst.kubewharf.io/reclaimed_memory": 10
EOF
```

##### Memory
Memory eviction is implemented in two parts: numa-level eviction and system-level eviction. The former is used along with numa-binding enhancement, while the latter is used for more general cases. In this tutorial, we will mainly demonstrate the latter. For each level, katalyst will trigger memory eviciton based on memory usage and Kswapd active rate to avoid slow path for memory allocation in kernel.

Create several pods (including `shared_cores` and `reclaimed_cores`)

```bash
curl https://raw.githubusercontent.com/kubewharf/katalyst-core/main/examples/shared-large-pod.yaml | kubectl create -f -
curl https://raw.githubusercontent.com/kubewharf/katalyst-core/main/examples/reclaimed-large-pod.yaml | kubectl create -f -
```

Create KCC to change the default free memory and Kswapd rate threshold.

```bash
kubectl create -f - <<EOF
apiVersion: config.katalyst.kubewharf.io/v1alpha1
kind: KatalystCustomConfig
metadata:
  name: eviction-configuration
spec:
  targetType:
    group: config.katalyst.kubewharf.io
    resource: evictionconfigurations
    version: v1alpha1

---
apiVersion: config.katalyst.kubewharf.io/v1alpha1
kind: EvictionConfiguration
metadata:
  name: default
spec:
  config:
    evictionPluginsConfig:
      memoryEvictionPluginConfig:
        enableNumaLevelDetection: false
        systemKswapdRateExceedTimesThreshold: 1
        systemKswapdRateThreshold: 2000
EOF
```

###### **Memory Usage Eviction**
Exec into `reclaimed-large-pod-2` and request enough memory. When memory free drops below the threshold, Katalyst will try to evict pods `reclaimed_cores` pods, and it will choose the pod that uses the most memory.

```bash
kubectl exec -it reclaimed-large-pod-2 bash

stress --vm 1 --vm-bytes 175G --vm-hang 1000 --verbose
```

Check the eviction event:
```bash
kubectl get event -A | grep evict

default     2m40s       Normal   EvictCreated     pod/reclaimed-large-pod-2   Successfully create eviction; reason: met threshold in scope: memory from plugin: memory-pressure-eviction-plugin
default     2m5s        Normal   EvictSucceeded   pod/reclaimed-large-pod-2   Evicted pod has been deleted physically; reason: met threshold in scope: memory from plugin: memory-pressure-eviction-plugin
```

```yaml
taints:
- effect: NoSchedule
  key: node.katalyst.kubewharf.io/MemoryPressure
  timeAdded: "2023-01-09T06:32:08Z"
```

###### **Kswapd Eviction**
Login into the working node and put some pressure on system memory

```bash
stress --vm 1 --vm-bytes 180G --vm-hang 1000 --verbose
```

When Kswapd active rates exceed the target threshold (default = 1),  Katalyst will try to eviction both `reclaimed_cores` and `shared_cores` pods, and `reclaimed_cores` will be picked for eviction first.

Check the eviction event:
```bash
kubectl get event -A | grep evict

default           2m2s        Normal    EvictCreated              pod/reclaimed-large-pod-2          Successfully create eviction; reason: met threshold in scope: memory from plugin: memory-pressure-eviction-plugin
default           92s         Normal    EvictSucceeded            pod/reclaimed-large-pod-2          Evicted pod has been deleted physically; reason: met threshold in scope: memory from plugin: memory-pressure-eviction-plugin
```

```yaml
taints:
- effect: NoSchedule
  key: node.katalyst.kubewharf.io/MemoryPressure
  timeAdded: "2023-01-09T06:32:08Z"
```

##### **Load Eviction**
For `shared_cores` pods, if any pod spawns too many threads, the scheduling period of linux cfs scheduler may be split into small pieces and will result in more throttling and impacts workload performance. To solve this, katalyst implements load eviction to detect load counts and trigger taint and eviction actions based on threshold, and the comparison formula is as follows.
``` soft: load > resource_pool_cpu_amount ```
``` hard: load > resource_pool_cpu_amount * threshold ```

Create several pods (including `shared_cores` and `reclaimed_cores`).

```bash
curl https://raw.githubusercontent.com/kubewharf/katalyst-core/main/examples/shared-large-pod.yaml | kubectl create -f -
curl https://raw.githubusercontent.com/kubewharf/katalyst-core/main/examples/reclaimed-large-pod.yaml | kubectl create -f -
```

Put some pressure to reduce allocatable reclaimed resources until the load exceeds the soft threshold. In this case, taint will be added in CNR to avoid scheduling new pods, but the existing pods will keep running.

```bash
kubectl exec shared-large-pod-2 -it -- stress -c 50
```
```yaml
taints:
- effect: NoSchedule
  key: node.katalyst.kubewharf.io/CPUPressure
  timeAdded: "2023-01-05T05:26:51Z"
```

Put more pressure to reduce allocatable reclaimed resources until the load exceeds the hard threshold. In this case, katalyst will evict the pods that create the most amount of threads.

```bash
kubectl exec shared-large-pod-2 -it -- stress -c 100
```
```bash
$ kubectl get event -A | grep evict
67s         Normal   EvictCreated     pod/shared-large-pod-2      Successfully create eviction; reason: met threshold in scope: cpu.load.1min.container from plugin: cpu-pressure-eviction-plugin
68s         Normal   Killing          pod/shared-large-pod-2      Stopping container stress
32s         Normal   EvictSucceeded   pod/shared-large-pod-2      Evicted pod has been deleted physically; reason: met threshold in scope: cpu.load.1min.container from plugin: cpu-pressure-eviction-plugin
```

#### Centralized Eviction
In some cases, the agents may suffer from the single point of failure, i.e. In a large cluster, the daemon may fail to work because of a lot of abnormal cases, and pods running on the node may go out of control. Katalyst introduces a centralized eviction mechanism to evict all reclaimed pods to relieve this problem.
By default, if the readiness state keeps failing for 10 minutes, Katalyst will taint the CNR as `unSchedubable` to make sure no more pods with `reclaimed_cores` can be scheduled to this node. And if the readiness state keeps failing for 20 minutes, it will try to evict all pods with `reclaimed_cores`.

```yaml
taints:
- effect: NoScheduleForReclaimedTasks
  key: node.kubernetes.io/unschedulable
```

## Further More
We will try to provide more tutorials in the future along with feature releases in the future.