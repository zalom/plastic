-- A driver claim keeps the agent that took it: the name PLASTIC_AGENT gave, or none for the session's own agent.
ALTER TABLE work."drivers" ADD COLUMN "agent" TEXT;
