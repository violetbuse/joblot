SELECT *
FROM cron_jobs
WHERE cron_jobs.id = $1
    AND cron_jobs.user_id LIKE $2
    AND cron_jobs.tenant_id LIKE $3;