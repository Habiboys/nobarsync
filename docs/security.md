# Security

Passwords use bcrypt. The session cookie `nobarsync_session` is HTTP-only and `SameSite=Lax`. The CSRF cookie `nobarsync_csrf` is readable by the app, and mutating requests from a logged-in browser send `x-nobarsync-csrf`. Login, register, and guest creation are the CSRF exceptions.

Authorization is checked on the server for room commands, media reads, uploads, and admin routes. Hidden buttons are not the control.

Playback tokens expire after two hours, are bound to a path prefix, and are checked before any cache or object read. The bucket is private. Do not enable a public `r2.dev` domain.

Rate limits use ETS: 300 API requests per minute per IP, and 20 per minute on register, login, and guest. Chat is stripped of tags and limited to 500 characters. Reactions use an allowlist and a 500 ms socket throttle.

Logs include request and room ids. Do not log session cookies, socket tokens, or playback tokens. The JSON logger has a redact helper for those field names.

URL import blocks private and metadata addresses. There is no yt-dlp and no DRM bypass.

Production refuses to boot without `SECRET_KEY_BASE`, `DATABASE_URL`, `MEDIA_TOKEN_SECRET`, and the S3 settings.
