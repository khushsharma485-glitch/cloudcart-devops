package com.cloudcart.order.api;

import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.cloudcart.order.error.DownstreamUnavailableException;
import com.cloudcart.order.error.InvalidOrderException;
import com.cloudcart.order.service.OrderService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(OrderController.class)
class OrderControllerTest {

    private static final String VALID = "{\"userId\":101,\"productId\":501,\"quantity\":2}";

    @Autowired
    private MockMvc mvc;

    @MockitoBean
    private OrderService orderService;

    @Test
    void zeroQuantityIsRejected() throws Exception {
        mvc.perform(post("/api/orders").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":1,\"productId\":1,\"quantity\":0}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.quantity").exists());
    }

    @Test
    void businessRuleViolationReturns422() throws Exception {
        when(orderService.create(anyLong(), anyLong(), anyInt()))
                .thenThrow(new InvalidOrderException("User 101 does not exist"));

        mvc.perform(post("/api/orders").contentType(MediaType.APPLICATION_JSON).content(VALID))
                .andExpect(status().isUnprocessableEntity())
                .andExpect(jsonPath("$.detail").value("User 101 does not exist"));
    }

    @Test
    void dependencyOutageReturns503() throws Exception {
        when(orderService.create(anyLong(), anyLong(), anyInt()))
                .thenThrow(new DownstreamUnavailableException("product-service", null));

        mvc.perform(post("/api/orders").contentType(MediaType.APPLICATION_JSON).content(VALID))
                .andExpect(status().isServiceUnavailable())
                .andExpect(jsonPath("$.dependency").value("product-service"));
    }

    @Test
    void unknownStatusValueIsRejected() throws Exception {
        mvc.perform(put("/api/orders/1/status").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"status\":\"TELEPORTED\"}"))
                .andExpect(status().isBadRequest());
    }
}
