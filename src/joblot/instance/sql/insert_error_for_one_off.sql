INSERT INTO errored_attempts (
        id,
        planned_at,
        attempted_at,
        user_id,
        tenant_id,
        one_off_job_id,
        method,
        url,
        req_headers,
        req_body,
        error
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
        $11
    );