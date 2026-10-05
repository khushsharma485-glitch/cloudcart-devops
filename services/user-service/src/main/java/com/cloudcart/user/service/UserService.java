package com.cloudcart.user.service;

import com.cloudcart.user.domain.User;
import com.cloudcart.user.domain.UserRepository;
import com.cloudcart.user.error.ConflictException;
import com.cloudcart.user.error.NotFoundException;
import java.util.List;
import java.util.Locale;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class UserService {

    private static final Logger log = LoggerFactory.getLogger(UserService.class);

    private final UserRepository repository;

    public UserService(UserRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public User create(String name, String email) {
        String normalisedEmail = email.trim().toLowerCase(Locale.ROOT);
        if (repository.existsByEmailIgnoreCase(normalisedEmail)) {
            throw new ConflictException("A user with email " + normalisedEmail + " already exists");
        }
        User saved = repository.save(new User(name.trim(), normalisedEmail));
        log.info("User created id={}", saved.getId());
        return saved;
    }

    @Transactional(readOnly = true)
    public List<User> findAll() {
        return repository.findAll();
    }

    @Transactional(readOnly = true)
    public User findById(Long id) {
        return repository.findById(id)
                .orElseThrow(() -> new NotFoundException("User " + id + " not found"));
    }

    @Transactional
    public void delete(Long id) {
        if (!repository.existsById(id)) {
            throw new NotFoundException("User " + id + " not found");
        }
        repository.deleteById(id);
        log.info("User deleted id={}", id);
    }
}
