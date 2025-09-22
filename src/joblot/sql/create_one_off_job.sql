INSERT INTO one_off_jobs (
        id,
        hash,
        created_at,
        user_id,
        tenant_id,
        metadata,
        method,
        url,
        headers,
        body,
        execute_at,
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
        $13,
        $14
    )
RETURNING *;