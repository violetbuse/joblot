SELECT *
FROM responses
WHERE cron_job_id = ANY($1::TEXT [])
    OR one_off_job_id = ANY($2::TEXT []);