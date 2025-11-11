# KOReader Data Storage

This section covers how KOReader stores reading progress and metadata.

## Contents

- [DocSettings](01-docsettings.md) - Sidecar file structure and percent calculation
- [ReadHistory](02-readhistory.md) - Timestamp tracking and challenges
- [Data Flow](03-data-flow.md) - How data moves between systems

## Overview

KOReader stores reading progress in "sidecar" files alongside each book. These are Lua table files that contain the reading position, status, and other metadata.

Unlike Kobo's centralized database, KOReader uses a distributed approach where each book has its own metadata file. The plugin reads from these files to push progress to Kobo, and writes to them when pulling progress from Kobo.
