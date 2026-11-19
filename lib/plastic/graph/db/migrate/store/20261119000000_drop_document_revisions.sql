-- The documents table holds the current text of each document, and document_heads its hash.
-- No reader names document_revisions any more, so the copies of earlier texts go.
DROP TABLE IF EXISTS main.document_revisions;
