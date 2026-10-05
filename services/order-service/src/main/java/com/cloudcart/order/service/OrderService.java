package com.cloudcart.order.service;

import com.cloudcart.order.client.CatalogClient;
import com.cloudcart.order.client.ProductSnapshot;
import com.cloudcart.order.domain.Order;
import com.cloudcart.order.domain.OrderRepository;
import com.cloudcart.order.domain.OrderStatus;
import com.cloudcart.order.error.ConflictException;
import com.cloudcart.order.error.InvalidOrderException;
import com.cloudcart.order.error.NotFoundException;
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class OrderService {

    private static final Logger log = LoggerFactory.getLogger(OrderService.class);

    private final OrderRepository repository;
    private final CatalogClient catalog;
    private final MeterRegistry meterRegistry;
    private final Counter ordersCreated;

    public OrderService(OrderRepository repository, CatalogClient catalog, MeterRegistry meterRegistry) {
        this.repository = repository;
        this.catalog = catalog;
        this.meterRegistry = meterRegistry;
        this.ordersCreated = Counter.builder("cloudcart.orders.placed")
                .description("Orders successfully created")
                .register(meterRegistry);
    }

    /**
     * Validates the user and product against their owning services, then
     * stores the order with the price captured at order time. Remote calls
     * are made before the transaction starts so a slow dependency never
     * holds a database connection.
     */
    public Order create(Long userId, Long productId, int quantity) {
        if (!catalog.userExists(userId)) {
            rejected("unknown_user");
            throw new InvalidOrderException("User " + userId + " does not exist");
        }
        ProductSnapshot product = catalog.findProduct(productId).orElseThrow(() -> {
            rejected("unknown_product");
            return new InvalidOrderException("Product " + productId + " does not exist");
        });
        if (product.stock() < quantity) {
            rejected("insufficient_stock");
            throw new InvalidOrderException("Insufficient stock for product " + productId
                    + ": requested " + quantity + ", available " + product.stock());
        }

        Order saved = repository.save(new Order(userId, productId, quantity, product.price()));
        ordersCreated.increment();
        log.info("Order created id={} userId={} productId={} quantity={} total={}",
                saved.getId(), userId, productId, quantity, saved.getTotalPrice());
        return saved;
    }

    @Transactional(readOnly = true)
    public Order findById(Long id) {
        return repository.findById(id)
                .orElseThrow(() -> new NotFoundException("Order " + id + " not found"));
    }

    @Transactional(readOnly = true)
    public List<Order> findByUser(Long userId) {
        return repository.findByUserIdOrderByCreatedAtDesc(userId);
    }

    @Transactional
    public Order updateStatus(Long id, OrderStatus next) {
        Order order = findById(id);
        OrderStatus current = order.getStatus();
        if (!current.canTransitionTo(next)) {
            throw new ConflictException("Order " + id + " cannot move from " + current + " to " + next
                    + "; allowed: " + current.allowedNext());
        }
        order.changeStatus(next);
        log.info("Order status changed id={} from={} to={}", id, current, next);
        return order;
    }

    private void rejected(String reason) {
        meterRegistry.counter("cloudcart.orders.rejected", "reason", reason).increment();
        log.warn("Order failed reason={}", reason);
    }
}
