---
title: "Resource Recommender"
linkTitle: "Resource Recommender"
weight: 3
date: 2024-09-10
description: >
---

## Introduction

In the dynamic landscape of online business operations, resource allocation efficiency is paramount. Katalyst provide the Resource Recommender to enhance resource allocation for online business operations. By analyzing historical CPU and memory usage data, the module provides actionable recommendations for resource provisioning, aiming to strike a balance between performance and cost-efficiency.

Features of the Resource Recommender include:

- Data-Driven Insights: Based on past CPU and memory usage data to identify usage patterns and trends.
- Recommendations: Utilizes statistical analysis to recommend appropriate resource requests for various service loads.
- Cost Optimization: Helps to minimize unnecessary resource expenditure by recommending allocations that align with actual usage patterns, potentially reducing the costs associated with over-provisioning.
- Seamless Integration: Offers a non-intrusive solution that integrates with existing systems without necessitating changes to applications or the underlying platform.

With the Resource Recommender, service owners can dynamically adjust their resource needs, ensuring optimal performance during peak hours and minimal waste during off-peak times.

## Prerequisites

- Katalyst >= v0.5.12
- Cluster installed Prometheus / Victoria Metrics

## Installation

### Install Data Source

> If you have added Prometheus / Victoria Metrics, you can skip to next topic.
>
> Please make sure your datasource has two metrics below:
>
> 'container_cpu_usage_seconds_total' and 'container_memory_working_set_bytes'

We use Victoria Metrics as an Example.

- Add helm repo

```bash
helm repo add vm https://victoriametrics.github.io/helm-charts/
helm repo update
```

- Install vmsingle

```bash
helm show values vm/victoria-logs-single > values-vmsingle.yaml
# you should modify PV configurations: persistentVolume

# test and install
helm install vmsingle vm/victoria-metrics-single -f values-vmsingle.yaml -n monitoring --debug --dry-run
helm install vmsingle vm/victoria-metrics-single -f values-vmsingle.yaml -n monitoring
```

- Install vmagent

```bash
helm show values vm/victoria-metrics-agent > values-vmagent.yaml
# you should modify write url configurations: remoteWriteUrls
# such as http://vmsingle-victoria-metrics-single-server:8428/api/v1/write
# if in others namespace, use urls like this pattern: <service-name>.<namespace>.svc.cluster.local
# meanwhile, you should enable service

# test and install
helm install vmagent vm/victoria-metrics-agent -f values-vmagent.yaml -n monitoring --debug --dry-run
helm install vmagent vm/victoria-metrics-agent -f values-vmagent.yaml -n monitoring
```

- Install vmoperator

```bash
helm show values vm/victoria-metrics-operator > values-vmoperator.yaml
# you should not modify anything, due to this, you can also not install configuration yaml

# test and install
helm install vmoperator vm/victoria-metrics-operator -f values-vmoperator.yaml -n monitoring --debug -dry-run
helm install vmoperator vm/victoria-metrics-operator -f values-vmoperator.yaml -n monitoring
```

- (options) Install Grafana
```bash
helm show values grafana/grafana > values-grafana.yaml
# modify PV configuration: persistentVolume and persistence

# test and install
helm install grafana grafana/grafana -f values-grafana.yaml -n monitoring --debug -dry-run
helm install grafana grafana/grafana -f values-grafana.yaml -n monitoring
```

Victoria metrics is compatible with prometheus. We can add the VM address to the Prometheus data source of grafana

> In cluster, you can use the DNS resolution service in the cluster
>
> in same namespace: `http://vmsingle-victoria-metrics-single-server:8428`
>
> in different namespace(e.g. monitoring): `http://vmsingle-victoria-metrics-single-server.monitoring.svc.cluster.local:8428`

- Check Installation

You can check service and pods, it should be like this:

