-- A node keeps an optional deadline: the minutes a claim on it may run before plastic graph ready reports it as overdue.
ALTER TABLE work."nodes" ADD COLUMN "deadline" INTEGER;
