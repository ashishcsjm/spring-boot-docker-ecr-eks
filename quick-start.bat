@echo off
REM Quick Start Script for Docker EKS Demo Application (Windows)

echo =========================================
echo Docker EKS Demo Application Setup
echo =========================================

REM Step 1: Build the Spring Boot application
echo.
echo Step 1: Building Spring Boot application...
call mvn clean package

if errorlevel 1 (
    echo Maven build failed. Exiting.
    exit /b 1
)

echo ✓ Spring Boot application built successfully

REM Step 2: Build Docker image
echo.
echo Step 2: Building Docker image...
docker build -t docker-eks-demo:1.0.0 .

if errorlevel 1 (
    echo Docker build failed. Exiting.
    exit /b 1
)

echo ✓ Docker image built successfully

REM Step 3: Test Docker image locally
echo.
echo Step 3: Testing Docker image locally...
echo Starting container on port 8080...
docker run -d -p 8080:8080 --name docker-eks-demo-test docker-eks-demo:1.0.0

echo Waiting for application to start...
timeout /t 10

REM Test health endpoint
echo.
echo Testing /actuator/health endpoint...
curl http://localhost:8080/actuator/health

REM Test info endpoint
echo.
echo.
echo Testing /api/info endpoint...
curl http://localhost:8080/api/info

REM Stop the test container
echo.
echo.
echo Stopping test container...
docker stop docker-eks-demo-test
docker rm docker-eks-demo-test

echo.
echo =========================================
echo ✓ Application is ready!
echo =========================================
echo.
echo Next steps:
echo 1. Push to AWS ECR:
echo    aws ecr create-repository --repository-name docker-eks-demo --region us-east-1
echo    aws ecr get-login-password --region us-east-1 ^| docker login --username AWS --password-stdin ^<ACCOUNT_ID^>.dkr.ecr.us-east-1.amazonaws.com
echo    docker tag docker-eks-demo:1.0.0 ^<ACCOUNT_ID^>.dkr.ecr.us-east-1.amazonaws.com/docker-eks-demo:1.0.0
echo    docker push ^<ACCOUNT_ID^>.dkr.ecr.us-east-1.amazonaws.com/docker-eks-demo:1.0.0
echo.
echo 2. Update k8s-deployment.yaml with ECR image URL
echo.
echo 3. Deploy to EKS:
echo    kubectl apply -f k8s-deployment.yaml
echo =========================================
