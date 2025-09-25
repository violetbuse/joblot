-- Modify "errored_attempts" table
ALTER TABLE "errored_attempts" ADD COLUMN "method" text NOT NULL, ADD COLUMN "url" text NOT NULL, ADD COLUMN "req_headers" text[] NOT NULL, ADD COLUMN "req_body" text NOT NULL;