```bash
root@debian-node-1:~/projects/local-manifest# kubectl get pods -n monitoring
NAME                                                    READY   STATUS    RESTARTS        AGE
grafana-74fcb4b8b4-zfjtl                                1/1     Running   27 (106m ago)   43d
vmagent-victoria-metrics-agent-5d84b88fd-9fnrb          1/1     Running   27 (106m ago)   43d
vmoperator-victoria-metrics-operator-6f45db777d-kmf96   1/1     Running   27 (106m ago)   43d
vmsingle-victoria-metrics-single-server-0               1/1     Running   27 (106m ago)   43d

root@debian-node-1:~/projects/local-manifest# kubectl get services -n monitoring
NAME                                      TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)            AGE
grafana                                   NodePort    172.23.219.82    <none>        80:30377/TCP       43d
vmagent-victoria-metrics-agent            ClusterIP   172.23.231.196   <none>        8429/TCP           43d
vmoperator-victoria-metrics-operator      ClusterIP   172.23.217.1     <none>        8080/TCP,443/TCP   43d
vmsingle-victoria-metrics-single-server   ClusterIP   None             <none>        8428/TCP           43d
```

### Install Katalyst ResourceRecommender

```bash
helm repo add kubewharf https://kubewharf.github.io/charts
helm repo update

helm show values kubewharf/katalyst-resource-recommend > values-rrc.yaml
# you should modify datasource values

helm install resource-recommend -f values-rrc.yaml -n katalyst-system --create-namespace kubewharf/katalyst-resource-recommend
```

## Quickly Use Resource Recommender

Use the shared_cores configuration mentioned in Getting Started as an example, and bind ResourceRecommend CR to it.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shared-normal-deployment
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: shared-normal
  template:
    metadata:
      labels:
        app: shared-normal
      annotations:
        "katalyst.kubewharf.io/qos_level": shared_cores
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
---
apiVersion: recommendation.katalyst.kubewharf.io/v1alpha1
kind: ResourceRecommend
metadata:
  name: shared-normal-deployment-recommendation
  namespace: default
spec:
  resourcePolicy:
    algorithmPolicy:
      algorithm: percentile
      extensions: {}
      recommender: default
    containerPolicies:
      - containerName: "*"
        controlledResourcesPolicies:
          - resourceName: "cpu"
            bufferPercent: 10
            controlledValues: "RequestsOnly"
            minAllowed: "1"
            maxAllowed: "3"
          - resourceName: "memory"
            bufferPercent: 10
            controlledValues: "RequestsOnly"
            minAllowed: "500Mi"
            maxAllowed: "2Gi"
  targetRef:
    apiVersion: "apps/v1"
    kind: "Deployment"
    name: "shared-normal-deployment"
```
We can query the current status through command below and get status（a possible scenario）

```bash
kubectl apply -f recommendation-demo.yaml # apply example yaml
kubectl describe resourcerecommend shared-normal-deployment-recommendation # get status
```

```bash
Status:
  Conditions:
    Last Transition Time:  2024-08-31T14:52:30Z
    Status:                True
    Type:                  Initialized
    Last Transition Time:  2024-08-31T14:52:48Z
    Message:               data preparing
    Reason:                Recommendat
    ionNotReady
    Status:                False
    Type:                  RecommendationProvided
    Last Transition Time:  2024-08-31T14:52:30Z
    Status:                True
    Type:                  Validated
  Observed Generation:     1
```
When everything goes as expected, you will get the following scenario

```bash
Status:
  Conditions:
    Last Transition Time:    2024-09-03T18:11:01Z
    Status:                  True
    Type:                    Initialized
    Last Transition Time:    2024-09-03T18:11:01Z
    Status:                  True
    Type:                    RecommendationProvided
    Last Transition Time:    2024-09-03T18:11:01Z
    Status:                  True
    Type:                    Validated
  Last Recommendation Time:  2024-09-03T18:11:01Z
  Observed Generation:       1
  Recommend Resources:
    Container Recommendations:
      Container Name:  stress
      Requests:
        Target:
          Cpu:     1487m
          Memory:  11Mi
