# Docker EKS Demo Application

A sample Spring Boot application with JDK 21 designed for Docker containerization and AWS EKS (Elastic Kubernetes Service) deployment.

## Features

- **Spring Boot 3.3.0** with JDK 21
- **Health Endpoint** - Built-in health checks for Kubernetes probes
- **Info Endpoint** - Display application information
- **Actuator Endpoints** - Kubernetes-ready liveness and readiness probes
- **Docker Ready** - Includes Dockerfile for containerization
- **Kubernetes Ready** - Includes k8s-deployment.yaml for EKS deployment

## Project Structure

```
docker-eks-demo/
├── src/
│   ├── main/
│   │   ├── java/com/example/
│   │   │   ├── DockerEksDemoApplication.java
│   │   │   └── controller/
│   │   │       ├── InfoController.java
│   │   │       └── InfoResponse.java
│   │   └── resources/
│   │       └── application.properties
│   └── test/
├── pom.xml
├── Dockerfile
├── .dockerignore
├── k8s-deployment.yaml
└── README.md
```

## API Endpoints

### Health Check
```
GET /actuator/health
```
Returns the application health status. This endpoint is used by Kubernetes for liveness and readiness probes.

**Response:**
```json
{
  "status": "UP"
}
```

### Application Info
```
GET /api/info
```
Returns information about the application.

**Response:**
```json
{
  "message": "Sample application for Docker and EKS test",
  "applicationName": "Docker EKS Demo Application",
  "version": "1.0.0",
  "description": "This is a demonstration Spring Boot application designed for Docker containerization and Kubernetes (EKS) deployment testing",
  "javaVersion": "21.x.x",
  "timestamp": 1234567890
}
```

## Prerequisites

- Java 21 (JDK 21)
- Maven 3.6+
- Docker (for containerization)
- AWS CLI (for ECR push)
- kubectl (for EKS deployment)

## Build Instructions

### 1. Build the JAR file
```bash
mvn clean package
```

### 2. Build the Docker Image
```bash
docker build -t docker-eks-demo:1.0.0 .
```

### 3. Test the Docker Image Locally
```bash
docker run -p 8080:8080 docker-eks-demo:1.0.0
```

Test the endpoints:
```bash
curl http://localhost:8080/actuator/health
curl http://localhost:8080/api/info
```

## AWS ECR Deployment

### 1. Create an ECR Repository
```bash
aws ecr create-repository \
  --repository-name docker-eks-demo \
  --region us-east-1
```

### 2. Login to ECR
```bash
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com
```

### 3. Tag the Docker Image
```bash
docker tag docker-eks-demo:1.0.0 \
  <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/docker-eks-demo:1.0.0
```

### 4. Push to ECR
```bash
docker push <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/docker-eks-demo:1.0.0
```

## AWS EKS Deployment

### 1. Update k8s-deployment.yaml
Update the image URL in `k8s-deployment.yaml`:
```yaml
image: <AWS_ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/docker-eks-demo:1.0.0
```

### 2. Deploy to EKS
```bash
kubectl apply -f k8s-deployment.yaml
```

### 3. Verify Deployment
```bash
# Check deployment status
kubectl get deployments
kubectl get pods

# Check service
kubectl get services
kubectl describe service docker-eks-demo-service

# View logs
kubectl logs -f deployment/docker-eks-demo
```

### 4. Access the Application
```bash
# Get external IP
kubectl get service docker-eks-demo-service

# Test the endpoints
curl http://<EXTERNAL_IP>/api/info
curl http://<EXTERNAL_IP>/actuator/health
```

## Local Development

### Run the application locally
```bash
mvn spring-boot:run
```

The application will start on `http://localhost:8080`

### Test the endpoints
```bash
curl http://localhost:8080/actuator/health
curl http://localhost:8080/api/info
```

## Kubernetes Probes Configuration

The deployment includes:
- **Liveness Probe**: Checks if the application is running (`/actuator/health/liveness`)
- **Readiness Probe**: Checks if the application is ready to accept traffic (`/actuator/health/readiness`)

Both probes are configured with appropriate timeouts and failure thresholds for production use.

## Resource Limits

The Kubernetes deployment specifies:
- **Requests**: 256Mi RAM, 250m CPU
- **Limits**: 512Mi RAM, 500m CPU

Adjust these values based on your load testing and requirements.

## Notes

- The application uses Java 21 with G1GC garbage collector configuration
- Actuator endpoints are exposed for monitoring and health checks
- The Docker image uses Eclipse Temurin's official JDK 21 image
- All timestamps and IDs are automatically tracked and logged

## Troubleshooting

### Docker build fails
- Ensure you have run `mvn clean package` first
- Check that the JAR file exists in `target/` directory

### Kubernetes pod not starting
- Check pod logs: `kubectl logs <pod-name>`
- Verify the image exists in ECR and credentials are configured
- Check resource availability on the cluster

### Health check endpoints returning errors
- Verify the pod is in Running state: `kubectl get pods`
- Check application logs for errors

## References

- [Spring Boot Documentation](https://spring.io/projects/spring-boot)
- [Docker Documentation](https://docs.docker.com/)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
