INSERT INTO sqlar (name, mode, mtime, sz, data, intent_id, sha256, origin_id) VALUES
  ('1/design.png', 420, 100, 3, x'010203', '1', 'sha-design', 'ORIGIN'),
  ('1/spec.pdf', 420, 200, 2, x'ff00', '1', NULL, 'ORIGIN');
INSERT INTO printed (path, sha256, at, origin_id) VALUES ('refs.md', 'dd', '2026-11-01', 'ORIGIN');
INSERT INTO changes ("table", key, operation, row, at, origin_id) VALUES ('sqlar', '1/design.png', 'put', '{}', '2026-11-01', 'ORIGIN');
