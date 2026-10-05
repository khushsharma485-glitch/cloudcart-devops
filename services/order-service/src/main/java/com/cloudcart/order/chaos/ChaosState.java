package com.cloudcart.order.chaos;

import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

@Component
@ConditionalOnProperty(name = "chaos.enabled", havingValue = "true")
public class ChaosState {

    private volatile double errorRate;
    private volatile long latencyMillis;

    public double getErrorRate() {
        return errorRate;
    }

    public void setErrorRate(double errorRate) {
        this.errorRate = Math.min(Math.max(errorRate, 0), 1);
    }

    public long getLatencyMillis() {
        return latencyMillis;
    }

    public void setLatencyMillis(long latencyMillis) {
        this.latencyMillis = Math.min(Math.max(latencyMillis, 0), 30_000);
    }
}
