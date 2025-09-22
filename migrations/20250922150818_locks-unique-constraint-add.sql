-- Modify "locks" table
ALTER TABLE "locks" ADD CONSTRAINT "locks_id_nonce_key" UNIQUE ("id", "nonce");
