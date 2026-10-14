# Locking down the Cloudinary upload preset

Uploads use an **unsigned** Cloudinary preset (`CloudinaryService.uploadPreset`
in `lib/services/cloudinary_service.dart`) so the app can upload directly
without embedding the account's API secret. The tradeoff: the preset name
itself is the only thing authorizing an upload, and it's visible to anyone
who decompiles the APK/web bundle or just inspects the network request. The
app now validates file type/size client-side before uploading (see
`CloudinaryService._upload`), but that's not real enforcement — someone can
call the Cloudinary API directly with that preset name and skip the app
entirely. The dashboard-side restrictions below are the actual enforcement
and can only be set there, not from app code.

## Do this in the Cloudinary dashboard

1. Log in → **Settings → Upload** → find the preset named in
   `uploadPreset` (currently `twp0ykep`).
2. Set **Allowed formats**: `jpg,jpeg,png,webp` for the photo use case,
   `pdf` for resumes, `mp4,mov,m4v` for intro videos. Cloudinary presets
   are per-preset, not per-call — if you want different formats enforced
   per upload type, create **three separate unsigned presets** (photo,
   resume, video) and update `CloudinaryService` to use the matching
   preset name per upload method instead of one shared preset.
3. Set a **Max file size** on the preset matching (or tighter than) the
   app's own limits (5 MB photo / 8 MB resume / 60 MB video).
4. Turn on **Moderation** (e.g. Cloudinary's manual or AI moderation add-on)
   if you want a review queue before an uploaded file is publicly
   servable — optional, but worth it once there's real traffic given
   resumes/photos are user-submitted and unmoderated today.
5. Consider setting **Unique filename** + **Overwrite: false** (usually the
   default) so uploads can't collide with or overwrite another user's file.

## Why not switch to signed uploads instead?

A signed upload (using the API secret) would let you enforce limits
server-side without relying on dashboard config, but the secret can't live
in the Flutter app — it would need a small endpoint on the Node backend in
`backend/` that generates the signature. That's a real (if small) feature,
tracked in `docs/PRODUCTION_ROADMAP.md`, not something to bolt on inside
this pass.
