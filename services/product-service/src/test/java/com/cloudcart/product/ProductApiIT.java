package com.cloudcart.product;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.Map;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
class ProductApiIT {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @Autowired
    private TestRestTemplate rest;

    @Test
    void productLifecycle() {
        ResponseEntity<Map> created = rest.postForEntity("/api/products",
                Map.of("name", "Laptop", "description", "14 inch", "price", 999.99, "stock", 5), Map.class);
        assertThat(created.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        Number id = (Number) created.getBody().get("id");

        ResponseEntity<Map> updated = rest.exchange("/api/products/" + id, HttpMethod.PUT,
                new HttpEntity<>(Map.of("name", "Laptop Pro", "price", 1299.50, "stock", 3)), Map.class);
        assertThat(updated.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(updated.getBody()).containsEntry("name", "Laptop Pro").containsEntry("stock", 3);
        assertThat(((Number) updated.getBody().get("price")).doubleValue()).isEqualTo(1299.50);

        assertThat(rest.getForEntity("/api/products", Object[].class).getBody()).isNotEmpty();

        rest.delete("/api/products/" + id);
        assertThat(rest.getForEntity("/api/products/" + id, Map.class).getStatusCode())
                .isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    void prometheusEndpointIsExposed() {
        rest.getForEntity("/api/products", String.class);
        String metrics = rest.getForObject("/actuator/prometheus", String.class);
        assertThat(metrics)
                .contains("http_server_requests_seconds_bucket")
                .contains("application=\"product-service\"");
        assertThat(rest.getForEntity("/actuator/health/readiness", String.class).getStatusCode())
                .isEqualTo(HttpStatus.OK);
    }
}
