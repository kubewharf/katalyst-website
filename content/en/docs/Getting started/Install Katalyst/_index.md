---
title: "Install Katalyst"
linkTitle: "Install Katalyst"
weight: 2
keywords: ["Getting Started", "Installation"]
---

## Prerequisites
If you don't have a kubewharf enhanced kubernetes cluster up and running already, please follow [the guide](../install-enhanced-k8s/) to install one.

## Add helm repo
```bash
helm repo add kubewharf https://kubewharf.github.io/charts
helm repo update
```

## Install Malachite
```bash
helm install malachite -n malachite-system --create-namespace kubewharf/malachite
```

## Install Katalyst
### Option.1 Install Katalyst Components All in One

```bash
helm install katalyst -n katalyst-system --create-namespace kubewharf/katalyst
```

### Option.2 Install Katalyst Components Standalone

**Install Katalyst-agent**

```bash
helm install katalyst-agent -n katalyst-system --create-namespace kubewharf/katalyst-agent
```

**Install Katalyst-controller**

```bash
helm install katalyst-controller -n katalyst-system --create-namespace kubewharf/katalyst-controller
```

**Install Katalyst-metric**

```bash
helm install katalyst-metric -n katalyst-system --create-namespace kubewharf/katalyst-metric
```

**Install Katalyst-scheduler**

```bash
helm install katalyst-scheduler -n katalyst-system --create-namespace kubewharf/katalyst-scheduler
```

**Install Katalyst-webhook**

```bash
helm install katalyst-webhook -n katalyst-system --create-namespace kubewharf/katalyst-webhook
```