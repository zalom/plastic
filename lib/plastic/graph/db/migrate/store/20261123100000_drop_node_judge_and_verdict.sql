-- A node no longer has the columns judge and verdict, which no code read and no store filled.
ALTER TABLE work."nodes" DROP COLUMN "judge";
ALTER TABLE work."nodes" DROP COLUMN "verdict";