```

We can get recommendation in `Recommend Resources`

## Support

### Data Source and Algorithm

- DataSource：Prometheus / VictoriaMetrics and other databases that support Prometheus API.
- Algorithm：Percentile(built-in)

### Condition Message Explanation

| Message                                                      | Explain                                                      |
| :----------------------------------------------------------- | :----------------------------------------------------------- |
| { no message }                                               | OK                                                           |
| data preparing                                               | The data required for the calculation is being collected, usually when the controller is just started |
| no samples in the last 24 hours                              | HistogramTask relies on the latest sample data. The error indicates that no new samples have been generated in the past 24 hours. This may be because the collection program has stopped running. Please check the metrics reporting program. |
| The data sample is insufficient to obtain the predicted value | The data collection is finished. Since there is not enough data, wait for up to 24 hours to get recommendation. |
| The sample found is empty                                    | There is no data in the queried time period. Please check the metrics reporting program and data source configuration. |
| histogram task run panic                                     | HistogramTask meets unexpected panic                         |

### Run Params Explanation

| Name                                            | Default | Explain                                                      |
| :---------------------------------------------- | :------ | :----------------------------------------------------------- |
| oom-record-max-number                           | 5000    | Max number for oom records to store in configmap             |
| resourcerecommend-health-probe-bind-port        | 8080    | The port the health probe binds to.                          |
| resourcerecommend-metrics-bind-port             | 8081    | The port the metric endpoint binds to.                       |
| res-sync-workers                                | 1       | num of goroutine to sync recs                                |
| resource-recommend-resync-period                | 24      | (Unit: Hour) period for recommend controller to sync resource recommend |
| resourcerecommend-datasource                    | prom    | available datasource: prom                                   |
| resourcerecommend-prometheus-address            | {empty} | prometheus address                                           |
| resourcerecommend-prometheus-auth-type          | {empty} | prometheus auth type, works together with the following username and password to achieve authentication. Leave it blank to indicate that no authentication is required. |
| resourcerecommend-prometheus-auth-username      | {empty} | prometheus auth username                                     |
| resourcerecommend-prometheus-auth-username      | {empty} | prometheus auth password                                     |
| resourcerecommend-prometheus-auth-bearertoken   | {empty} | prometheus auth bearertoken                                  |
| resourcerecommend-prometheus-keepalive          | 60      | (Unit: Second) prometheus keepalive                          |
| resourcerecommend-prometheus-timeout            | 3       | (Unit: Minute) prometheus timeout                            |
| resourcerecommend-prometheus-bratelimit         | false   | prometheus bratelimit                                        |
| resourcerecommend-prometheus-maxpoints          | 11000   | prometheus max points limit per time series                  |
| resourcerecommend-prometheus-promql-base-filter | {empty} | Get basic filters in promql for historical usage data. This filter is added to all promql statements.Supports filters format of promql, e.g: group="Katalyst",cluster="cfeaf782fasdfe" |

### CR Demo and Explanation

```yaml
apiVersion: recommendation.katalyst.kubewharf.io/v1alpha1
kind: ResourceRecommend
metadata:
  name: shared-normal-deployment-recommendation
  namespace: default
spec:
  resourcePolicy:
    algorithmPolicy:
      algorithm: percentile  # Algorithm
      recommender: default   # Use default recommender
      extensions: {}         # Additional K-V pairs
    containerPolicies:
      - containerName: "*"   # For all containers, you can use it to select container
        controlledResourcesPolicies:
          - resourceName: "cpu" # Only "cpu" or "memory"
            bufferPercent: 10   # If recommendation calculated is 100m, the result will be 100*1.1 = 110m
            controlledValues: "RequestsOnly" # Only RequestValue will be modify by recommendation, LimitValue will not be.
            minAllowed: 100m
            maxAllowed: "3"
          - resourceName: "memory"
            bufferPercent: 10
            controlledValues: "RequestsOnly"
            minAllowed: "500Mi"
            maxAllowed: "2Gi"
  targetRef:
    apiVersion: "apps/v1"
    kind: "Deployment"
    name: "shared-normal-deployment"
```