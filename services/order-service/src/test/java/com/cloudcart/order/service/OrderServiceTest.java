package com.cloudcart.order.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudcart.order.client.CatalogClient;
import com.cloudcart.order.client.ProductSnapshot;
import com.cloudcart.order.domain.Order;
import com.cloudcart.order.domain.OrderRepository;
import com.cloudcart.order.domain.OrderStatus;
import com.cloudcart.order.error.ConflictException;
import com.cloudcart.order.error.DownstreamUnavailableException;
import com.cloudcart.order.error.InvalidOrderException;
import io.micrometer.core.instrument.simple.SimpleMeterRegistry;
import java.math.BigDecimal;
import java.util.Optional;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class OrderServiceTest {

    @Mock
    private OrderRepository repository;

    @Mock
    private CatalogClient catalog;

    private SimpleMeterRegistry meters;
    private OrderService service;

    @BeforeEach
    void setUp() {
        meters = new SimpleMeterRegistry();
        service = new OrderService(repository, catalog, meters);
    }

    @Test
    void createCapturesPriceAndComputesTotal() {
        when(catalog.userExists(101L)).thenReturn(true);
        when(catalog.findProduct(501L))
                .thenReturn(Optional.of(new ProductSnapshot(501L, "Mouse", new BigDecimal("19.99"), 10)));
        when(repository.save(any(Order.class))).thenAnswer(inv -> inv.getArgument(0));

        Order order = service.create(101L, 501L, 2);

        assertThat(order.getUnitPrice()).isEqualByComparingTo("19.99");
        assertThat(order.getTotalPrice()).isEqualByComparingTo("39.98");
        assertThat(order.getStatus()).isEqualTo(OrderStatus.PENDING);
        assertThat(meters.counter("cloudcart.orders.placed").count()).isEqualTo(1.0);
    }

    @Test
    void createRejectsUnknownUser() {
        when(catalog.userExists(1L)).thenReturn(false);

        assertThatThrownBy(() -> service.create(1L, 2L, 1))
                .isInstanceOf(InvalidOrderException.class)
                .hasMessageContaining("User 1");
        verify(repository, never()).save(any());
        assertThat(meters.counter("cloudcart.orders.rejected", "reason", "unknown_user").count()).isEqualTo(1.0);
    }

    @Test
    void createRejectsUnknownProduct() {
        when(catalog.userExists(1L)).thenReturn(true);
        when(catalog.findProduct(2L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.create(1L, 2L, 1))
                .isInstanceOf(InvalidOrderException.class)
                .hasMessageContaining("Product 2");
    }

    @Test
    void createRejectsInsufficientStock() {
        when(catalog.userExists(1L)).thenReturn(true);
        when(catalog.findProduct(2L)).thenReturn(Optional.of(new ProductSnapshot(2L, "X", BigDecimal.ONE, 1)));

        assertThatThrownBy(() -> service.create(1L, 2L, 5))
                .isInstanceOf(InvalidOrderException.class)
                .hasMessageContaining("Insufficient stock");
        verify(repository, never()).save(any());
    }

    @Test
    void createPropagatesDependencyOutage() {
        when(catalog.userExists(1L)).thenThrow(new DownstreamUnavailableException("user-service", null));

        assertThatThrownBy(() -> service.create(1L, 2L, 1)).isInstanceOf(DownstreamUnavailableException.class);
        verify(repository, never()).save(any());
    }

    @Test
    void updateStatusRejectsIllegalTransition() {
        Order order = new Order(1L, 2L, 1, BigDecimal.ONE);
        when(repository.findById(10L)).thenReturn(Optional.of(order));

        assertThatThrownBy(() -> service.updateStatus(10L, OrderStatus.DELIVERED))
                .isInstanceOf(ConflictException.class)
                .hasMessageContaining("PENDING");
    }

    @Test
    void updateStatusAppliesLegalTransition() {
        Order order = new Order(1L, 2L, 1, BigDecimal.ONE);
        when(repository.findById(10L)).thenReturn(Optional.of(order));

        assertThat(service.updateStatus(10L, OrderStatus.CONFIRMED).getStatus()).isEqualTo(OrderStatus.CONFIRMED);
    }
}
