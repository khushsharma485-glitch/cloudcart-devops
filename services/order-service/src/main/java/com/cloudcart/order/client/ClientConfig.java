package com.cloudcart.order.client;

import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/**
 * One RestClient per downstream service. The auto-configured builder is
 * used so outbound calls are recorded as http_client_requests metrics.
 * Timeouts are mandatory: a hung dependency must not exhaust our threads.
 */
@Configuration
public class ClientConfig {

    @Bean
    RestClient userRestClient(RestClient.Builder builder, ClientProperties props) {
        return build(builder, props, props.userService().baseUrl());
    }

    @Bean
    RestClient productRestClient(RestClient.Builder builder, ClientProperties props) {
        return build(builder, props, props.productService().baseUrl());
    }

    private static RestClient build(RestClient.Builder builder, ClientProperties props, String baseUrl) {
        SimpleClientHttpRequestFactory factory = new SimpleClientHttpRequestFactory();
        factory.setConnectTimeout(props.connectTimeout());
        factory.setReadTimeout(props.readTimeout());
        return builder.clone().baseUrl(baseUrl).requestFactory(factory).build();
    }
}
