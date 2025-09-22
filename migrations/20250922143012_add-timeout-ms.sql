-- Modify "cron_jobs" table
ALTER TABLE "cron_jobs" ADD COLUMN "timeout_ms" integer NOT NULL DEFAULT 10000;
-- Modify "one_off_jobs" table
ALTER TABLE "one_off_jobs" ADD COLUMN "timeout_ms" integer NOT NULL DEFAULT 10000;
