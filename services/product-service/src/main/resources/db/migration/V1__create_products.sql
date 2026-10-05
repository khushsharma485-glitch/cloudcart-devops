CREATE TABLE products (
    id          BIGSERIAL      PRIMARY KEY,
    name        VARCHAR(150)   NOT NULL,
    description VARCHAR(1000),
    price       NUMERIC(12, 2) NOT NULL CHECK (price >= 0),
    stock       INTEGER        NOT NULL CHECK (stock >= 0),
    created_at  TIMESTAMPTZ    NOT NULL,
    updated_at  TIMESTAMPTZ    NOT NULL
);
