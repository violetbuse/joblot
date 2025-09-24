DELETE FROM cron_jobs
WHERE id = $1
    AND user_id LIKE $2
    AND tenant_id LIKE $3;