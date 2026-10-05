package com.cloudcart.order.client;

import java.time.Duration;
import org.springframework.boot.context.properties.ConfigurationProperties;

@ConfigurationProperties(prefix = "clients")
public record ClientProperties(
        Endpoint userService,
        Endpoint productService,
        Duration connectTimeout,
        Duration readTimeout) {

    public record Endpoint(String baseUrl) {
    }
}
