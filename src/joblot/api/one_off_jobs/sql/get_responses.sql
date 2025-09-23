SELECT *
FROM responses
WHERE one_off_job_id = ANY($1::TEXT []);