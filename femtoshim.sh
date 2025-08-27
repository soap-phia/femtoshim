#!/bin/bash

export COLOR_RESET="\033[0m"
export MAGENTA_B="\033[1;35m"
export PINK_B="\x1b[1;38;2;235;170;238m"

shim="$1"
femtoshim="femtoshim.bin"
truncate -s "200M" "$femtoshim"

rootfs=$(mktemp -d)
tempmount=$(mktemp -d)
rm -rf "$rootfs"
mkdir -p "$rootfs"

crosdev=$(losetup -Pf --show "$shim")
chromeos=$(cgpt find -l ROOT-A "$crosdev" | head -n 1)
mount -o ro "$chromeos" "$tempmount"

export arch=x86_64
if [ -f "$tempmount/bin/bash" ]; then
    case "$(file -b "$temproot/bin/bash" | awk -F ', ' '{print $2}' | tr '[:upper:]' '[:lower:]')" in
        *aarch64* | *armv8* | *arm*) export arch=aarch64 ;;
    esac
fi
if [ -z "$shim" ] || echo "$shim" | grep -vq ".bin"; then
  echo "Please run on a raw shim."
fi

[ ! -f alpine-minirootfs.tar.gz ] && wget -q --show-progress "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/$arch/alpine-minirootfs-3.22.0-$arch.tar.gz" -O alpine-minirootfs.tar.gz 
tar -xf alpine-minirootfs.tar.gz -C "$rootfs"
rm -f "$rootfs/sbin/init" "alpine-minirootfs.tar.gz"
if [ -f "$tempmount/etc/lsb-release" ]; then
  cp -ar "$tempmount/etc/lsb-release" $rootfs/etc/lsb-release
  export boardname=$(cat $tempmount/etc/lsb-release | grep CHROMEOS_RELEASE_BOARD= | awk -F '=' '{print $2}')
else
  echo "Please run on a raw shim."
  exit
fi
umount $tempmount
dev=$(losetup -Pf --show $femtoshim)
sync

sgdisk --zap-all "$dev" >/dev/null 2>&1
sgdisk -n 1:2048:10239 -c 1:"STATE" "$dev" >/dev/null 2>&1
sgdisk -n 2:10240:75775 "$dev" >/dev/null 2>&1
size=$(du -sb $rootfs | awk '{print $1}')
sectors=$(( (size + 4194304 + 511) / 512 ))
sgdisk -n 3:75776:+${sectors} -c 3:"Femtoshim" "$dev" >/dev/null 2>&1
sgdisk -t 3:8300 "$dev" >/dev/null 2>&1
kernelpartition="${dev}p2"
skpart=$(cgpt find -l KERN-A "$crosdev" | head -n 1)
skpartnum="${skpart##*p}"
sgdisk -i "$skpartnum" "$crosdev"
dd if="$skpart" of="$kernelpartition" status=none

sgdisk --partition-guid=2:B5BAF579-07EF-A747-858B-87C0E507CD29 "$dev"
cgpt add -i 2 -t "$(cgpt show -i "$skpartnum" -t "$crosdev")" -l "$(cgpt show -i "$skpartnum" -l "$crosdev")" -P 15 -T 15 -S 1 "$dev" >/dev/null

state="${dev}p1"
root="${dev}p3"

mkfs.ext4 -F "$state" -L "STATE" >/dev/null 2>&1
mkfs.ext4 -F "$root" -L "Femtoshim" >/dev/null 2>&1

statemount=$(mktemp -d)
root_mount=$(mktemp -d)

mount "$state" "$statemount"
mkdir -p "$statemount/dev_image/etc/"
touch "$statemount/dev_image/etc/lsb-factory"

mount "$root" "$root_mount"

cp -a ./init $rootfs/sbin/init
rsync -a --delete "$rootfs/." "$root_mount" >/dev/null 2>&1 || { echo "failed to copy all files"; exit 1; }
chmod +x "$root_mount/sbin/init" 2>/dev/null
sync

umount "$root_mount"
partprobe
sleep 3
e2fsck -fy $root
resize2fs -M $root

losetup -D
end=$(parted -m "$femtoshim" unit B print | tail -n 1 | cut -d: -f3 | sed 's/B//')
end=$((end + 512))
truncate -s "$end" "$femtoshim"
finalshim="femtoshim-${boardname}.bin"
mv "$femtoshim" "$finalshim" 2>/dev/null

echo -e "${MAGENTA_B}Done! Credits:"
echo -e "${PINK_B}Sophia${COLOR_RESET}: Writing Femtoshim"