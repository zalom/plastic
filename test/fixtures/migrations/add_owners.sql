ALTER TABLE tickets ADD COLUMN owner TEXT;
UPDATE tickets SET owner = 'ada';
