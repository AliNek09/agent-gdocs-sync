# Google Docs API Setup Guide (gdocs-report-push)

## Installing gcloud CLI

### macOS

```bash
brew install --cask google-cloud-sdk
```

### Linux (Debian/Ubuntu)

```bash
curl https://sdk.cloud.google.com | bash
exec -l $SHELL
```

### Windows

Download the installer from https://cloud.google.com/sdk/docs/install

## Authenticating

The push uses your personal Google account credentials via OAuth. No API key or service account is needed.

```bash
# Login with Drive access (required to create and edit Google Docs)
gcloud auth login --enable-gdrive-access

# Verify authentication works
gcloud auth print-access-token
```

The `--enable-gdrive-access` flag grants write access to your Google Drive files, which the skill needs to:

- Look up documents by name (Drive search)
- Create a new document if it doesn't exist yet
- Read existing tab content (to diff against local files)
- Edit tabs via the Google Docs API

## Finding a Google Doc ID

The Doc ID is the long string in the document URL:

```
https://docs.google.com/document/d/1aBcDeFgHiJkLmNoPqRsTuVwXyZ/edit
                                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                     This is the DOC_ID
```

Use this value as `--doc-id` for unambiguous addressing, or as the fourth field (`doc_id`) in a `PUSH_MAPPINGS` entry in `.gdocs-report-push.conf`.

## Finding a Drive Folder ID

The folder ID is the long string in the folder URL after `/folders/`:

```
https://drive.google.com/drive/folders/0AFolderIDHere
                                       ^^^^^^^^^^^^^^
                                       This is the FOLDER_ID
```

Use it as `--folder-id` to scope a name lookup (helpful when multiple docs share the same name), or as the third field (`folder_id`) in a `PUSH_MAPPINGS` entry.

## API Endpoints Used

The push uses the Google Drive v3 and Google Docs v1 APIs:

- `GET  https://www.googleapis.com/drive/v3/files?q=...` — look up the document by name
- `POST https://www.googleapis.com/drive/v3/files` — create a new document when one doesn't exist
- `GET  https://docs.googleapis.com/v1/documents/{DOC_ID}?includeTabsContent=true` — read current tabs
- `POST https://docs.googleapis.com/v1/documents/{DOC_ID}:batchUpdate` — create/update/delete tabs and apply styles

All requests are automatically retried with exponential backoff on `429 Too Many Requests` and `5xx` responses.

## Troubleshooting

### "failed to get access token"

Your gcloud session has expired. Re-authenticate:

```bash
gcloud auth login --enable-gdrive-access
```

### "found N documents named '...'"

Multiple Google Docs share that name. The push refuses to guess — it prints the matching IDs and exits. Disambiguate by passing `--doc-id` directly, or by scoping with `--folder-id`.

### "No .gdocs-report-push.conf found"

You're running in config-driven mode without a config file. Either:

1. Create a config via the wizard:
   ```bash
   bash <path-to-skill>/scripts/init-config.sh
   ```
2. Or use ad-hoc mode, which skips the config entirely:
   ```bash
   bash <path-to-skill>/scripts/push.sh --source-dir docs/api --doc-name "API Docs"
   ```

### Tab exists but content isn't updating

By default, tabs whose content matches local files are skipped. The comparison is a hash of the rendered plain text, so cosmetic markdown changes that produce identical text are intentionally ignored. To rewrite the tab anyway:

```bash
bash <path-to-skill>/scripts/push.sh --force
```

### Old tabs aren't being removed when I delete local files

By default the push is archive-safe: deleting a local file does **not** delete its tab. To enable true sync:

```bash
bash <path-to-skill>/scripts/push.sh --delete-stale
```

### Markdown syntax showing up as literal characters in the doc

That was a bug in earlier versions. The current converter strips `#`, `**`, `*`, `` ` ``, and list markers from the rendered text and applies Google Docs styles on the correct ranges. If you still see raw markdown, make sure the skill is up to date.

### Unsupported markdown features

Tables, images, blockquotes, and deeply nested lists are not converted — they pass through as plain text. Write these in Google Docs directly, or keep them in the local `.md` files and accept that they'll look plain in the doc.
