# assets

Drop wallpapers here (`.jpg`, `.jpeg`, `.png`, `.webp`, `.bmp`). They show up
in **edit mode → Settings → Wallpaper**, where you can pick one and choose
Fill / Align / Stretch.

Without an explicit choice, the dashboard uses a file named:

```
wallpaper.jpg
```

It is shown sharp on the boot lock screen and blurred behind the widgets.

You can also set an explicit path in `config/dashboard.json`:

```json
"wallpaper": "assets/my-photo.jpg",
"wallpaperMode": "fill"
```

This directory is device-local content: `deploy/rsync.sh` does not sync or
delete `assets/wallpaper.*`.
