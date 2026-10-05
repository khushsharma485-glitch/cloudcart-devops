package com.cloudcart.order.api;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Positive;

public record CreateOrderRequest(
        @NotNull @Positive Long userId,
        @NotNull @Positive Long productId,
        @NotNull @Min(1) @Max(1000) Integer quantity) {
}
