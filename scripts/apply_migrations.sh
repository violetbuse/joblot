#!/bin/bash

atlas migrate apply \
    --dir "file://migrations" \
    --url "postgres://postgres:postgres@localhost:5432/postgres?sslmode=disable"