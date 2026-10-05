package com.cloudcart.order.error;

public class DownstreamUnavailableException extends RuntimeException {

    private final String dependency;

    public DownstreamUnavailableException(String dependency, Throwable cause) {
        super(dependency + " is unavailable", cause);
        this.dependency = dependency;
    }

    public String getDependency() {
        return dependency;
    }
}
