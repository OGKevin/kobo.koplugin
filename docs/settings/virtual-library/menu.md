# Virtual Library Menu Navigation

## Accessing Virtual Library Settings

1. Open KOReader top menu while in File Browser
2. Navigate to Kobo Library

## Menu Hierarchy

```
Kobo Library
├── Enable virtual library [Toggle]
├── Virtual library folder cover [Action]
├── Sync reading state with Kobo [Toggle]
├── Sync settings [Submenu]
│   ├── Enable automatic sync [Toggle]
│   ├── Sync from Kobo [Submenu]
│   │   ├── Sync on startup [Toggle]
│   │   ├── When Kobo is newer [Menu]
│   │   │   ├── Prompt
│   │   │   ├── Silent
│   │   │   └── Never
│   │   └── When Kobo is older [Menu]
│   │       ├── Prompt
│   │       ├── Silent
│   │       └── Never
│   ├── Sync to Kobo [Submenu]
│   │   ├── Sync on book close [Toggle]
│   │   ├── When KOReader is newer [Menu]
│   │   │   ├── Prompt
│   │   │   ├── Silent
│   │   │   └── Never
│   │   └── When KOReader is older [Menu]
│   │       ├── Prompt
│   │       ├── Silent
│   │       └── Never
├── DRM Settings [Submenu]
│   ├── Enable DRM decryption [Toggle]
│   ├── Cache directory [Action]
│   └── Clear decrypted book cache [Action]
└── About Kobo Library [Action]
```

## Menu Item Reference

| Menu Item                    | Type   | Default                    | Function                                                                                      |
| ---------------------------- | ------ | -------------------------- | --------------------------------------------------------------------------------------------- |
| Enable virtual library       | Toggle | On                         | Show/hide the Kobo Library folder in KOReader's file browser                                  |
| Virtual library folder cover | Action | —                          | Select a custom cover image for the virtual library folder (used by ProjectTitle plugin)      |
| Sync reading state with Kobo | Toggle | Off                        | Enable/disable synchronization of reading progress between KOReader and Kobo Nickel           |
| Enable automatic sync        | Toggle | Off                        | Automatically sync when opening the virtual library (once per startup)                        |
| Sync on startup              | Toggle | Off                        | Sync reading state when opening books from the virtual library                                |
| When Kobo is newer           | Menu   | Prompt                     | Action when Kobo has newer reading position: Prompt (ask user), Silent (auto-sync), Never     |
| When Kobo is older           | Menu   | Never                      | Action when Kobo has older reading position: Prompt (ask user), Silent (auto-sync), Never     |
| Sync on book close           | Toggle | On                         | Automatically sync reading state to Kobo when closing a book                                  |
| When KOReader is newer       | Menu   | Silent                     | Action when KOReader has newer reading position: Prompt (ask user), Silent (auto-sync), Never |
| When KOReader is older       | Menu   | Never                      | Action when KOReader has older reading position: Prompt (ask user), Silent (auto-sync), Never |
| Enable DRM decryption        | Toggle | Off                        | Decrypt DRM-protected books from the Kobo Store when opening them                             |
| Cache directory              | Action | `/tmp/kobo.koplugin.cache` | Choose where decrypted book files are temporarily stored                                      |
| Clear decrypted book cache   | Action | —                          | Delete all temporarily stored decrypted book files from the cache directory                   |
| About Kobo Library           | Action | —                          | Display information about the Kobo Library plugin including version and features              |
