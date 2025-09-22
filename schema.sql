-- locks table for resource locking by instances
CREATE TABLE locks (
    id TEXT PRIMARY KEY,
    nonce TEXT NOT NULL,
    expires_at INTEGER NOT NULL,
    UNIQUE (id, nonce)
);
CREATE INDEX idx_locks_expires_at ON locks(expires_at);
CREATE INDEX idx_locks_nonce ON locks(nonce);
-- one-off jobs table for one-off jobs
CREATE TABLE one_off_jobs (
    -- admin fields
    id TEXT PRIMARY KEY,
    hash INTEGER NOT NULL,
    created_at INTEGER NOT NULL DEFAULT EXTRACT(
        EPOCH
        FROM NOW()
    ),
    user_id TEXT NOT NULL DEFAULT '',
    tenant_id TEXT NOT NULL DEFAULT '',
    metadata JSONB NOT NULL DEFAULT '{}',
    -- http request fields
    method TEXT NOT NULL,
    url TEXT NOT NULL,
    headers TEXT [] NOT NULL,
    body TEXT NOT NULL,
    -- http execution details
    execute_at INTEGER NOT NULL,
    maximum_attempts INTEGER NOT NULL DEFAULT 1,
    non_2xx_is_failure BOOLEAN NOT NULL DEFAULT TRUE,
    timeout_ms INTEGER NOT NULL DEFAULT 10000,
    completed BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE INDEX idx_one_off_jobs_hash ON one_off_jobs(hash);
CREATE INDEX idx_one_off_jobs_created_at ON one_off_jobs(created_at);
CREATE INDEX idx_one_off_jobs_user_id ON one_off_jobs(user_id);
CREATE INDEX idx_one_off_jobs_tenant_id ON one_off_jobs(tenant_id);
CREATE INDEX idx_one_off_jobs_execute_at ON one_off_jobs(execute_at);
CREATE INDEX idx_one_off_jobs_completed ON one_off_jobs(completed);
-- cron jobs table for cron jobs
CREATE TABLE cron_jobs (
    -- admin fields
    id TEXT PRIMARY KEY,
    hash INTEGER NOT NULL,
    created_at INTEGER NOT NULL DEFAULT EXTRACT(
        EPOCH
        FROM NOW()
    ),
    user_id TEXT NOT NULL DEFAULT '',
    tenant_id TEXT NOT NULL DEFAULT '',
    metadata JSONB NOT NULL DEFAULT '{}',
    -- cron details
    cron TEXT NOT NULL,
    -- http request fields
    method TEXT NOT NULL,
    url TEXT NOT NULL,
    headers TEXT [] NOT NULL,
    body TEXT NOT NULL,
    execute_at INTEGER NOT NULL,
    maximum_attempts INTEGER NOT NULL DEFAULT 1,
    non_2xx_is_failure BOOLEAN NOT NULL DEFAULT TRUE,
    timeout_ms INTEGER NOT NULL DEFAULT 10000
);
CREATE INDEX idx_cron_jobs_hash ON cron_jobs(hash);
CREATE INDEX idx_cron_jobs_created_at ON cron_jobs(created_at);
CREATE INDEX idx_cron_jobs_user_id ON cron_jobs(user_id);
CREATE INDEX idx_cron_jobs_tenant_id ON cron_jobs(tenant_id);
-- responses table for response data
CREATE TABLE responses (
    -- admin fields
    id TEXT NOT NULL,
    planned_at INTEGER NOT NULL,
    attempted_at INTEGER NOT NULL,
    user_id TEXT NOT NULL DEFAULT '',
    tenant_id TEXT NOT NULL DEFAULT '',
    -- one-off job or cron job id
    one_off_job_id TEXT,
    cron_job_id TEXT,
    -- http request fields in case the underlying changes
    method TEXT NOT NULL,
    url TEXT NOT NULL,
    req_headers TEXT [] NOT NULL,
    req_body TEXT NOT NULL,
    -- http response fields
    res_status_code INTEGER NOT NULL,
    res_headers TEXT [] NOT NULL,
    res_body TEXT NOT NULL,
    -- http execution details
    response_time_ms INTEGER NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (one_off_job_id) REFERENCES one_off_jobs(id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (cron_job_id) REFERENCES cron_jobs(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX idx_responses_planned_at ON responses(planned_at);
CREATE INDEX idx_responses_attempted_at ON responses(attempted_at);
CREATE INDEX idx_responses_one_off_job_id ON responses(one_off_job_id);
CREATE INDEX idx_responses_cron_job_id ON responses(cron_job_id);
-- error attempts table for errored attempts
CREATE TABLE errored_attempts (
    id TEXT NOT NULL,
    planned_at INTEGER NOT NULL,
    attempted_at INTEGER NOT NULL,
    user_id TEXT NOT NULL DEFAULT '',
    tenant_id TEXT NOT NULL DEFAULT '',
    -- one-off job or cron job id
    one_off_job_id TEXT,
    cron_job_id TEXT,
    -- error details
    error TEXT NOT NULL,
    PRIMARY KEY (id),
    FOREIGN KEY (one_off_job_id) REFERENCES one_off_jobs(id) ON UPDATE CASCADE ON DELETE CASCADE,
    FOREIGN KEY (cron_job_id) REFERENCES cron_jobs(id) ON UPDATE CASCADE ON DELETE CASCADE
);
CREATE INDEX idx_errored_attempts_planned_at ON errored_attempts(planned_at);
CREATE INDEX idx_errored_attempts_attempted_at ON errored_attempts(attempted_at);
CREATE INDEX idx_errored_attempts_one_off_job_id ON errored_attempts(one_off_job_id);
CREATE INDEX idx_errored_attempts_cron_job_id ON errored_attempts(cron_job_id);