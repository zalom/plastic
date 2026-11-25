-- A ruling no longer replaces another: a decision is rewritten in place under its own number. The data step of this
-- version merges each ruling that replaced another into the decision it replaced, reading the supersedes links, which
-- hold the same pairs as this column. Its down adds the column back empty.
ALTER TABLE main."rulings" DROP COLUMN "supersedes";
