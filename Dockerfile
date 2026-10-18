# Use official Eclipse Temurin JDK 21 image
FROM eclipse-temurin:21-jre

# Set working directory
WORKDIR /app

# Copy the JAR file from build context
COPY target/docker-eks-demo-1.0.0.jar app.jar

# Expose port 8080
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/actuator/health || exit 1

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
