-- Creates the table for storing IoT messages
CREATE TABLE IF NOT EXISTS messages (
    id SERIAL PRIMARY KEY,
    payload TEXT,
    received_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
