#!/bin/bash

atlas migrate diff $1 \
    --dir "file://migrations" \
    --to "file://schema.sql" \
    --dev-url "docker://postgres/17/dev?search_path=public"