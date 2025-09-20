--- migration:up

CREATE TABLE one_off_jobs (
    id TEXT PRIMARY KEY,
    hash INTEGER NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb, 
    user_id TEXT,
    tenant_id TEXT,
    created_at INTEGER NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW()),

    -- Request data
    method TEXT NOT NULL,
    url TEXT NOT NULL,
    headers TEXT[],
    body TEXT,
    timeout_ms INTEGER NOT NULL,
    execute_at INTEGER NOT NULL,

    -- Response data
    status_code INTEGER,
    response_headers TEXT[],
    response_body TEXT,
    response_time_ms INTEGER,
    executed_at INTEGER,

    -- constraint: response data must either be all  there or not at all
    CONSTRAINT response_data_must_all_be_present CHECK (
        (
            status_code IS NULL AND
            response_headers IS NULL AND
            response_body IS NULL AND
            response_time_ms IS NULL AND
            executed_at IS NULL
        ) OR (
            status_code IS NOT NULL AND
            response_headers IS NOT NULL AND
            response_body IS NOT NULL AND
            response_time_ms IS NOT NULL AND
            executed_at IS NOT NULL
        )
    )
);

CREATE INDEX idx_one_off_jobs_user_id ON one_off_jobs(user_id);
CREATE INDEX idx_one_off_jobs_tenant_id ON one_off_jobs(tenant_id);
CREATE INDEX idx_one_off_jobs_execute_at ON one_off_jobs(execute_at);
CREATE INDEX idx_one_off_jobs_executed_at ON one_off_jobs(executed_at);

CREATE TABLE cron_jobs (
    id TEXT PRIMARY KEY,
    hash INTEGER NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
    user_id TEXT,
    tenant_id TEXT,
    cron TEXT NOT NULL,
    created_at INTEGER NOT NULL DEFAULT EXTRACT(EPOCH FROM NOW()),

    -- Request data
    method TEXT NOT NULL,
    url TEXT NOT NULL,
    headers TEXT[],
    body TEXT,
    timeout_ms INTEGER NOT NULL
);

CREATE INDEX idx_cron_jobs_user_id ON cron_jobs(user_id);
CREATE INDEX idx_cron_jobs_tenant_id ON cron_jobs(tenant_id);
CREATE INDEX idx_cron_jobs_cron ON cron_jobs(cron);

CREATE TABLE cron_executions (
    id TEXT PRIMARY KEY,
    cron_id TEXT REFERENCES cron_jobs(id),

    -- Response data
    status_code INTEGER,
    response_headers TEXT[],
    response_body TEXT,
    response_time_ms INTEGER,
    executed_at INTEGER, 

     -- constraint: response data must either be all  there or not at all
    CONSTRAINT response_data_must_all_be_present CHECK (
        (
            status_code IS NULL AND
            response_headers IS NULL AND
            response_body IS NULL AND
            response_time_ms IS NULL AND
            executed_at IS NULL
        ) OR (
            status_code IS NOT NULL AND
            response_headers IS NOT NULL AND
            response_body IS NOT NULL AND
            response_time_ms IS NOT NULL AND
            executed_at IS NOT NULL
        )
    )
);

CREATE INDEX idx_cron_executions_cron_id ON cron_executions(cron_id);
CREATE INDEX idx_cron_executions_executed_at ON cron_executions(executed_at);

CREATE TABLE locks (
    id TEXT PRIMARY KEY,
    nonce TEXT NOT NULL,
    expires_at INTEGER NOT NULL
);

CREATE INDEX idx_locks_expires_at ON locks(expires_at);
CREATE INDEX idx_locks_nonce ON locks(nonce);

--- migration:down

DROP INDEX idx_locks_expires_at;
DROP INDEX idx_locks_nonce;
DROP TABLE locks;

DROP INDEX idx_cron_executions_cron_id;
DROP INDEX idx_cron_executions_executed_at;
DROP TABLE cron_executions;

DROP INDEX idx_cron_jobs_cron;
DROP INDEX idx_cron_jobs_tenant_id;
DROP INDEX idx_cron_jobs_user_id;
DROP TABLE cron_jobs;

DROP INDEX idx_one_off_jobs_execute_at;
DROP INDEX idx_one_off_jobs_executed_at;
DROP INDEX idx_one_off_jobs_user_id;
DROP INDEX idx_one_off_jobs_tenant_id;
DROP TABLE one_off_jobs;

--- migration:end