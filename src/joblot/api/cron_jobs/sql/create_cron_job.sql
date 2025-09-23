INSERT INTO cron_jobs (
        id,
        hash,
        user_id,
        tenant_id,
        metadata,
        cron,
        method,
        url,
        headers,
        body,
        maximum_attempts,
        non_2xx_is_failure,
        timeout_ms
    )
VALUES (
        $1,
        $2,
        $3,
        $4,
        $5,
        $6,
        $7,
        $8,
        $9,
        $10,
        $11,
        $12,
        $13
    )
RETURNING *;