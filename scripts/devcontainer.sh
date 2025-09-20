#!/bin/bash

docker run -d \
  --name joblot-pg \
  -e POSTGRES_USER=postgres \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=postgres \
  -p 5432:5432 \
  -v joblot-pg-data:/var/lib/postgresql/data \
  postgres:17