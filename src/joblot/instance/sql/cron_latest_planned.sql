SELECT COALESCE(
        GREATEST(
            (
                SELECT MAX(planned_at)
                FROM responses
                WHERE cron_job_id = $1
            ),
            (
                SELECT MAX(planned_at)
                FROM errored_attempts
                WHERE cron_job_id = $1
            )
        ),
        0
    ) AS latest_planned_at;