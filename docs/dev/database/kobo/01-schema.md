# Kobo Database Schema

This document describes the Kobo SQLite database schema and the key tables used by the plugin.

## Database Location

The Kobo database is located at:

```
/mnt/onboard/.kobo/KoboReader.sqlite
```

## Key Tables

### Content Table

The primary table containing book and chapter information.

#### Relevant Fields

| Field                 | Type    | Purpose                                        | Example                           |
| --------------------- | ------- | ---------------------------------------------- | --------------------------------- |
| `ContentID`           | TEXT    | Unique identifier (PRIMARY KEY)                | `"0N3773Z7HFPXB"`                 |
| `ContentType`         | INTEGER | 6 = Book entry, 9 = Chapter entry              | `6`                               |
| `BookTitle`           | TEXT    | Book title                                     | `"The Great Gatsby"`              |
| `Attribution`         | TEXT    | Author information                             | `"F. Scott Fitzgerald"`           |
| `___PercentRead`      | INTEGER | Reading progress (0-100)                       | `67`                              |
| `___FileOffset`       | INTEGER | **Cumulative percentage** where chapter starts | `50` (chapter starts at 50%)      |
| `___FileSize`         | INTEGER | **Percentage size** of this chapter            | `10` (chapter is 10% of book)     |
| `DateLastRead`        | TEXT    | Last reading timestamp (ISO 8601)              | `"2024-01-15 14:30:00.000+00:00"` |
| `ReadStatus`          | INTEGER | Reading status code (see below)                | `1`                               |
| `ChapterIDBookmarked` | TEXT    | Current chapter bookmark                       | `"chapter1.html#kobo.1.1"`        |

#### ReadStatus Codes

```lua
0 = Unread/Unopened  -- Book never opened
1 = Reading          -- Currently reading
2 = Finished         -- Book completed
3 = Reading (alt)    -- Alternative reading status
```

#### ContentType Values

```lua
6 = Book entry       -- Main book record
9 = Chapter entry    -- Individual chapter records
```

## Timestamp Format

Kobo uses ISO 8601 format:

```
2024-01-15 14:30:00.000+00:00
```

The plugin converts between Unix timestamps and this format:

```lua
-- Parse Kobo timestamp to Unix timestamp
function parseKoboTimestamp(date_string)
    local year, month, day, hour, min, sec =
        date_string:match("(%d+)-(%d+)-(%d+)[T ](%d+):(%d+):(%d+)")
    return os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(min),
        sec = tonumber(sec),
    })
end

-- Format Unix timestamp to Kobo format
function formatKoboTimestamp(timestamp)
    return os.date("!%Y-%m-%d %H:%M:%S.000+00:00", timestamp)
end
```
