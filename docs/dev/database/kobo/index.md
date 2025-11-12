# Kobo Database

This section covers the Kobo SQLite database and how the plugin interacts with it.

## Contents

- [Schema](01-schema.md) - Database structure and field definitions
- [Progress Storage](02-progress-storage.md) - How reading progress is calculated and stored
- [Queries](03-queries.md) - SQL queries used by the plugin

## Overview

The Kobo database is a SQLite database located at `/mnt/onboard/.kobo/KoboReader.sqlite`. It
contains all book metadata, reading progress, and user annotations for books purchased from the Kobo
store or synced through Kobo's ecosystem.

The plugin reads from this database to pull reading progress into KOReader, and writes to it to push
KOReader's progress back to Kobo.
