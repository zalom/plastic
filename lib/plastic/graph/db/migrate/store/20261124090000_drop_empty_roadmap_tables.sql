-- The five roadmap tables came back on a store that a checkout from before the schema gate opened; they hold no row.
-- legacy.db keeps the rows of a table that does hold one, before this runs.
DROP TABLE IF EXISTS work."roadmap_log";
DROP TABLE IF EXISTS work."roadmap_edges";
DROP TABLE IF EXISTS work."roadmap_items";
DROP TABLE IF EXISTS work."batches";
DROP TABLE IF EXISTS work."roadmaps";
