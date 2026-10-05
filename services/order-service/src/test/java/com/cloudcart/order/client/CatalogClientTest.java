package com.cloudcart.order.client;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.springframework.test.web.client.match.MockRestRequestMatchers.requestTo;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withResourceNotFound;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withServerError;
import static org.springframework.test.web.client.response.MockRestResponseCreators.withSuccess;

import com.cloudcart.order.error.DownstreamUnavailableException;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.http.MediaType;
import org.springframework.test.web.client.MockRestServiceServer;
import org.springframework.web.client.RestClient;

class CatalogClientTest {

    private MockRestServiceServer users;
    private MockRestServiceServer products;
    private CatalogClient client;

    @BeforeEach
    void setUp() {
        RestClient.Builder userBuilder = RestClient.builder().baseUrl("http://user-service");
        RestClient.Builder productBuilder = RestClient.builder().baseUrl("http://product-service");
        users = MockRestServiceServer.bindTo(userBuilder).build();
        products = MockRestServiceServer.bindTo(productBuilder).build();
        client = new CatalogClient(userBuilder.build(), productBuilder.build());
    }

    @Test
    void userExistsTrueOn200() {
        users.expect(requestTo("http://user-service/api/users/1"))
                .andRespond(withSuccess("{\"id\":1}", MediaType.APPLICATION_JSON));

        assertThat(client.userExists(1L)).isTrue();
    }

    @Test
    void userExistsFalseOn404() {
        users.expect(requestTo("http://user-service/api/users/2")).andRespond(withResourceNotFound());

        assertThat(client.userExists(2L)).isFalse();
    }

    @Test
    void userServiceErrorBecomesDownstreamUnavailable() {
        users.expect(requestTo("http://user-service/api/users/3")).andRespond(withServerError());

        assertThatThrownBy(() -> client.userExists(3L))
                .isInstanceOf(DownstreamUnavailableException.class)
                .hasMessageContaining("user-service");
    }

    @Test
    void findProductParsesSnapshot() {
        products.expect(requestTo("http://product-service/api/products/5"))
                .andRespond(withSuccess(
                        "{\"id\":5,\"name\":\"Desk\",\"price\":150.00,\"stock\":4,\"description\":\"ignored\"}",
                        MediaType.APPLICATION_JSON));

        ProductSnapshot product = client.findProduct(5L).orElseThrow();
        assertThat(product.price()).isEqualByComparingTo("150.00");
        assertThat(product.stock()).isEqualTo(4);
    }

    @Test
    void findProductEmptyOn404() {
        products.expect(requestTo("http://product-service/api/products/6")).andRespond(withResourceNotFound());

        assertThat(client.findProduct(6L)).isEmpty();
    }
}
