-- The setting migrate.drop_document_revisions is retired: no command reads it, so its rows go from every scope.
DELETE FROM "settings" WHERE "key" = 'migrate.drop_document_revisions';
