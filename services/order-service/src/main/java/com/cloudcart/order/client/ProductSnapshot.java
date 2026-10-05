package com.cloudcart.order.client;

import java.math.BigDecimal;

/** The subset of product-service's response that order-service needs. */
public record ProductSnapshot(Long id, String name, BigDecimal price, int stock) {
}
