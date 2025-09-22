-- Modify "cron_jobs" table
ALTER TABLE "cron_jobs" ALTER COLUMN "user_id" SET NOT NULL, ALTER COLUMN "user_id" SET DEFAULT '', ALTER COLUMN "tenant_id" SET NOT NULL, ALTER COLUMN "tenant_id" SET DEFAULT '';
-- Modify "errored_attempts" table
ALTER TABLE "errored_attempts" ALTER COLUMN "user_id" SET NOT NULL, ALTER COLUMN "user_id" SET DEFAULT '', ALTER COLUMN "tenant_id" SET NOT NULL, ALTER COLUMN "tenant_id" SET DEFAULT '';
-- Modify "one_off_jobs" table
ALTER TABLE "one_off_jobs" ALTER COLUMN "user_id" SET NOT NULL, ALTER COLUMN "user_id" SET DEFAULT '', ALTER COLUMN "tenant_id" SET NOT NULL, ALTER COLUMN "tenant_id" SET DEFAULT '';
-- Modify "responses" table
ALTER TABLE "responses" ALTER COLUMN "user_id" SET NOT NULL, ALTER COLUMN "user_id" SET DEFAULT '', ALTER COLUMN "tenant_id" SET NOT NULL, ALTER COLUMN "tenant_id" SET DEFAULT '';
