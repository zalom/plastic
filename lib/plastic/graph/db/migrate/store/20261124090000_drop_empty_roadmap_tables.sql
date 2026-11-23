-- The five roadmap tables came back on stores that a release from before the roadmap removal opened; they hold no row.
-- legacy.db keeps the rows of a table that does hold one, before this runs.
DROP TABLE IF EXISTS work."roadmap_log";
DROP TABLE IF EXISTS work."roadmap_edges";
DROP TABLE IF EXISTS work."roadmap_items";
DROP TABLE IF EXISTS work."batches";
DROP TABLE IF EXISTS work."roadmaps";
