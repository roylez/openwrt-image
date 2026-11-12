#!/bin/sh
# Reflash to the newest release image from github.com/roylez/openwrt-image,
# but only when the release build date (YYYYMMDD in the asset filename) is
# newer than the running image's own build date in /etc/build-date, which
# CI bakes into every image. Reading the image's own date instead of
# persisting a marker means config backups can never make a newer image
# look outdated.
#
# Written for luci-app-commands: every outcome prints one self-describing
# "upgrade-firmware:" line. Exit codes:
# 0  flashed a new image (device reboots), or already up to date
# 1  could not fetch release info from GitHub (curl error printed)
# 2  release assets carry no build date / no digest
# 3  cannot detect target, board, or filesystem on this device
# 4  no unambiguous matching image in the release
# 5  image download failed (curl error printed)
# 6  downloaded image failed sha256 verification

REPO=roylez/openwrt-image
BUILD_DATE_FILE=/etc/build-date
IMG=/tmp/firmware.img.gz

die() {
	echo "upgrade-firmware: FAILED ($1): $2"
	exit $1
}

json=$(curl -sSf 2>&1 "https://api.github.com/repos/$REPO/releases/latest") || {
	die 1 "cannot fetch release info (curl exit $?): $json"
}

DATE=$(printf '%s\n' "$json" |
	grep -o 'openwrt-[0-9.]*-[0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]-' |
	head -n 1 |
	cut -d- -f3)
[ -n "$DATE" ] || die 2 "no build date found in release assets"

RUNNING=$(cat "$BUILD_DATE_FILE" 2>/dev/null || echo 0)
if [ "$DATE" -le "$RUNNING" ]; then
	echo "upgrade-firmware: up to date (installed $RUNNING, latest release $DATE)"
	exit 0
fi

# /proc/mounts is kernel format: "<dev> /rom squashfs ro,... 0 0". ext4
# builds ship an empty /rom directory without any mount, so the mount
# must be checked, not the directory.
if grep -q " /rom squashfs " /proc/mounts; then
	FS=squashfs
else
	FS=ext4
fi

[ -f /etc/openwrt_release ] || die 3 "/etc/openwrt_release missing: cannot detect target"
. /etc/openwrt_release
[ -n "$DISTRIB_TARGET" ] || die 3 "DISTRIB_TARGET unset in /etc/openwrt_release: cannot detect target"
TARGET=$(printf '%s\n' "$DISTRIB_TARGET" | tr / -)

[ -f /tmp/sysinfo/board_name ] || die 3 "/tmp/sysinfo/board_name missing: cannot detect board"
PROFILE=$(tr , _ < /tmp/sysinfo/board_name)

URL=$(printf '%s\n' "$json" |
	grep -o "https://[^\"]*openwrt-[0-9.]*-$DATE-$TARGET-.*$PROFILE-$FS-sysupgrade\.img\.gz")
if [ "$(printf '%s\n' "$URL" | grep -c .)" -ne 1 ]; then
	echo "upgrade-firmware: FAILED (4): no unambiguous $TARGET $PROFILE $FS image for build $DATE."
	echo "upgrade-firmware: release assets:"
	printf '%s\n' "$json" | grep -o '"name": "[^"]*img\.gz"' | cut -d'"' -f4
	exit 4
fi

WANT=$(printf '%s\n' "$json" |
	grep -B6 "browser_download_url.*$(basename "$URL")" |
	grep -o "sha256:[0-9a-f]*" |
	cut -d: -f2)
[ -n "$WANT" ] || die 2 "release info carries no sha256 digest for $(basename "$URL")"

echo "upgrade-firmware: downloading build $DATE for $TARGET $PROFILE ($FS)"
curl -sSfL 2>&1 -o "$IMG" "$URL" || {
	rc=$?
	rm -f "$IMG"
	die 5 "download failed (curl exit $rc)"
}

HAVE=$(sha256sum "$IMG" | cut -d' ' -f1)
[ "$HAVE" = "$WANT" ] || {
	rm -f "$IMG"
	die 6 "sha256 mismatch (expected $WANT, got $HAVE; $IMG deleted)"
}

# After sysupgrade reboots into the new image, that image carries its own
# /etc/build-date, so no marker write is needed here.
echo "upgrade-firmware: image verified, flashing build $DATE; device will reboot"
sysupgrade "$IMG"
