-- Ten tables of older layouts sit in work_graph.db, which the schema no longer declares for it: savepoints, changes,
-- intents, clusters, completions, approvals, verdicts, archives, archive_entries and printed. They hold no row.
-- legacy.db keeps the rows of a table that does hold one, before this runs. Each name is qualified with work, because
-- knowledge_graph.db and plastic.db hold live tables of the same names.
DROP TABLE IF EXISTS work."savepoints";
DROP TABLE IF EXISTS work."changes";
DROP TABLE IF EXISTS work."intents";
DROP TABLE IF EXISTS work."clusters";
DROP TABLE IF EXISTS work."completions";
DROP TABLE IF EXISTS work."approvals";
DROP TABLE IF EXISTS work."verdicts";
DROP TABLE IF EXISTS work."archives";
DROP TABLE IF EXISTS work."archive_entries";
DROP TABLE IF EXISTS work."printed";
