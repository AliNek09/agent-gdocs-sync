# Google Docs API Setup Guide

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

The sync uses your personal Google account credentials via OAuth. No API key or service account is needed.

```bash
# Login with Drive access (required for reading Google Docs)
gcloud auth login --enable-gdrive-access

# Verify authentication works
gcloud auth print-access-token
```

The `--enable-gdrive-access` flag grants read access to your Google Drive files, which is required to fetch Google Docs content via the API.

## Finding Your Google Doc ID

The Doc ID is the long string in the document URL:

```
https://docs.google.com/document/d/1aBcDeFgHiJkLmNoPqRsTuVwXyZ/edit
                                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
                                     This is your DOC_ID
```

Copy this value into your `.gdocs-sync.conf` file.

## API Endpoint

The sync fetches the document using the Google Docs API v1:

```
GET https://docs.googleapis.com/v1/documents/{DOC_ID}?includeTabsContent=true
Authorization: Bearer <access_token>
```

The `includeTabsContent=true` parameter ensures all tab content is included in the response.

## Troubleshooting

### "failed to get access token"

Your gcloud session has expired. Re-authenticate:

```bash
gcloud auth login --enable-gdrive-access
```

### "failed to fetch Google Doc"

- Verify your `DOC_ID` is correct (check the URL)
- Make sure you have at least Viewer access to the document
- Check your internet connection

### "No .gdocs-sync.conf found"

Run the init script or create the config manually:

```bash
bash <path-to-skill>/scripts/init-config.sh
```

### Empty markdown files

The document or tab may have no text content. Images and drawings are not converted — only text, tables, and lists are supported.

### Monospace text appearing as code blocks

Consecutive paragraphs in monospace fonts (Courier New, Consolas, Source Code Pro) are automatically grouped into fenced code blocks. This is by design. If you don't want this, use a non-monospace font in your Google Doc.
