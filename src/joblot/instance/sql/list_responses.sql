SELECT *
FROM responses
WHERE planned_at = $1
    AND (
        one_off_job_id = $2
        OR cron_job_id = $2
    )
ORDER BY attempted_at ASC;