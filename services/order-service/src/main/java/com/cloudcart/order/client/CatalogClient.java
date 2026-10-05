package com.cloudcart.order.client;

import com.cloudcart.order.error.DownstreamUnavailableException;
import java.util.Optional;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.stereotype.Component;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestClient;
import org.springframework.web.client.RestClientException;

/**
 * Calls user-service and product-service. A 404 from a dependency is a
 * business answer ("does not exist"); anything else (timeout, connection
 * refused, 5xx) means the dependency is unhealthy and we fail with 503.
 */
@Component
public class CatalogClient {

    private static final Logger log = LoggerFactory.getLogger(CatalogClient.class);

    private final RestClient userClient;
    private final RestClient productClient;

    public CatalogClient(@Qualifier("userRestClient") RestClient userClient,
                         @Qualifier("productRestClient") RestClient productClient) {
        this.userClient = userClient;
        this.productClient = productClient;
    }

    public boolean userExists(Long userId) {
        try {
            userClient.get().uri("/api/users/{id}", userId).retrieve().toBodilessEntity();
            return true;
        } catch (HttpClientErrorException.NotFound ex) {
            return false;
        } catch (RestClientException ex) {
            log.error("user-service call failed userId={} error={}", userId, ex.getMessage());
            throw new DownstreamUnavailableException("user-service", ex);
        }
    }

    public Optional<ProductSnapshot> findProduct(Long productId) {
        try {
            return Optional.ofNullable(productClient.get().uri("/api/products/{id}", productId)
                    .retrieve().body(ProductSnapshot.class));
        } catch (HttpClientErrorException.NotFound ex) {
            return Optional.empty();
        } catch (RestClientException ex) {
            log.error("product-service call failed productId={} error={}", productId, ex.getMessage());
            throw new DownstreamUnavailableException("product-service", ex);
        }
    }
}
