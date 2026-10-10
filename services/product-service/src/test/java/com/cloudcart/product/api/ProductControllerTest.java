package com.cloudcart.product.api;

import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.cloudcart.product.error.NotFoundException;
import com.cloudcart.product.service.ProductService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.webmvc.test.autoconfigure.WebMvcTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

@WebMvcTest(ProductController.class)
class ProductControllerTest {

    @Autowired
    private MockMvc mvc;

    @MockitoBean
    private ProductService productService;

    @Test
    void negativePriceAndStockAreRejected() throws Exception {
        mvc.perform(post("/api/products")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"X\",\"price\":-1,\"stock\":-5}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.price").exists())
                .andExpect(jsonPath("$.errors.stock").exists());
    }

    @Test
    void missingRequiredFieldsAreRejectedOnUpdate() throws Exception {
        mvc.perform(put("/api/products/1").contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.errors.name").exists())
                .andExpect(jsonPath("$.errors.price").exists());
    }

    @Test
    void unknownProductReturns404() throws Exception {
        when(productService.findById(3L)).thenThrow(new NotFoundException("Product 3 not found"));

        mvc.perform(get("/api/products/3"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.detail").value("Product 3 not found"));
    }
}
