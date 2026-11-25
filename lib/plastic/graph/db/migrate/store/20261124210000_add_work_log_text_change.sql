-- An amended line of a change to the text inside a file keeps the exact old text and the new text.
ALTER TABLE work."work_log" ADD COLUMN "old_text" TEXT;
ALTER TABLE work."work_log" ADD COLUMN "new_text" TEXT;
