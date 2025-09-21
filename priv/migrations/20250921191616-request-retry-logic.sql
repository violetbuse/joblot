--- migration:up

ALTER TABLE one_off_jobs
    ADD COLUMN maximum_retries INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;

CREATE INDEX idx_one_off_jobs_maximum_retries ON one_off_jobs(maximum_retries);
CREATE INDEX idx_one_off_jobs_attempts ON one_off_jobs(attempts);

--- migration:down

DROP INDEX idx_one_off_jobs_maximum_retries;
DROP INDEX idx_one_off_jobs_attempts;

ALTER TABLE one_off_jobs
    DROP COLUMN maximum_retries,
    DROP COLUMN attempts;

--- migration:end