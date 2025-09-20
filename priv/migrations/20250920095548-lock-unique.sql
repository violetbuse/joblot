--- migration:up

ALTER TABLE locks ADD CONSTRAINT locks_id_unique UNIQUE (id, nonce);

--- migration:down

ALTER TABLE locks DROP CONSTRAINT locks_id_unique;

--- migration:end