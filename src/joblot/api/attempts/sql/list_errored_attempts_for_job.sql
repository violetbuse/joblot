SELECT *
FROM errored_attempts
WHERE tenant_id LIKE $1
    AND user_id LIKE $2
    AND (
        one_off_job_id = $3
        OR cron_job_id = $3
    )