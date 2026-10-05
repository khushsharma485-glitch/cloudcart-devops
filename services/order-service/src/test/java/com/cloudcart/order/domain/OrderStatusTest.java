package com.cloudcart.order.domain;

import static org.assertj.core.api.Assertions.assertThat;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

class OrderStatusTest {

    @ParameterizedTest
    @CsvSource({
        "PENDING,CONFIRMED,true",
        "PENDING,CANCELLED,true",
        "PENDING,SHIPPED,false",
        "CONFIRMED,SHIPPED,true",
        "CONFIRMED,CANCELLED,true",
        "SHIPPED,DELIVERED,true",
        "SHIPPED,CANCELLED,false",
        "DELIVERED,PENDING,false",
        "CANCELLED,CONFIRMED,false"
    })
    void transitions(OrderStatus from, OrderStatus to, boolean allowed) {
        assertThat(from.canTransitionTo(to)).isEqualTo(allowed);
    }

    @Test
    void terminalStatesHaveNoNextState() {
        assertThat(OrderStatus.DELIVERED.allowedNext()).isEmpty();
        assertThat(OrderStatus.CANCELLED.allowedNext()).isEmpty();
    }
}
