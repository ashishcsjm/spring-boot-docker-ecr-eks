# Kubernetes & AWS EKS — Concepts & Interview Notes

Study notes built around this project (Spring Boot → Docker → AWS ECR → AWS EKS).
Covers core concepts, architecture, EKS vs standalone Kubernetes, key `kubectl`
commands, debugging techniques, and architect-level Q&A.

---

## Table of Contents
1. [kubelet vs kubectl](#1-kubelet-vs-kubectl)
2. [replicas vs ReplicaSet](#2-replicas-vs-replicaset)
3. [What a Deployment Manifest Means](#3-what-a-deployment-manifest-means)
4. [Kubernetes Objects in This Project](#4-kubernetes-objects-in-this-project)
5. [Kubernetes Components (Control Plane vs Worker)](#5-kubernetes-components-control-plane-vs-worker)
6. [Kubernetes Architecture Diagram](#6-kubernetes-architecture-diagram)
7. [End-to-End Process Flow](#7-end-to-end-process-flow)
8. [AWS EKS vs Standalone Kubernetes](#8-aws-eks-vs-standalone-kubernetes)
9. [Most Important kubectl Commands](#9-most-important-kubectl-commands)
10. [Debugging Techniques](#10-debugging-techniques)
11. [Architect-Level Q&A](#11-architect-level-qa)

---

## 1. kubelet vs kubectl

These sound alike but live on opposite sides of the cluster.

| | **kubectl** | **kubelet** |
|---|---|---|
| What it is | The **CLI client** you run (on your EC2/laptop) | A **node agent daemon** running on every worker node |
| Who uses it | A human or CI pipeline | Kubernetes itself |
| Talks to | The kube-apiserver | The kube-apiserver (pulls work) + the container runtime (does work) |
| Job | Send commands/manifests to the cluster | Start/stop containers on its node, run probes, report pod status |
| In this project | `kubectl apply -f k8s-deployment.yaml` | The kubelet on the node pulled the ECR image, ran port 8080, and executed the `/actuator/health` probes |

**One-liner:** *"kubectl is how I talk to the cluster; kubelet is how the cluster runs containers on a node."*

---

## 2. replicas vs ReplicaSet

- **replicas** = a *number* (desired count). In this project `replicas: 2` means "always keep 2 pods."
- **ReplicaSet** = the *controller object* that enforces that number. It continuously watches and guarantees "exactly N pods matching my selector exist." If one dies, it creates a replacement (self-healing).

> You never write a ReplicaSet directly — the **Deployment creates and owns it**.
> Relationship: **Deployment → ReplicaSet → Pods**.

**Why the extra layer?** The Deployment manages *multiple* ReplicaSets to do **rolling updates**: on a new image it creates a *new* ReplicaSet and scales it up while scaling the old one down — zero-downtime deploys and instant rollback.

---

## 3. What a Deployment Manifest Means

A **manifest** is a declarative YAML file describing **desired state** — *what* you want, not *how* to achieve it. Kubernetes reconciles reality to match it.

```yaml
apiVersion: apps/v1        # which API group/version handles this object
kind: Deployment           # the object type
metadata:
  name: docker-eks-demo    # object name
spec:                      # DESIRED STATE
  replicas: 2              # want 2 pods
  selector:
    matchLabels:
      app: docker-eks-demo # which pods this Deployment owns
  template:                # the "cookie cutter" for each pod
    metadata:
      labels:
        app: docker-eks-demo   # MUST match selector + Service selector
    spec:
      containers:
      - image: <AWS_ACCOUNT_ID>.dkr.ecr.eu-north-1.amazonaws.com/demo-practice:1.0.0
        ports: [8080]
        livenessProbe:  ...   # restart if unhealthy
        readinessProbe: ...   # remove from traffic if not ready
```

**Interview phrasing:** *"A manifest is declarative desired state. I describe the end goal; controllers reconcile continuously to reach and maintain it. That's what makes Kubernetes self-healing and idempotent — applying the same manifest twice is safe."*

---

## 4. Kubernetes Objects in This Project

Named in hierarchy order (shows you understand the chain):

**1. Deployment** (`kind: Deployment`, name `docker-eks-demo`)
> A controller that manages stateless app replicas declaratively. You declare desired state; it reconciles.

Key fields:
- `replicas: 2` → desired number of pods.
- `selector.matchLabels: app=docker-eks-demo` → which pods it owns.
- `image: ...ecr.../demo-practice:1.0.0` → pulled from **ECR**.
- `livenessProbe` (`/actuator/health/liveness`) → if it fails, kubelet **restarts** the container.
- `readinessProbe` (`/actuator/health/readiness`) → if it fails, the pod is **removed from the Service endpoints** (no traffic) but not restarted.
- `resources.requests/limits` → requests drive **scheduling**, limits drive **throttling/OOM-kill**.

**2. ReplicaSet** (created *by* the Deployment)
> Guarantees N pods exist. On an update, the Deployment creates a new ReplicaSet and shifts pods over — that's rolling updates and rollbacks.

**3. Pod** (created by the ReplicaSet)
> Smallest deployable unit — one or more containers sharing a network namespace and IP. Here: one container running the Spring Boot JAR on port 8080.

**4. Service** (`kind: Service`, `type: LoadBalancer`, name `docker-eks-demo-service`)
> Pods are ephemeral and their IPs change. A Service gives a stable virtual IP + DNS and load-balances across matching pods. `type: LoadBalancer` makes EKS provision an **AWS load balancer**, mapping external port 80 → container port 8080.

> ⚠️ **Common trap:** the Service `selector: app=docker-eks-demo` MUST match the pod template labels. If they don't match, the Service has **no endpoints** and traffic goes nowhere.

---

## 5. Kubernetes Components (Control Plane vs Worker)

**Control plane = the brain (decides). Worker nodes = the muscle (runs).** In EKS, AWS manages the control plane.

**Control plane (AWS-managed in EKS):**

| Component | Role |
|---|---|
| **kube-apiserver** | Front door. Every request (kubectl, controllers, kubelet) goes through it. Validates, authenticates, persists to etcd. |
| **etcd** | The cluster database — key-value store holding desired + current state. Single source of truth. |
| **kube-scheduler** | Watches for unscheduled pods; picks a node based on resource requests, taints, affinity. |
| **controller-manager** | Runs reconciliation loops (Deployment/ReplicaSet controllers keep replica counts correct). |
| **cloud-controller-manager** | EKS-specific glue — provisions the AWS load balancer when you create a `LoadBalancer` Service. |

**Worker node (your EC2 / Auto Mode node):**

| Component | Role |
|---|---|
| **kubelet** | Node agent. Talks to apiserver, starts/stops containers, runs liveness/readiness probes, reports health. |
| **container runtime (containerd)** | Pulls the image from ECR and runs the container. |
| **kube-proxy / CNI** | Networking. kube-proxy programs routing rules for Service traffic; the CNI plugin gives each pod its IP. |

---

## 6. Kubernetes Architecture Diagram

```
                         ┌──────────────────────────────────────────────┐
   kubectl / CI  ───────▶│                CONTROL PLANE                  │
   (your EC2)            │                                              │
                         │   ┌────────────────┐    ┌──────────────┐     │
                         │   │  kube-apiserver│◀──▶│    etcd      │     │
                         │   │  (front door)  │    │ (state store)│     │
                         │   └───────┬────────┘    └──────────────┘     │
                         │           │                                  │
                         │   ┌───────┴────────┐  ┌──────────────────┐   │
                         │   │ kube-scheduler │  │ controller-mgr   │   │
                         │   │ (place pods)   │  │ (reconcile loops)│   │
                         │   └────────────────┘  └──────────────────┘   │
                         │                       ┌──────────────────┐   │
                         │                       │ cloud-controller │   │
                         │                       │ (makes AWS ELB)  │   │
                         └───────────────────────┴────────┬─────────┘   │
                                                          │ (apiserver ⇄ kubelet)
            ┌─────────────────────────────────────────────┼─────────────────────┐
            │                      WORKER NODES            │                     │
            ▼                                              ▼                     │
   ┌──────────────────────┐                      ┌──────────────────────┐        │
   │   Node 1             │                      │   Node 2             │        │
   │  ┌────────────────┐  │                      │  ┌────────────────┐  │        │
   │  │ kubelet        │  │                      │  │ kubelet        │  │        │
   │  │ kube-proxy/CNI │  │                      │  │ kube-proxy/CNI │  │        │
   │  │ containerd     │  │                      │  │ containerd     │  │        │
   │  │  ┌──────────┐  │  │                      │  │  ┌──────────┐  │  │        │
   │  │  │ Pod(8080)│  │  │                      │  │  │ Pod(8080)│  │  │        │
   │  │  └──────────┘  │  │                      │  │  └──────────┘  │  │        │
   │  └────────────────┘  │                      │  └────────────────┘  │        │
   └──────────────────────┘                      └──────────────────────┘        │
            ▲                                                                     │
            │   user traffic → AWS LoadBalancer (from type:LoadBalancer Service)  │
            └─────────────────────────────────────────────────────────────────────
```

- The **apiserver is the only component that talks to etcd** — everything else goes through the apiserver.
- Control plane = decides; worker nodes = execute.

---

## 7. End-to-End Process Flow

Narrate chronologically from `kubectl apply`:

1. **`kubectl apply -f k8s-deployment.yaml`** → kubectl sends the manifest to the **kube-apiserver**.
2. **apiserver** authenticates the caller (via the EKS **Access Entry** for the caller's IAM role), validates the YAML, and writes desired state (Deployment + Service) to **etcd**.
3. The **Deployment controller** sees a new Deployment → creates a **ReplicaSet**.
4. The **ReplicaSet controller** sees "desired 2, current 0" → creates **2 Pod objects** (unscheduled).
5. The **scheduler** evaluates nodes against `resources.requests` (256Mi / 250m) and **binds** each pod to a node. *(With EKS Auto Mode, if no node fits, a node is auto-provisioned here.)*
6. The **kubelet** on the chosen node tells **containerd** to **pull the ECR image** and start the container on port 8080.
7. kubelet runs the **readiness probe** (`/actuator/health/readiness`). Until it passes, the pod is **not** added to the Service endpoints.
8. Once ready, the pod IP is added to the **Service endpoints**. The **cloud-controller-manager** has provisioned an **AWS LoadBalancer** for the `type: LoadBalancer` Service.
9. A user hits `http://<elb-hostname>/api/info` → AWS LB → node → **kube-proxy/CNI** routes to a healthy pod on 8080 → Spring Boot returns JSON.
10. Continuously: kubelet runs the **liveness probe**; if it fails, the container is **restarted**. If a pod/node dies, the ReplicaSet recreates the pod — **self-healing**.

**One-paragraph version:**
> "I package my Spring Boot app as a Docker image in ECR. I apply a Deployment manifest to the EKS API server, which stores desired state in etcd. Controllers create a ReplicaSet and 2 Pods; the scheduler places them on nodes; the kubelet pulls the image and runs the containers, using actuator health endpoints as readiness and liveness probes. A LoadBalancer Service gives a stable AWS endpoint that load-balances across healthy pods. Kubernetes continuously reconciles desired vs actual state, so it self-heals and does zero-downtime rolling updates."

---

## 8. AWS EKS vs Standalone Kubernetes

**Core distinction: EKS = AWS runs the control plane for you; you own the workloads/nodes.**

| Aspect | **Standalone Kubernetes** (kubeadm/on-prem) | **AWS EKS** |
|---|---|---|
| Control plane | You install/run/patch apiserver, etcd, scheduler | **AWS-managed**, multi-AZ, auto-patched, SLA-backed |
| etcd backups | Your responsibility | AWS handles it |
| High availability | You design it (multiple masters, external etcd) | Built-in across 3 AZs |
| Worker nodes | You manage all | Managed Node Groups / Fargate / **Auto Mode** |
| Authentication | Certs / RBAC yourself | **IAM-integrated** — EKS API auth mode + **Access Entries** |
| Networking | Install a CNI (Calico, Flannel…) | AWS **VPC CNI** — pods get real VPC IPs |
| LoadBalancer Service | Needs MetalLB or a cloud provider | Native — provisions **AWS ELB/NLB** automatically |
| Image registry | Any | Integrates with **ECR** |
| Upgrades | Fully manual | One-click control-plane upgrade; you roll nodes |
| Cost | Infra only, more ops effort | ~$0.10/hr per cluster + compute, far less ops |

**Soundbite:** *"EKS offloads the undifferentiated heavy lifting — control-plane HA, etcd, patching — and integrates Kubernetes auth/networking/LB with IAM, VPC, and ELB. I trade some control for reliability and reduced operational burden."*

---

## 9. Most Important kubectl Commands

**Inspect / read:**
```bash
kubectl get nodes                      # list worker nodes + status
kubectl get pods -o wide               # pods + which node + pod IP
kubectl get deploy,rs,pods             # the Deployment→ReplicaSet→Pod chain
kubectl get svc                        # services + EXTERNAL-IP (the LB URL)
kubectl describe pod <pod>             # events, probe failures, pull errors ← #1 debug tool
kubectl get events --sort-by=.lastTimestamp   # cluster-wide timeline
```

**Logs / exec:**
```bash
kubectl logs <pod>                     # container stdout
kubectl logs <pod> --previous          # logs from the crashed/restarted container
kubectl logs -f <pod>                  # stream live
kubectl exec -it <pod> -- sh           # shell inside the container
```

**Apply / manage:**
```bash
kubectl apply -f k8s-deployment.yaml   # declarative create/update
kubectl rollout status deploy/docker-eks-demo   # watch a rollout
kubectl rollout undo deploy/docker-eks-demo     # roll back
kubectl scale deploy/docker-eks-demo --replicas=4
kubectl set image deploy/docker-eks-demo docker-eks-demo=...:2.0.0  # update image
kubectl delete -f k8s-deployment.yaml
```

**Debug / access:**
```bash
kubectl get pod <pod> -o yaml          # full live spec + status
kubectl port-forward svc/docker-eks-demo-service 8080:80   # test without a public LB
kubectl top pods                       # CPU/mem (needs metrics-server)
kubectl get endpoints <svc>            # confirm Service → pod wiring
```

**EKS-specific (AWS CLI, not kubectl):**
```bash
aws eks update-kubeconfig --name <cluster> --region eu-north-1   # wire kubectl to the cluster
aws eks list-access-entries --cluster-name <cluster>            # auth entries
```

**Top 5 to memorize:** `get pods -o wide`, `describe pod`, `logs --previous`, `rollout undo`, `apply`.

---

## 10. Debugging Techniques

**Method (say it as a method, not random commands):**
*"I debug top-down: is it scheduled → is it running → is it ready → is traffic reaching it?"*

1. **Pod stuck `Pending`** → `kubectl describe pod` → Events.
   - "insufficient cpu/memory" = no node fits → add/scale nodes (Auto Mode provisions one).
   - "didn't match node selector/taints" = scheduling constraint.
2. **`ImagePullBackOff` / `ErrImagePull`** → wrong image name/tag **or** node IAM role lacks ECR pull (`AmazonEC2ContainerRegistryReadOnly`).
3. **`CrashLoopBackOff`** → container starts then dies → `kubectl logs <pod> --previous` (bad config, missing env, port conflict).
4. **Pod `Running` but no traffic** → readiness probe failing or **Service selector doesn't match pod labels** → `kubectl get endpoints <svc>` (empty = misconfigured).
5. **`Unauthorized` from kubectl** → EKS auth, not network → missing **Access Entry** for the IAM role kubectl uses.
6. **LoadBalancer `EXTERNAL-IP <pending>`** → cloud-controller can't provision ELB → check subnet tags / LB controller / IAM.
7. **Golden rule:** `kubectl describe` + `kubectl get events` first — 80% of answers are in the Events section.

---

## 11. Architect-Level Q&A

**Q: Liveness vs readiness vs startup probe?**
Readiness = control *traffic* (remove from LB, no restart). Liveness = control *lifecycle* (restart container). Startup = for slow-booting apps, gates the other two until the app is up. This app exposes all via Spring Actuator.

**Q: How do you achieve zero-downtime deployments?**
RollingUpdate with `maxSurge`/`maxUnavailable`, backed by readiness probes so traffic only shifts to ready pods; `rollout undo` for instant rollback. For more safety: blue-green or canary (e.g., Argo Rollouts).

**Q: Pod vs Deployment vs StatefulSet vs DaemonSet?**
Deployment = stateless replicas (this app). StatefulSet = stable identity/storage (databases, Kafka). DaemonSet = one pod per node (log/monitoring agents). Job/CronJob = batch.

**Q: How does a Service route traffic?**
Service = stable virtual IP + DNS. `type: LoadBalancer` → cloud-controller provisions an AWS ELB → ELB → NodePort → kube-proxy → pod IP (via VPC CNI). Types: ClusterIP (internal), NodePort (node:port), LoadBalancer (external), plus Ingress for L7/host-based routing.

**Q: How do you secure an EKS cluster?**
- **AuthN/Z:** IAM + EKS Access Entries + Kubernetes RBAC (least privilege). Scope down from `AmazonEKSClusterAdminPolicy` in prod.
- **Network:** private API endpoint, NetworkPolicies, security groups, private subnets for nodes.
- **Workload:** no `root`, read-only FS, resource limits, Pod Security Standards, IRSA (IAM Roles for Service Accounts) instead of node-wide creds.
- **Supply chain:** scan ECR images, signed images, admission control.

**Q: How do you scale?**
Three layers: **HPA** (scale pods on CPU/mem/custom metrics), **Cluster Autoscaler / Karpenter / EKS Auto Mode** (scale nodes), **VPA** (right-size requests). Requests/limits drive all of it.

**Q: What happens when a node dies?**
apiserver stops getting kubelet heartbeats → node marked `NotReady` → after a timeout pods are evicted → ReplicaSet recreates them → scheduler places them on healthy nodes (Auto Mode may add capacity). Self-healing by design.

**Q: (Real from this project) Why might worker nodes fail to join the cluster?**
Nodes couldn't register with the control plane — a **networking/IAM** issue in a locked-down account (org SCP blocking OIDC; nodes in subnets without a path to the API server). Shows reasoning about the node↔control-plane handshake, not just happy-path YAML. Fix path: public subnets with a route to the API endpoint, correct node IAM role, and valid cluster access entries.

**Q: Private vs Public API endpoint access (also real here)?**
- **Public** → endpoint resolves to public IPs; callers reach it over the internet (allowlist CIDRs).
- **Private** → endpoint resolves to **private VPC IPs**; callers must be in-VPC and the **cluster security group must allow 443**.
- **Public + Private** → inside the VPC it resolves to private IPs. A classic symptom: `dial tcp 172.31.x.x:443: i/o timeout` = reached the private endpoint path but the security group blocks 443.
```
