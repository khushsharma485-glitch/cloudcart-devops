package com.cloudcart.order.chaos;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.util.concurrent.ThreadLocalRandom;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Configuration;
import org.springframework.web.servlet.HandlerInterceptor;
import org.springframework.web.servlet.config.annotation.InterceptorRegistry;
import org.springframework.web.servlet.config.annotation.WebMvcConfigurer;

/** Applies injected latency and errors to /api/** requests. */
@Configuration
@ConditionalOnProperty(name = "chaos.enabled", havingValue = "true")
public class ChaosInterceptor implements HandlerInterceptor, WebMvcConfigurer {

    private final ChaosState state;

    public ChaosInterceptor(ChaosState state) {
        this.state = state;
    }

    @Override
    public void addInterceptors(InterceptorRegistry registry) {
        registry.addInterceptor(this).addPathPatterns("/api/**");
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler)
            throws Exception {
        long latency = state.getLatencyMillis();
        if (latency > 0) {
            Thread.sleep(latency);
        }
        if (state.getErrorRate() > 0 && ThreadLocalRandom.current().nextDouble() < state.getErrorRate()) {
            response.sendError(HttpServletResponse.SC_INTERNAL_SERVER_ERROR, "Injected failure");
            return false;
        }
        return true;
    }
}
