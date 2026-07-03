# Bug: WebDAV MKCOL on an existing Host/Site folder returns 500 instead of 405

> **Scope: this only affects the Host/Site root folder itself** (e.g.
> `default/`), not regular subfolders. `MKCOL` on any existing subfolder
> under a Host (e.g. `default/templates/`) works fine. As long as content
> is never placed directly at the Host root — always at least one
> subfolder deep — this bug never triggers. See "Evidence" below for the
> tests that isolate this to the Host folder specifically.

## What is MKCOL

`MKCOL` ("**M**a**k**e **Col**lection") is an HTTP method defined by the
WebDAV protocol (RFC 4918), in addition to the standard HTTP methods
(GET, PUT, DELETE, etc). It's the WebDAV equivalent of `mkdir` — it tells
the server "create a folder (collection) at this path". rclone sends this
automatically before every file upload, to make sure the destination
folder exists.

## Summary
dotCMS's WebDAV endpoint returns `500 Internal Server Error` when a client
issues `MKCOL` against the **Host/Site folder itself** (e.g. `default/`)
when it already exists. Per RFC 4918 (WebDAV) and standard client
behavior, this should return `405 Method Not Allowed` (or `423 Locked`).

Regular, non-Host subfolders are **not** affected — `MKCOL` on an existing
regular folder (e.g. `default/templates/`) is handled correctly and
returns no error. The bug is specific to the top-level Host/Site
collection, most likely because a Host is a distinct object type in
dotCMS's content model rather than a plain WebDAV folder, and the MKCOL
handler doesn't special-case "Host already exists" the way it does for
ordinary folders.

Because of this, any WebDAV client that defensively ensures the parent
directory exists before uploading a file (a common, recommended pattern —
e.g. rclone does this automatically before every `PUT`) will fail **only
when uploading directly into the Host root** (e.g. `default/file.vtl`),
gets a `500` back — a generic server-error status that clients correctly
treat as retryable — causing repeated retries and ultimately a failed
upload. Uploading into any subfolder under the Host works fine.

## Environment
- Server: `pro-serv-rclone-deploy-sandbox.dotcms.dev`
- Endpoint under test: `https://pro-serv-rclone-deploy-sandbox.dotcms.dev/webdav/live/1/`
- Client: rclone v1.73.0 and v1.74.3 (both affected identically); also
  reproduced with a raw `curl` request (see below), so this is not
  client-specific.

## Steps to reproduce

1. Confirm the Host folder already exists:
   ```
   $ curl -u <user>:<pass> -X PROPFIND \
       https://pro-serv-rclone-deploy-sandbox.dotcms.dev/webdav/live/1/default/ \
       -H "Depth: 0"
   → 207 Multi-Status (folder exists)
   ```
2. Issue `MKCOL` against that same, already-existing Host folder:
   ```
   $ curl -u <user>:<pass> -X MKCOL \
       https://pro-serv-rclone-deploy-sandbox.dotcms.dev/webdav/live/1/default/
   ```

## Actual result
```
HTTP/2.0 500 Internal Server Error
```
(raw rclone debug log)
```
2026/07/02 18:30:54 DEBUG : HTTP REQUEST (req 0x14000523040)
2026/07/02 18:30:54 DEBUG : MKCOL /webdav/live/1/default/ HTTP/1.1
Host: pro-serv-rclone-deploy-sandbox.dotcms.dev
...
2026/07/02 18:30:54 DEBUG : HTTP RESPONSE (req 0x14000523040)
2026/07/02 18:30:54 DEBUG : HTTP/2.0 500 Internal Server Error
Connection: close
...
```

## Expected result
```
HTTP/1.1 405 Method Not Allowed
```
per RFC 4918 §9.3.1: *"405 (Method Not Allowed) - MKCOL can only be
executed on an unmapped URL."* Servers commonly return 405 (or 423 Locked
if a create is already in progress) for this case; rclone's WebDAV client
explicitly checks for `405`, `406`, or `423` to treat the "already exists"
case as success and proceed with the upload.

## Evidence this is isolated to "MKCOL on the existing Host folder"
- `MKCOL` on a **new**, not-yet-existing collection (Host or regular
  folder) works correctly and instantly (`201 Created`, confirmed via
  `rclone mkdir`).
- `MKCOL` on an **existing regular subfolder** (e.g.
  `default/some-existing-folder/`) works correctly with **no error** —
  confirmed by repeatedly re-running `rclone copy`/`mkdir` against the
  same, already-created subfolder.
- `MKCOL` on the **existing Host folder** (`default/`) reliably returns
  `500`, confirmed on repeated, isolated attempts.
- A raw `PUT` of a file directly (no preceding `MKCOL`) into the existing
  `default/` folder succeeds immediately with `201 Created`:
  ```
  > PUT /webdav/live/1/default/dummy-curl-test.vtl HTTP/2
  ...
  < HTTP/2 201
  ```
- So "create a new folder", "MKCOL an existing regular folder", and
  "write a file into an existing folder" all work fine. The only broken
  case is "MKCOL the Host/Site folder itself when it already exists".

## Impact
Any WebDAV client that follows the common, recommended pattern of
verifying/creating the parent directory before an upload (rclone does this
unconditionally before every file write) will fail **only** when uploading
files directly at the Host root (e.g. `default/page.vtl`). Uploading into
any real subfolder (e.g. `default/templates/page.vtl`) — which is how
content is normally organized in a dotCMS site anyway — is unaffected.

**Workaround in use**: keep all synced content under a real subfolder
beneath the Host (never place files loose at the Host root). With that
constraint, `rclone sync`/`copy` works correctly and this bug is avoided
entirely without any client-side changes.

## Suggested fix
Update the WebDAV `MKCOL` handler to return `405 Method Not Allowed` (or
`423 Locked`) when the target is an existing Host/Site folder, matching
the behavior already correctly implemented for ordinary existing folders.

## Automated check in this repo
`scripts/check-content-structure.sh` scans the local content tree and
fails (with a clear message pointing back to this doc) if any file sits
directly at a Host root. It runs:
- inside `scripts/deploy-dev.sh`, before every sync to Dev
- in `.github/workflows/pr-checks.yml`, on every PR targeting `main`

This is a general-purpose content-structure checker — add other structural
validations to it as they come up, not just this one.
