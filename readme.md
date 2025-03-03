
## OpenWRT image

This contains the files to generate OpenWRT image for personal uses.

Currently images for the following devices are supported:

- [FriendlyARM NanoPi R2S](https://openwrt.org/toh/friendlyarm/nanopi_r2s)

## Usage

- Backup configurations to say, backup.tar.gz
- Download the image and flash it to an SD card

  ```
  # figure out which disk to use (macOS)
  diskutil list

  # umount the disk
  diskutil unmountDisk /dev/disk2 (macOS)

  # dd to the disk (macOS)
  dd if=r2s.img of=/dev/disk2 bs=512
  ```

- Start the router, and connect to JAWS ssid
- resize root partition

  ```
  opkg install losetup resize2fs
  losesetup /dev/sda
  fsck.ext4 -f /dev/sda1
  resize2fs /dev/sda1
  ```

- Restore backup.tar.gz
