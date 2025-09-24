SELECT *
FROM errored_attempts
WHERE cron_job_id = ANY($1::TEXT []);