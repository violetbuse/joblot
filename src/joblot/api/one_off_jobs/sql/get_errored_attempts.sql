SELECT *
FROM errored_attempts
WHERE one_off_job_id = ANY($1::TEXT []);