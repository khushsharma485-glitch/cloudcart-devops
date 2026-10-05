package com.cloudcart.product.service;

import com.cloudcart.product.api.ProductRequest;
import com.cloudcart.product.domain.Product;
import com.cloudcart.product.domain.ProductRepository;
import com.cloudcart.product.error.NotFoundException;
import java.util.List;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class ProductService {

    private static final Logger log = LoggerFactory.getLogger(ProductService.class);

    private final ProductRepository repository;

    public ProductService(ProductRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public Product create(ProductRequest request) {
        Product saved = repository.save(new Product(
                request.name().trim(), request.description(), request.price(), request.stock()));
        log.info("Product created id={}", saved.getId());
        return saved;
    }

    @Transactional(readOnly = true)
    public List<Product> findAll() {
        return repository.findAll();
    }

    @Transactional(readOnly = true)
    public Product findById(Long id) {
        return repository.findById(id)
                .orElseThrow(() -> new NotFoundException("Product " + id + " not found"));
    }

    @Transactional
    public Product update(Long id, ProductRequest request) {
        Product product = findById(id);
        product.update(request.name().trim(), request.description(), request.price(), request.stock());
        log.info("Product updated id={}", id);
        return product;
    }

    @Transactional
    public void delete(Long id) {
        if (!repository.existsById(id)) {
            throw new NotFoundException("Product " + id + " not found");
        }
        repository.deleteById(id);
        log.info("Product deleted id={}", id);
    }
}
