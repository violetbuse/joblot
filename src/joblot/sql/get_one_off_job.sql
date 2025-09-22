SELECT *
FROM one_off_jobs
WHERE one_off_jobs.id = $1
    AND one_off_jobs.user_id LIKE $2
    AND one_off_jobs.tenant_id LIKE $3;