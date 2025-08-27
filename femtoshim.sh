#!/bin/bash

export COLOR_RESET="\033[0m"
export MAGENTA_B="\033[1;35m"
export PINK_B="\x1b[1;38;2;235;170;238m"

shim="$1"

rootfs=$(mktemp -d)
tempmount=$(mktemp -d)
rm -rf "$rootfs"
mkdir -p "$rootfs"

dev=$(losetup -Pf --show "$shim")
chromeos=$(cgpt find -l ROOT-A "$dev" | head -n 1)
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
sync
sectors=$(( (size + 511) / 512 ))
start=$(sgdisk -F $dev | awk '{print $1}')
sgdisk -d=3 "$dev"
start=$(sgdisk -i=2 "$dev" | awk '/Last sector/ {print $3}')
start=$((start + 1))
sgdisk -n 3:$start:+${sectors} -c 3:"Femtoshim" "$dev"
for n in $(seq 4 15); do
    sgdisk -d=$n "$dev" >/dev/null 2>&1 || true
done
losetup -d $dev
dev=$(losetup --find --show --partscan corsola.bin)
mkfs.ext4 -F "${dev}p3" -L "Femtoshim" >/dev/null 2>&1

root_bmount=$(mktemp -d)
mount "${dev}p3" "$root_bmount"

cp -a ./init $rootfs/sbin/init
rsync -a --delete "$rootfs/." "$root_bmount" >/dev/null 2>&1 || { echo "failed to copy all files"; exit 1; }
chmod +x "$root_bmount/sbin/init" 2>/dev/null
sync

umount "$root_bmount" -l 2>/dev/null

losetup -D
mv "$shim" "femtoshim-${boardname}.bin" 2>/dev/null
finalshim="femtoshim-${boardname}.bin"

echo -e "${MAGENTA_B}Done! Credits:"
echo -e "${PINK_B}Sophia${COLOR_RESET}: Writing Femtoshim"