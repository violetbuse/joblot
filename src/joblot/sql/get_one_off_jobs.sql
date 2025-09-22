SELECT *
FROM one_off_jobs
WHERE execute_at >= $1
    AND execute_at <= $2
    AND completed = $3
    AND user_id LIKE $4
    AND tenant_id LIKE $5;