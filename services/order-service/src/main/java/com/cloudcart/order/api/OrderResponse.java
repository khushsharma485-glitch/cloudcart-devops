package com.cloudcart.order.api;

import com.cloudcart.order.domain.Order;
import com.cloudcart.order.domain.OrderStatus;
import java.math.BigDecimal;
import java.time.Instant;

public record OrderResponse(
        Long id,
        Long userId,
        Long productId,
        int quantity,
        BigDecimal unitPrice,
        BigDecimal totalPrice,
        OrderStatus status,
        Instant createdAt,
        Instant updatedAt) {

    public static OrderResponse from(Order o) {
        return new OrderResponse(o.getId(), o.getUserId(), o.getProductId(), o.getQuantity(),
                o.getUnitPrice(), o.getTotalPrice(), o.getStatus(), o.getCreatedAt(), o.getUpdatedAt());
    }
}
