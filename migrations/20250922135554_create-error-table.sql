-- Create "errored_attempts" table
CREATE TABLE "errored_attempts" (
  "id" text NOT NULL,
  "planned_at" integer NOT NULL,
  "attempted_at" integer NOT NULL,
  "user_id" text NULL,
  "tenant_id" text NULL,
  "one_off_job_id" text NULL,
  "cron_job_id" text NULL,
  "error" text NOT NULL,
  PRIMARY KEY ("id"),
  CONSTRAINT "errored_attempts_cron_job_id_fkey" FOREIGN KEY ("cron_job_id") REFERENCES "cron_jobs" ("id") ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "errored_attempts_one_off_job_id_fkey" FOREIGN KEY ("one_off_job_id") REFERENCES "one_off_jobs" ("id") ON UPDATE CASCADE ON DELETE CASCADE
);
-- Create index "idx_errored_attempts_attempted_at" to table: "errored_attempts"
CREATE INDEX "idx_errored_attempts_attempted_at" ON "errored_attempts" ("attempted_at");
-- Create index "idx_errored_attempts_cron_job_id" to table: "errored_attempts"
CREATE INDEX "idx_errored_attempts_cron_job_id" ON "errored_attempts" ("cron_job_id");
-- Create index "idx_errored_attempts_one_off_job_id" to table: "errored_attempts"
CREATE INDEX "idx_errored_attempts_one_off_job_id" ON "errored_attempts" ("one_off_job_id");
-- Create index "idx_errored_attempts_planned_at" to table: "errored_attempts"
CREATE INDEX "idx_errored_attempts_planned_at" ON "errored_attempts" ("planned_at");
