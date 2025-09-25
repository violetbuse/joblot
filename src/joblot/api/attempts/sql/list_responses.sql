SELECT *
FROM responses
WHERE tenant_id LIKE $1
    AND user_id LIKE $2
    AND id > $3
ORDER BY id ASC
LIMIT $4