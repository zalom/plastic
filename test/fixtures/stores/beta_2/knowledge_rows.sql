INSERT INTO documents (intent_id, path, body, updated_at, origin_id) VALUES ('1', 'plan.md', 'storage redesign notes
', '2026-11-01', 'ORIGIN');
INSERT INTO document_revisions (sha256, intent_id, path, body, created_at, origin_id) VALUES ('24c786c76abd2784095722fae31885a9ea8e8a64c6063ba022b9e98ca241360a', '1', 'plan.md', 'storage redesign notes
', '2026-11-01', 'ORIGIN');
INSERT INTO document_passages (sha256, intent_id, path, position, body, line_start, line_end, origin_id) VALUES ('24c786c76abd2784095722fae31885a9ea8e8a64c6063ba022b9e98ca241360a', '1', 'plan.md', 0, 'storage redesign notes', 1, 1, 'ORIGIN');
INSERT INTO document_heads (intent_id, path, sha256, updated_at, origin_id) VALUES ('1', 'plan.md', '24c786c76abd2784095722fae31885a9ea8e8a64c6063ba022b9e98ca241360a', '2026-11-01', 'ORIGIN');
INSERT INTO rulings (intent_id, id, text, origin_id) VALUES ('1', 'r1', 'keep it simple', 'ORIGIN');
INSERT INTO printed (path, sha256, at, origin_id) VALUES ('shared.md', 'knowledge-copy', '2026-11-01', 'ORIGIN'), ('intents/1/plan.md', 'aa', '2026-11-01', 'ORIGIN');
INSERT INTO changes ("table", key, operation, row, at, origin_id) VALUES ('documents', '1', 'put', '{}', '2026-11-01', 'ORIGIN');
