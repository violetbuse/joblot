-- Create "cron_jobs" table
CREATE TABLE "cron_jobs" (
  "id" text NOT NULL,
  "hash" integer NOT NULL,
  "created_at" integer NOT NULL DEFAULT EXTRACT(epoch FROM now()),
  "user_id" text NULL,
  "tenant_id" text NULL,
  "metadata" jsonb NOT NULL DEFAULT '{}',
  "cron" text NOT NULL,
  "method" text NOT NULL,
  "url" text NOT NULL,
  "headers" text[] NOT NULL,
  "body" text NOT NULL,
  "execute_at" integer NOT NULL,
  "maximum_attempts" integer NOT NULL DEFAULT 1,
  "non_2xx_is_failure" boolean NOT NULL DEFAULT true,
  PRIMARY KEY ("id")
);
-- Create index "idx_cron_jobs_created_at" to table: "cron_jobs"
CREATE INDEX "idx_cron_jobs_created_at" ON "cron_jobs" ("created_at");
-- Create index "idx_cron_jobs_hash" to table: "cron_jobs"
CREATE INDEX "idx_cron_jobs_hash" ON "cron_jobs" ("hash");
-- Create index "idx_cron_jobs_tenant_id" to table: "cron_jobs"
CREATE INDEX "idx_cron_jobs_tenant_id" ON "cron_jobs" ("tenant_id");
-- Create index "idx_cron_jobs_user_id" to table: "cron_jobs"
CREATE INDEX "idx_cron_jobs_user_id" ON "cron_jobs" ("user_id");
-- Create "one_off_jobs" table
CREATE TABLE "one_off_jobs" (
  "id" text NOT NULL,
  "hash" integer NOT NULL,
  "created_at" integer NOT NULL DEFAULT EXTRACT(epoch FROM now()),
  "user_id" text NULL,
  "tenant_id" text NULL,
  "metadata" jsonb NOT NULL DEFAULT '{}',
  "method" text NOT NULL,
  "url" text NOT NULL,
  "headers" text[] NOT NULL,
  "body" text NOT NULL,
  "execute_at" integer NOT NULL,
  "maximum_attempts" integer NOT NULL DEFAULT 1,
  "non_2xx_is_failure" boolean NOT NULL DEFAULT true,
  "completed" boolean NOT NULL DEFAULT false,
  PRIMARY KEY ("id")
);
-- Create index "idx_one_off_jobs_completed" to table: "one_off_jobs"
CREATE INDEX "idx_one_off_jobs_completed" ON "one_off_jobs" ("completed");
-- Create index "idx_one_off_jobs_created_at" to table: "one_off_jobs"
CREATE INDEX "idx_one_off_jobs_created_at" ON "one_off_jobs" ("created_at");
-- Create index "idx_one_off_jobs_execute_at" to table: "one_off_jobs"
CREATE INDEX "idx_one_off_jobs_execute_at" ON "one_off_jobs" ("execute_at");
-- Create index "idx_one_off_jobs_hash" to table: "one_off_jobs"
CREATE INDEX "idx_one_off_jobs_hash" ON "one_off_jobs" ("hash");
-- Create index "idx_one_off_jobs_tenant_id" to table: "one_off_jobs"
CREATE INDEX "idx_one_off_jobs_tenant_id" ON "one_off_jobs" ("tenant_id");
-- Create index "idx_one_off_jobs_user_id" to table: "one_off_jobs"
CREATE INDEX "idx_one_off_jobs_user_id" ON "one_off_jobs" ("user_id");
-- Create "responses" table
CREATE TABLE "responses" (
  "id" text NOT NULL,
  "planned_at" integer NOT NULL,
  "attempted_at" integer NOT NULL,
  "user_id" text NULL,
  "tenant_id" text NULL,
  "one_off_job_id" text NULL,
  "cron_job_id" text NULL,
  "method" text NOT NULL,
  "url" text NOT NULL,
  "req_headers" text[] NOT NULL,
  "req_body" text NOT NULL,
  "res_status_code" integer NOT NULL,
  "res_headers" text[] NOT NULL,
  "res_body" text NOT NULL,
  "response_time_ms" integer NOT NULL,
  PRIMARY KEY ("id"),
  CONSTRAINT "responses_cron_job_id_fkey" FOREIGN KEY ("cron_job_id") REFERENCES "cron_jobs" ("id") ON UPDATE CASCADE ON DELETE CASCADE,
  CONSTRAINT "responses_one_off_job_id_fkey" FOREIGN KEY ("one_off_job_id") REFERENCES "one_off_jobs" ("id") ON UPDATE CASCADE ON DELETE CASCADE
);
-- Create index "idx_responses_attempted_at" to table: "responses"
CREATE INDEX "idx_responses_attempted_at" ON "responses" ("attempted_at");
-- Create index "idx_responses_cron_job_id" to table: "responses"
CREATE INDEX "idx_responses_cron_job_id" ON "responses" ("cron_job_id");
-- Create index "idx_responses_one_off_job_id" to table: "responses"
CREATE INDEX "idx_responses_one_off_job_id" ON "responses" ("one_off_job_id");
-- Create index "idx_responses_planned_at" to table: "responses"
CREATE INDEX "idx_responses_planned_at" ON "responses" ("planned_at");
