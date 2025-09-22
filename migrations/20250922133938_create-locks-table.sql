-- Create "locks" table
CREATE TABLE "locks" (
  "id" text NOT NULL,
  "nonce" text NOT NULL,
  "expires_at" integer NOT NULL,
  PRIMARY KEY ("id")
);
-- Create index "idx_locks_expires_at" to table: "locks"
CREATE INDEX "idx_locks_expires_at" ON "locks" ("expires_at");
-- Create index "idx_locks_nonce" to table: "locks"
CREATE INDEX "idx_locks_nonce" ON "locks" ("nonce");
