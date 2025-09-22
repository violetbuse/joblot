SELECT *
FROM errored_attempts
WHERE cron_id in $1;