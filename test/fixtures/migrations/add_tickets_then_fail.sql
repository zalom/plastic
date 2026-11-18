CREATE TABLE tickets(id INTEGER PRIMARY KEY, title TEXT NOT NULL);
INSERT INTO tickets(title) VALUES ('first');
INSERT INTO tickets(id, title) VALUES (1, 'same id again');
