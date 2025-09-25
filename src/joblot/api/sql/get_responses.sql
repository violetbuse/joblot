SELECT *
FROM responses
WHERE one_off_job_id = ANY($1::TEXT [])
    OR cron_job_id = ANY($1::TEXT [])
ORDER BY attempted_at DESC
LIMIT $2;