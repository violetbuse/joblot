SELECT *
FROM responses
WHERE cron_job_id = ANY($1::TEXT []);