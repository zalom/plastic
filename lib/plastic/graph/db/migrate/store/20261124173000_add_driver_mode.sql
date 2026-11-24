-- A driver claim keeps the mode of the delivery: guided when plastic intent start took it, auto when plastic intent auto took it.
ALTER TABLE work."drivers" ADD COLUMN "mode" TEXT;
