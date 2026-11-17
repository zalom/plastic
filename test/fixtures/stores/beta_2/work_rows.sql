INSERT INTO intents (id, intent_id, origin_id, slug, title, status, reason, opened_at) VALUES
  (1, '1', 'ORIGIN', 'first', 'First', 'in_progress', NULL, '2026-11-01'),
  (2, '2', 'ORIGIN', 'second', 'Second', 'done', 'shipped', '2026-11-02'),
  (3, '3', 'ORIGIN', 'third', 'Third', 'open', NULL, '2026-11-03');
DELETE FROM intents WHERE id = 3;
INSERT INTO clusters (name, intent_id, origin_id) VALUES ('core', '1', 'ORIGIN');
INSERT INTO nodes (intent_id, id, kind, title, state, "by", retries, updated_at, origin_id) VALUES
  ('1', 'n1', 'build', 'Build', 'claimed', 'agent-1', 1, '2026-11-01T10:00:00Z', 'ORIGIN'),
  ('1', 'n2', 'build', 'Test', 'done', 'agent-2', 0, '2026-11-01T11:00:00Z', 'ORIGIN'),
  ('1', 'n3', 'build', 'Plan', 'ready', NULL, NULL, '2026-11-01T09:00:00Z', 'ORIGIN');
INSERT INTO edges (intent_id, "from", "to", kind, origin_id) VALUES ('1', 'n1', 'n2', 'needs', 'ORIGIN');
INSERT INTO savepoints (intent_id, position, at, text, origin_id, session_id) VALUES
  ('1', 1, '2026-11-01T10:00:00Z', 'first note', 'ORIGIN', 's-1'),
  ('1', 2, '2026-11-01T10:05:00Z', 'second note', 'ORIGIN', 's-2');
INSERT INTO completions (intent_id, origin_id, at, session_id, judge, criteria, evidence, outcome_sha256) VALUES ('2', 'ORIGIN', 't', 's', 'verdict', '{}', '{}', 'h');
INSERT INTO approvals (intent_id, origin_id, at, session_id) VALUES ('1', 'ORIGIN', 't', 's');
INSERT INTO verdicts (intent_id, round, origin_id, verdict, findings) VALUES ('1', 1, 'ORIGIN', 'pass', '[]');
INSERT INTO archives (intent_id, origin_id, at) VALUES ('2', 'ORIGIN', 't');
INSERT INTO archive_entries (intent_id, path, origin_id, kind, mode, mtime, data) VALUES ('2', 'a.md', 'ORIGIN', 'file', 420, 't', x'00ff10');
INSERT INTO printed (path, sha256, at, origin_id) VALUES ('intents/2/outcome.md', 'bb', '2026-11-01', 'ORIGIN'), ('shared.md', 'work-copy', '2026-11-01', 'ORIGIN');
INSERT INTO changes ("table", key, operation, row, at, origin_id) VALUES ('intents', '1', 'put', '{}', '2026-11-01', 'ORIGIN');
INSERT INTO roadmaps (slug, title, origin_id) VALUES ('road', 'Road', 'ORIGIN');
