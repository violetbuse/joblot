-- Modify "cron_jobs" table
ALTER TABLE "cron_jobs" ADD COLUMN "initial_retry_delay_seconds" integer NOT NULL DEFAULT 30, ADD COLUMN "retry_delay_factor" real NOT NULL DEFAULT 1.5, ADD COLUMN "maximum_retry_delay_seconds" integer NOT NULL DEFAULT 86400;
-- Modify "one_off_jobs" table
ALTER TABLE "one_off_jobs" ADD COLUMN "initial_retry_delay_seconds" integer NOT NULL DEFAULT 30, ADD COLUMN "retry_delay_factor" real NOT NULL DEFAULT 1.5, ADD COLUMN "maximum_retry_delay_seconds" integer NOT NULL DEFAULT 86400;
