package com.cloudcart.order.error;

/** The request is well-formed but cannot be fulfilled (unknown user, no stock, ...). */
public class InvalidOrderException extends RuntimeException {

    public InvalidOrderException(String message) {
        super(message);
    }
}
