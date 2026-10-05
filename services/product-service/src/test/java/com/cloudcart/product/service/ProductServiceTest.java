package com.cloudcart.product.service;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import com.cloudcart.product.api.ProductRequest;
import com.cloudcart.product.domain.Product;
import com.cloudcart.product.domain.ProductRepository;
import com.cloudcart.product.error.NotFoundException;
import java.math.BigDecimal;
import java.util.Optional;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

@ExtendWith(MockitoExtension.class)
class ProductServiceTest {

    @Mock
    private ProductRepository repository;

    @InjectMocks
    private ProductService service;

    @Test
    void createTrimsNameAndSaves() {
        when(repository.save(any(Product.class))).thenAnswer(inv -> inv.getArgument(0));

        Product saved = service.create(new ProductRequest("  Keyboard ", "Mechanical", new BigDecimal("49.99"), 10));

        assertThat(saved.getName()).isEqualTo("Keyboard");
        assertThat(saved.getPrice()).isEqualByComparingTo("49.99");
        assertThat(saved.getStock()).isEqualTo(10);
    }

    @Test
    void updateChangesAllFields() {
        Product existing = new Product("Old", "old", BigDecimal.ONE, 1);
        when(repository.findById(5L)).thenReturn(Optional.of(existing));

        Product updated = service.update(5L, new ProductRequest("New", "new", BigDecimal.TEN, 3));

        assertThat(updated.getName()).isEqualTo("New");
        assertThat(updated.getDescription()).isEqualTo("new");
        assertThat(updated.getPrice()).isEqualByComparingTo(BigDecimal.TEN);
        assertThat(updated.getStock()).isEqualTo(3);
    }

    @Test
    void updateMissingProductThrows() {
        when(repository.findById(5L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> service.update(5L, new ProductRequest("X", null, BigDecimal.ONE, 1)))
                .isInstanceOf(NotFoundException.class);
    }

    @Test
    void deleteMissingProductThrows() {
        when(repository.existsById(9L)).thenReturn(false);

        assertThatThrownBy(() -> service.delete(9L)).isInstanceOf(NotFoundException.class);
        verify(repository, never()).deleteById(any());
    }
}
