package com.example.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api")
public class InfoController {

    @GetMapping("/info")
    public ResponseEntity<InfoResponse> getInfo() {
        InfoResponse response = InfoResponse.builder()
                .message("Sample application for Docker and EKS test")
                .applicationName("Docker EKS Demo Application")
                .version("1.0.0")
                .description("This is a demonstration Spring Boot application designed for Docker containerization and Kubernetes (EKS) deployment testing")
                .javaVersion(System.getProperty("java.version"))
                .timestamp(System.currentTimeMillis())
                .build();

        return ResponseEntity.ok(response);
    }

}
