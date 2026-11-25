-- A roadmap's item order is now needs links between intents; the roadmap tables go.
-- legacy.db keeps the five tables whole before this runs, and the data step of this version writes the links from them.
DROP TABLE IF EXISTS work."roadmap_log";
DROP TABLE IF EXISTS work."roadmap_edges";
DROP TABLE IF EXISTS work."roadmap_items";
DROP TABLE IF EXISTS work."batches";
DROP TABLE IF EXISTS work."roadmaps";
