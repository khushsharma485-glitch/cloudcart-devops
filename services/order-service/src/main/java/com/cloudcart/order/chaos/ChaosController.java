package com.cloudcart.order.chaos;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Fault injection used by the incident runbooks in docs/incidents.
 *
 * Only registered when CHAOS_ENABLED=true. It is disabled by default and
 * the production Helm values never enable it. The Ingress does not route
 * /internal/**, so it is reachable only via kubectl port-forward.
 */
@RestController
@RequestMapping("/internal/chaos")
@ConditionalOnProperty(name = "chaos.enabled", havingValue = "true")
public class ChaosController {

    private static final Logger log = LoggerFactory.getLogger(ChaosController.class);
    private static final int MAX_SECONDS = 600;
    private static final int MAX_MEGABYTES = 1024;

    private final ChaosState state;
    private final List<byte[]> retained = new ArrayList<>();
    private final ExecutorService burners = Executors.newCachedThreadPool();

    public ChaosController(ChaosState state) {
        this.state = state;
    }

    @PostMapping("/cpu")
    public Map<String, Object> burnCpu(@RequestParam(defaultValue = "60") int seconds,
                                       @RequestParam(defaultValue = "2") int threads) {
        int duration = Math.min(Math.max(seconds, 1), MAX_SECONDS);
        int workers = Math.min(Math.max(threads, 1), 8);
        long deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(duration);
        for (int i = 0; i < workers; i++) {
            burners.submit(() -> {
                double sink = 0;
                while (System.nanoTime() < deadline) {
                    sink += Math.sqrt(sink + 1);
                }
                return sink;
            });
        }
        log.warn("CHAOS cpu burn started seconds={} threads={}", duration, workers);
        return Map.of("cpuBurnSeconds", duration, "threads", workers);
    }

    @PostMapping("/memory")
    public synchronized Map<String, Object> allocate(@RequestParam(defaultValue = "100") int megabytes) {
        int mb = Math.min(Math.max(megabytes, 1), MAX_MEGABYTES);
        for (int i = 0; i < mb; i++) {
            retained.add(new byte[1024 * 1024]);
        }
        log.warn("CHAOS memory retained totalMb={}", retained.size());
        return Map.of("retainedMegabytes", retained.size());
    }

    @PostMapping("/errors")
    public Map<String, Object> errors(@RequestParam double rate) {
        state.setErrorRate(rate);
        log.warn("CHAOS error injection rate={}", state.getErrorRate());
        return Map.of("errorRate", state.getErrorRate());
    }

    @PostMapping("/latency")
    public Map<String, Object> latency(@RequestParam long millis) {
        state.setLatencyMillis(millis);
        log.warn("CHAOS latency injection millis={}", state.getLatencyMillis());
        return Map.of("latencyMillis", state.getLatencyMillis());
    }

    @GetMapping
    public Map<String, Object> status() {
        return Map.of("errorRate", state.getErrorRate(),
                "latencyMillis", state.getLatencyMillis(),
                "retainedMegabytes", retained.size());
    }

    @DeleteMapping
    public synchronized Map<String, Object> reset() {
        state.setErrorRate(0);
        state.setLatencyMillis(0);
        retained.clear();
        log.warn("CHAOS reset");
        return status();
    }
}
