# Docker EKS Demo Application

A sample **Spring Boot (JDK 17)** application built to demonstrate the full container
pipeline: **build → Docker → AWS ECR → AWS EKS**. It exposes one info API and
Actuator health endpoints suitable for Kubernetes liveness/readiness probes.

> 📘 See **[CONCEPTS-NOTES.md](./CONCEPTS-NOTES.md)** for Kubernetes/EKS concept
> explanations, architecture diagrams, key `kubectl` commands, and interview Q&A.

---

## Features

- **Spring Boot 3.3.0** on **JDK 17**
- **Info Endpoint** (`/api/info`) — returns app metadata
- **Actuator Health** (`/actuator/health`) — plus Kubernetes liveness/readiness probes
- **Docker-ready** — `Dockerfile` + `docker-compose.yml`
- **Kubernetes-ready** — `k8s-deployment.yaml` (Deployment + LoadBalancer Service)

---

## Project Structure

```
docker-eks-demo/
├── src/
│   ├── main/
│   │   ├── java/com/example/
│   │   │   ├── DockerEksDemoApplication.java   # @SpringBootApplication main
│   │   │   └── controller/
│   │   │       ├── InfoController.java          # GET /api/info
│   │   │       └── InfoResponse.java            # Lombok DTO
│   │   └── resources/
│   │       └── application.properties           # port 8080, actuator config
│   └── test/
├── pom.xml                    # Java 17, Spring Boot 3.3.0
├── Dockerfile                 # eclipse-temurin:17-jre
├── .dockerignore
├── docker-compose.yml         # local run with healthcheck
├── k8s-deployment.yaml        # Deployment (2 replicas) + LoadBalancer Service
├── eks-cluster-config.yaml    # eksctl cluster config (optional path)
├── CONCEPTS-NOTES.md          # concepts + interview Q&A
└── README.md
```

---

## API Endpoints

### Application Info
```
GET /api/info
```
```json
{
  "message": "Sample application for Docker and EKS test",
  "applicationName": "Docker EKS Demo Application",
  "version": "1.0.0",
  "description": "This is a demonstration Spring Boot application designed for Docker containerization and Kubernetes (EKS) deployment testing",
  "javaVersion": "17.x.x",
  "timestamp": 1730000000000
}
```

### Health Check (used by Kubernetes probes)
```
GET /actuator/health
GET /actuator/health/liveness
GET /actuator/health/readiness
```
```json
{ "status": "UP" }
```

---

## Prerequisites

- Java 17 (JDK 17)
- Maven 3.6+
- Docker
- AWS CLI (configured; `aws sts get-caller-identity` works)
- kubectl
- (optional) eksctl

---

## Environment Used in This Project

| Item | Value |
|---|---|
| AWS account | `566078794302` |
| Region | `eu-north-1` |
| ECR repository | `566078794302.dkr.ecr.eu-north-1.amazonaws.com/demo-practice` |
| Image tag | `1.0.0` |
| EKS cluster | `thoughtful-bluegrass-otter` (created via AWS Console, EKS Auto Mode) |
| Build/push host | EC2 instance with IAM role `DemoRole` |

> Replace these with your own account ID / region / repo / cluster where applicable.

---

# Part 1 — Run Spring Boot on Docker (local / EC2)

### Step 1. Build the JAR
```bash
mvn clean package
```
Produces `target/docker-eks-demo-1.0.0.jar`.

### Step 2. Build the Docker image
```bash
docker build -t docker-eks-demo:1.0.0 .
```

### Step 3. Run the container
```bash
docker run -p 8080:8080 docker-eks-demo:1.0.0
```

### Step 4. Test the endpoints
```bash
curl http://localhost:8080/api/info
curl http://localhost:8080/actuator/health
```

### (Alternative) Run with Docker Compose
```bash
docker compose up --build        # start (includes a container healthcheck)
docker compose down              # stop
```

> 💡 **Opening port 8080 from your own machine:** if testing against an EC2 host,
> add an inbound rule to the EC2 security group allowing **TCP 8080** from your
> public IP (`<your-ip>/32`), then browse `http://<ec2-public-ip>:8080/api/info`.

---

# Part 2 — Push the image to AWS ECR

> All commands run on the build host (EC2). Use the **same user** for `docker login`
> and `docker push` (e.g. both with `sudo`), and the **same region**, or you get
> `no basic auth credentials`.

### Step 1. (One-time) Create the ECR repository
```bash
aws ecr create-repository --repository-name demo-practice --region eu-north-1
```

### Step 2. Authenticate Docker to ECR
```bash
aws ecr get-login-password --region eu-north-1 | \
  docker login --username AWS --password-stdin \
  566078794302.dkr.ecr.eu-north-1.amazonaws.com
```

### Step 3. Tag the image for ECR
```bash
docker tag docker-eks-demo:1.0.0 \
  566078794302.dkr.ecr.eu-north-1.amazonaws.com/demo-practice:1.0.0
```

### Step 4. Push
```bash
docker push 566078794302.dkr.ecr.eu-north-1.amazonaws.com/demo-practice:1.0.0
```

Verify in the console: **ECR → Repositories → demo-practice → image tag `1.0.0`**.

---

# Part 3 — Deploy to AWS EKS

EKS is a **managed** service: AWS runs the control plane (apiserver, etcd,
scheduler). You create the cluster, wire `kubectl` to it, grant access, and apply
your manifests. This project used an **AWS Console–created cluster with EKS Auto
Mode** (nodes are auto-provisioned when workloads need them).

