SELECT *
FROM one_off_jobs
WHERE user_id LIKE $1
    AND tenant_id LIKE $2
    AND id > $3
ORDER BY id ASC
LIMIT $4;