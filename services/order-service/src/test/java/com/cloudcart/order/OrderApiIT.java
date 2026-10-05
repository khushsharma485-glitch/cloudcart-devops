package com.cloudcart.order;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.when;

import com.cloudcart.order.client.CatalogClient;
import com.cloudcart.order.client.ProductSnapshot;
import java.math.BigDecimal;
import java.util.Map;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.testcontainers.service.connection.ServiceConnection;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.testcontainers.containers.PostgreSQLContainer;
import org.testcontainers.junit.jupiter.Container;
import org.testcontainers.junit.jupiter.Testcontainers;

/**
 * Real PostgreSQL and real HTTP stack. The downstream services are mocked
 * here; the end-to-end path across all three services is exercised by the
 * smoke tests against docker compose / Kubernetes (tests/smoke).
 */
@Testcontainers
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "chaos.enabled=true")
class OrderApiIT {

    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> postgres = new PostgreSQLContainer<>("postgres:16-alpine");

    @Autowired
    private TestRestTemplate rest;

    @MockitoBean
    private CatalogClient catalog;

    @Test
    void orderLifecycle() {
        when(catalog.userExists(101L)).thenReturn(true);
        when(catalog.findProduct(501L))
                .thenReturn(Optional.of(new ProductSnapshot(501L, "Mouse", new BigDecimal("25.00"), 50)));

        ResponseEntity<Map> created = rest.postForEntity("/api/orders",
                Map.of("userId", 101, "productId", 501, "quantity", 2), Map.class);
        assertThat(created.getStatusCode()).isEqualTo(HttpStatus.CREATED);
        assertThat(created.getBody()).containsEntry("status", "PENDING");
        assertThat(((Number) created.getBody().get("totalPrice")).doubleValue()).isEqualTo(50.0);
        Number id = (Number) created.getBody().get("id");

        ResponseEntity<Map> confirmed = rest.exchange("/api/orders/" + id + "/status", HttpMethod.PUT,
                new HttpEntity<>(Map.of("status", "CONFIRMED")), Map.class);
        assertThat(confirmed.getBody()).containsEntry("status", "CONFIRMED");

        ResponseEntity<Map> illegal = rest.exchange("/api/orders/" + id + "/status", HttpMethod.PUT,
                new HttpEntity<>(Map.of("status", "PENDING")), Map.class);
        assertThat(illegal.getStatusCode()).isEqualTo(HttpStatus.CONFLICT);

        ResponseEntity<Object[]> byUser = rest.getForEntity("/api/orders/user/101", Object[].class);
        assertThat(byUser.getBody()).hasSize(1);

        assertThat(rest.getForEntity("/api/orders/999999", Map.class).getStatusCode())
                .isEqualTo(HttpStatus.NOT_FOUND);
    }

    @Test
    void businessMetricsAreExported() {
        when(catalog.userExists(7L)).thenReturn(false);
        rest.postForEntity("/api/orders", Map.of("userId", 7, "productId", 1, "quantity", 1), Map.class);

        String metrics = rest.getForObject("/actuator/prometheus", String.class);
        assertThat(metrics)
                .contains("cloudcart_orders_placed_total")
                .contains("cloudcart_orders_rejected_total{application=\"order-service\",reason=\"unknown_user\"}");
    }

    @Test
    void chaosErrorInjectionCanBeToggled() {
        rest.postForEntity("/internal/chaos/errors?rate=1.0", null, Map.class);
        assertThat(rest.getForEntity("/api/orders/user/1", String.class).getStatusCode())
                .isEqualTo(HttpStatus.INTERNAL_SERVER_ERROR);

        rest.delete("/internal/chaos");
        assertThat(rest.getForEntity("/api/orders/user/1", String.class).getStatusCode())
                .isEqualTo(HttpStatus.OK);
    }
}