### Step 1. Create the cluster (AWS Console)
Console → **EKS → Create cluster**:
- Name: `thoughtful-bluegrass-otter`
- Kubernetes version: current
- **EKS Auto Mode: Enabled** (auto-provisions compute — no manual node group needed)
- Authentication mode: **EKS API** (access via Access Entries)
- VPC: default VPC, **public subnets**
- API server endpoint access: **Public** (allowlist `0.0.0.0/0` for a practice cluster)

> Alternative (eksctl): `eksctl create cluster -f eks-cluster-config.yaml`
> — in a locked-down org account this can fail (SCP blocking OIDC, nodes not
> joining); the Console + Auto Mode path avoids that.

### Step 2. Wire kubectl to the cluster
```bash
aws eks update-kubeconfig --name thoughtful-bluegrass-otter --region eu-north-1
```

### Step 3. Grant your IAM identity access (fixes `Unauthorized`)
The cluster was created by your Console login; the EC2's `DemoRole` that `kubectl`
uses needs its own **Access Entry**, or `kubectl` returns
`You must be logged in to the server (Unauthorized)`.

Confirm the identity kubectl uses:
```bash
aws sts get-caller-identity
```

Create the access entry — **Console:** cluster → **Access** tab → **Create access
entry** → principal `arn:aws:iam::566078794302:role/DemoRole`, type Standard →
policy **AmazonEKSClusterAdminPolicy**, scope Cluster → Create.

**CLI equivalent:**
```bash
aws eks create-access-entry \
  --cluster-name thoughtful-bluegrass-otter \
  --principal-arn arn:aws:iam::566078794302:role/DemoRole \
  --type STANDARD --region eu-north-1

aws eks associate-access-policy \
  --cluster-name thoughtful-bluegrass-otter \
  --principal-arn arn:aws:iam::566078794302:role/DemoRole \
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
  --access-scope type=cluster --region eu-north-1
```

Verify:
```bash
kubectl get nodes
```

### Step 4. Deploy the application
`k8s-deployment.yaml` already points at the ECR image. Apply it:
```bash
kubectl apply -f k8s-deployment.yaml
```

Watch it come up (Auto Mode provisions a node in ~1–2 min):
```bash
kubectl get pods -w
kubectl get deploy,rs,pods
```
Each pod should reach `READY 1/1`, `STATUS Running`.

### Step 5. Get the LoadBalancer URL and access the app
```bash
kubectl get svc docker-eks-demo-service
```
Read the **`EXTERNAL-IP`** column (an AWS ELB hostname like
`a1b2...elb.eu-north-1.amazonaws.com`; wait if it shows `<pending>`).

The Service exposes port **80** → container **8080**, so use plain HTTP:
```bash
curl http://<EXTERNAL-HOSTNAME>/api/info
curl http://<EXTERNAL-HOSTNAME>/actuator/health
```
Or open `http://<EXTERNAL-HOSTNAME>/api/info` in a browser.

> ⏱️ The ELB hostname can take 2–3 minutes to become DNS-resolvable after creation.

---

## Kubernetes Configuration Reference

**Probes** (`k8s-deployment.yaml`):
- **Liveness** `/actuator/health/liveness` → restart container if it fails.
- **Readiness** `/actuator/health/readiness` → remove from Service traffic if not ready.

**Resources per pod:**
- Requests: 256Mi RAM, 250m CPU
- Limits: 512Mi RAM, 500m CPU

**Service:** `type: LoadBalancer`, port 80 → targetPort 8080.

---

## Local Development (no Docker)
```bash
mvn spring-boot:run
# → http://localhost:8080/api/info
```

---

## Troubleshooting (issues actually hit in this project)

| Symptom | Cause | Fix |
|---|---|---|
| `docker build` COPY jar fails | `target/` was in `.dockerignore` | Remove `target/` from `.dockerignore`, run `mvn clean package` first |
| `release version 21 not supported` | JDK 21 not on build host | Project set to Java 17 (pom.xml + Dockerfile) |
| `no basic auth credentials` on push | login/push user or region mismatch | Same user (both `sudo`) + same region for login and push |
| kubectl `no such host` | Stale kubeconfig to old cluster | `aws eks update-kubeconfig --name <cluster> --region eu-north-1` |
| kubectl `i/o timeout` to `172.31.x.x:443` | Private endpoint + SG blocks 443 | Enable Public endpoint access, or open 443 on the cluster security group |
| `You must be logged in (Unauthorized)` | IAM role has no EKS Access Entry | Create Access Entry for the role (Step 3 above) |
| Pod `Pending` | No node fits | Auto Mode provisions one; or add a node group |
| `ImagePullBackOff` | Node role lacks ECR pull | Attach `AmazonEC2ContainerRegistryReadOnly` to node role |
| Service `EXTERNAL-IP <pending>` | ELB still provisioning | Wait; check subnet tags / LB controller |

---

## Cleanup
```bash
kubectl delete -f k8s-deployment.yaml          # remove app + LoadBalancer
# then delete the EKS cluster from the Console (or: eksctl delete cluster ...)
```

---

## References
- [Spring Boot](https://spring.io/projects/spring-boot)
- [Docker](https://docs.docker.com/)
- [AWS ECR](https://docs.aws.amazon.com/ecr/)
- [AWS EKS](https://docs.aws.amazon.com/eks/)
- [Kubernetes](https://kubernetes.io/docs/)
