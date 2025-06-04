#!/bin/sh

parted -ls

parted -f -s /dev/mmcblk0 resizepart 2 100%

losetup /dev/loop0 /dev/mmcblk0p2

e2fsck -y -f /dev/loop0

resize2fs /dev/loop0

losetup -d /dev/loop0

echo "DONE"
