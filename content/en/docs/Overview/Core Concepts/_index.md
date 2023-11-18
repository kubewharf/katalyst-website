---
title: "Core Concepts"
linkTitle: "Core Concepts"
weight: 2
keywords: ["concepts"]
description: ""
---

## QoS

To extend the ability of kubernetes' original QoS class, katalyst defines its own QoS class with CPU as the dominant resource. Other than memory, CPU is considered as a divisible resource and is easier to isolate. And for cloudnative workloads, CPU is usually the dominant resource that causes performance problems. So katalyst uses CPU to name different QoS classes, and other resources are implicitly accompanied by it.

### Definition
<br>
<table>
  <tbody>
    <tr>
      <th align="center">Qos level</th>
      <th align="center">Feature</th>
      <th align="center">Target Workload</th>
      <th align="center">Mapped k8s QoS</th>
    </tr>
    <tr>
      <td>dedicated_cores</td>
      <td>
        <ul>
          <li>Bind with a quantity of dedicated cpu cores</li>
          <li>Without sharing with any other pod</li>
        </ul>
      </td>
      <td>
        <ul>
          <li>Workload that's very sensitive to latency</li>
          <li>such as online advertising, recommendation.</li>
        </ul>
      </td>
      <td>Guaranteed</td>
    </tr>
    <tr>
      <td>shared_cores</td>
      <td>
        <ul>
          <li>Share a set of dedicated cpu cores with other shared_cores pods</li>
        </ul>
      </td>
      <td>
        <ul>
          <li>Workload that can tolerate a little cpu throttle or neighbor spikes</li>
          <li>such as microservices for webservice.</li>
        </ul>
      </td>
      <td>Guaranteed/Burstable</td>
    </tr>
    <tr>
      <td>reclaimed_cores</td>
      <td>
        <ul>
          <li>Over-committed resources that are squeezed from dedicated_cores or shared_cores</li>
          <li>Whenever dedicated_cores or shared_cores need to claim their resources back, reclaimed_cores will be suppressed or evicted</li>
        </ul>
      </td>
      <td>
        <ul>
          <li>Workload that mainly cares about throughput rather than latency</li>
          <li>such as batch bigdata, offline training.</li>
        </ul>
      </td>
      <td>BestEffort</td>
    </tr>
    <tr>
      <td>system_cores</td>
      <td>
        <ul>
          <li>Reserved for core system agents to ensure performance</li>
        </ul>
      </td>
      <td>
        <ul>
          <li>Core system agents.</li>
        </ul>
      </td>
      <td>Burstable</td>
    </tr>
  </tbody>
</table>

#### Pool

As introduced above, katalyst uses the term `pool` to indicate a combination of resources that a batch of pods share with each other. For instance, pods with shared_cores may share a shared pool, meaning that they share the same cpusets, memory limits and so on; in the meantime, if `cpuset_pool` enhancement is enabled, the single shared pool will be separated into several pools based on the configurations.

### Enhancement

Beside the core QoS level,  katalyst also provides a mechanism to enhance the ability of standard QoS levels. The enhancement works as a flexible extensibility, and may be added continuously.

<br>
<table>
  <tbody>
    <tr>
      <th align="center">Enhancement</th>
      <th align="center">Feature</th>
    </tr>
    <tr>
      <td>numa_binding</td>
      <td>
        <ul>
          <li>Indicates that the pod should be bound into a (or several) numa node(s) to gain further performance improvements</li>
          <li>Only supported by dedicated_cores</li>
        </ul>
      </td>
    </tr>
    <tr>
      <td>cpuset_pool</td>
      <td>
        <ul>
          <li>Allocate a separated cpuset in shared_cores pool to isolate scheduling domain for identical pods.</li>
          <li>Only supported by shared_cores</li>
        </ul>
      </td>
    </tr>
    <tr>
      <td>...</td>
      <td>
      </td>
    </tr>
  </tbody>
</table>

## Configurations

To make the configuration more flexible, katalyst designs a new mechanism to set configs on the run, and it works as a supplement for static configs defined via command-line flags. In katalyst, the implementation of this mechanism is called `KatalystCustomConfig` (`KCC` for short). It enables each daemon component to dynamically adjust its working status without restarting or re-deploying.
For more information about KCC, please refer to [dynamic-configuration](https://github.com/kubewharf/katalyst-core/blob/main/docs/proposals/qos-management/wip-20220706-dynamic-configuration.md).