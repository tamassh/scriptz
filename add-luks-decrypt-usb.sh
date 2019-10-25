#!/bin/bash

#
# Simple script to allow USB or passphrase under LUKs
#
# richc@graphcore.ai - 4/04/2019

# Uncomment to enable debugging
#set -x

# Usage:
#: -d <device>
#: -p <passphrase>
#: -r revert
#: -d dry-run
#: -a apply

# Useful variables
_options="d:p:arthv"
_echo="/bin/echo -e"
_backup_loc="/root/.luks-usb_pass"
_backup_files="/etc/crypttab /usr/share/initramfs-tools/scripts/local-top/cryptroot"

# DEFAULTS
_usb_drive=""
_passphrase=""
_apply=1
_revert=0
_dryrun=""
_verbose=0

# Functions
printOptions(){

	$_echo "Usage:"
	$_echo "\t-d <path to USB>      : (Mandatory) Define which device to install decryption key onto"
        $_echo "\t-p <passphrase>   	: Existing LUKs decryption passphrase"
        $_echo "\t-a 			: Apply changes, ie: configure host just to prompt for passphrase or use USB key"
        $_echo "\t-r 			: Revert changes, ie: configure host just to prompt for passphrase"
        $_echo "\t-t 			: Dry run of operations"
        $_echo "\t-v 			: Run in verbose/debug mode"
        $_echo "\t-h 			: Print this message"

}

yesno() {

  while true; do
	  read -p "Please confirm (y/n)?: " yn
    case $yn in
        [Yy]* ) 
          return 0
	;;
        [Nn]* )
	  return 1
	;;
        * )
	  ${_echo} "Please answer (y)es or (n)o."
	;;
    esac
  done

}

backupFile() {

  [ $# -ne 2 ]  && return 1
  [[ ! -f $1 ]] && return 1
  [[ ! -d $2 ]] && mkdir -m 0700 

  ${_echo} "Backing up $1"
  ${_dryrun} cp -f $1 $2/$(basename $1) && return 0

  return 1

}

checkDrive() {

  # defaults
  local _disk="null"
  local _removable=0

  [ $# -ne 1 ] && return 1

  ${_echo} "Verifying $1 is a USB"

  # Figure out where the actual disk is, and the kernel agrees
  if [[ -h $1 ]]; then
     _disk="$(basename $(readlink $1))" 
  else
     _disk="$(basename $1)"
  fi
  [[ ! -d /sys/block/${_disk} ]] && return 1

  # Check its removable
  [[ -f /sys/block/${_disk}/removable ]] && _removable=$(cat /sys/block/${_disk}/removable)
  [[ "${_removable}" ]] && return 0 || return 1

}

idDrive(){

  local _disk="null"

  [ $# -ne 1 ] && return 1

  # Figure out where the actual disk is, and the kernel agrees
  if [[ -h $1 ]]; then
     _disk="$(basename $(readlink $1))"
  else
     _disk="$(basename $1)"
  fi

  local _drive_info="$(lshw -short -C disk -quiet | grep ${_disk} | awk '{$1=$2=$3=""; print $0}')"
  ${_echo} "USB: $1 : Drive Info: ${_drive_info}"

}

checkLuksPass() {

  [ $# -ne 2 ]  && return 1
  [[ ! -b $2 ]] && return 1

  ${_echo} "verifying passphrase ... \c"

  # Check we can open the LUKs volume $2 using pass $1
  echo $1 | sudo cryptsetup luksOpen --test-passphrase $2 || return 1

  ${_echo} "ok"

  return 0

}

addLuksKey() {

  [ $# -ne 1 ]  && return 1
  [[ ! -f $1 ]] && return 1

  local _rootdisk="/dev/disk/by-uuid/$(grep -v '#' /etc/crypttab | awk '{print substr($2,6); exit}')"

  ${_echo} Adding USB key to LUKs
 
  # Empty slot 7 for our use
  ${_dryrun} ${_echo} $_passphrase | cryptsetup luksKillSlot $_rootdisk 7 2>/dev/null

  # Add the key
  ${_dryrun} ${_echo} $_passphrase | cryptsetup luksAddKey $_rootdisk ${1} 7 || return 1

  return 0

}

applyPatch() {

  [ $# -ne 2 ]  && return 1
  [[ ! -f $2 ]] && return 1
  patch -b --dry-run $1 < $2 2>/dev/null >/dev/null || return 1
  ${_dryrun} patch -b $1 < $2 && return 0 || return 1

}

rollbackPatch() {

  [ $# -ne 2 ]  && return 1
  [[ ! -f $2 ]] && return 1
  patch -R --dry-run $1 < $2 2>/dev/null >/dev/null || return 1
  ${_dryrun} patch -R $1 < $2 && return 0 || return 1

}

createCryptrootPatch() {

  cat << 'EOF' > ${_backup_loc}/cryptroot.patch
--- /usr/share/initramfs-tools/scripts/local-top/cryptroot	2019-04-04 14:44:56.215908193 +0100
+++ working/cryptroot	2019-04-04 10:33:34.642026736 +0100
@@ -26,6 +26,9 @@
 # source for log_*_msg() functions, see LP: #272301
 . /scripts/functions
 
+# define askpass
+askpass="/lib/cryptsetup/askpass"
+
 #
 # Helper functions
 #
@@ -77,6 +80,7 @@
 	cryptveracrypt=""
 	cryptrootdev=""
 	cryptdiscard=""
+        cryptaskpassfallback="yes"
 	CRYPTTAB_OPTIONS=""
 
 	local IFS=" ,"
@@ -152,6 +156,9 @@
 		discard)
 			cryptdiscard="yes"
 			;;
+		askpassfallback)
+			cryptaskpassfallback="yes"
+			;;
 		esac
 		PARAM="${x%=*}"
 		if [ "$PARAM" = "$x" ]; then
@@ -195,6 +202,10 @@
 	fi
 
 	parse_options "$opts" || return 1
+	# disable cryptkeyscript - fall back to askpass.
+	if [ -n "$do_fallback" ]; then
+		cryptkeyscript=""
+	fi
 
 	if [ -z "$cryptkeyscript" ]; then
 		if [ ${cryptsource#/dev/disk/by-uuid/} != $cryptsource ]; then
@@ -203,7 +214,7 @@
 		else
 			diskname="$cryptsource ($crypttarget)"
 		fi
-		cryptkeyscript="/lib/cryptsetup/askpass"
+		cryptkeyscript=$askpass
 		cryptkey="Please unlock disk $diskname: "
 	elif ! type "$cryptkeyscript" >/dev/null; then
 		message "cryptsetup ($crypttarget): error - script \"$cryptkeyscript\" missing"
@@ -324,7 +335,17 @@
 			if ! crypttarget="$crypttarget" cryptsource="$cryptsource" \
 			     $cryptkeyscript "$cryptkey" | $cryptopen; then
 				message "cryptsetup ($crypttarget): cryptsetup failed, bad password or options?"
-				continue
+				
+				# if not askpass, fall back to askpass on fail.
+				if [ -z "$cryptaskpassfallback" ]; then
+					continue
+				elif [ "$cryptkeyscript" = "$askpass" ]; then
+					continue
+				else
+					export do_fallback="$cryptaskpassfallback"
+					setup_mapping "$1"
+					return
+				fi
 			fi
 		fi
 
EOF

  return 0

}


createCryptab(){

  local decrypt_key=/dev/disk/by-label/key:/.keys/crypt0.key:5
  local luks_options=luks,initramfs,keyscript=/lib/cryptsetup/scripts/passdev,askpassfallback,tries=3
  local _cryptdisk="$(grep -v '#' /etc/crypttab | awk '{print $1 " " $2; exit}')"

  new_line="$_cryptdisk $decrypt_key $luks_options"
  
  ${_echo} Updating crypttab

  # Start building our patch file
  grep -v "^${_cryptdisk}" /etc/crypttab > /tmp/crypttab
  ${_dryrun} ${_echo} "$_cryptdisk $decrypt_key $luks_options" >> /tmp/crypttab

  diff -u /etc/crypttab /tmp/crypttab > ${_backup_loc}/crypttab.patch 

  applyPatch /etc/crypttab ${_backup_loc}/crypttab.patch && return 0

  return 1

}

revertCryptab(){

  [[ ! -f ${_backup_loc}/crypttab.patch ]] && exit 1

  ${_echo} Reverting crypttab

  rollbackPatch /etc/crypttab ${_backup_loc}/crypttab.patch && return 0

  return 1

}

createCryptroot(){

  createCryptrootPatch

  if !  grep -q cryptaskpassfallback /usr/share/initramfs-tools/scripts/local-top/cryptroot; then
    applyPatch /usr/share/initramfs-tools/scripts/local-top/cryptroot ${_backup_loc}/cryptroot.patch && return 0
  else
    return 0
  fi

  return 1

}

revertCryptroot(){

  [[ ! -f ${_backup_loc}/cryptroot.patch ]] && exit 1

  rollbackPatch /usr/share/initramfs-tools/scripts/local-top/cryptroot ${_backup_loc}/cryptroot.patch && return 0

  return 1


}

createLegacyGrub(){

    [ $# -ne 1 ]  && return 1

    [[ ! -f ${_backup_loc}/initrd.img-$(uname -r) ]] && cp /boot//initrd.img-$(uname -r) ${_backup_loc}/initrd.img-$(uname -r)
    [[ -f ${_backup_loc}/initrd.img-$(uname -r) ]] && cp -f ${_backup_loc}/initrd.img-$(uname -r) /boot/initrd.img-$(uname -r).legacy

    local rootdisk_uuid=$(grep -v '#' /etc/crypttab | awk '{print substr($2,6); exit}')
    local rootdisk_lv=$(ls /dev/mapper/*root | head -n1)

    ${_echo} Adding option to grub menu to boot legacy image.

    cat << EOF > $1
#!/bin/sh
exec tail -n +3 \$0
# This file provides an easy way to add custom menu entries.  Simply type the
# menu entries you want to add after this comment.  Be careful not to change
# the 'exec tail' line above.

menuentry 'Graphcore Legacy LUKs passphrase (recovery)' {
        recordfail
        load_video
        gfxmode $linux_gfx_mode
        insmod gzio
        if [ x$grub_platform = xxen ]; then insmod xzio; insmod lzopio; fi
        insmod part_msdos
        insmod ext2
        if [ x$feature_platform_search_hint = xy ]; then
          search --no-floppy --fs-uuid --set=root ${rootdisk_uuid}
        else
          search --no-floppy --fs-uuid --set=root ${rootdisk_uuid}
        fi
	linux   /vmlinuz-$(uname -r) root=${rootdisk_lv} ro  quiet nosplash modeset=i915
	initrd  /initrd.img-$(uname -r).legacy
}
EOF

  [[ -f $1 ]] && ${_dryrun} chmod 0555 $1 
  
  ${_dryrun} update-initramfs -u -k $(uname -r ) && ${_dryrun} update-grub 

  return 0

}

revertLegacyGrub(){

  [ $# -ne 1 ]  && return 1

  ${_echo} Removing option in grub menu to boot legacy image.

  [[ -f $1 ]] && ${_dryrun} rm ${1} 
  
  ${_dryrun} update-initramfs -u -k $(uname -r ) && ${_dryrun} update-grub 

  return 0

}

createUSBStick(){

  [ $# -ne 1 ]  && return 1

  $_echo "Creating decrypt USB stick, this operation will wipe the device"
  idDrive $1
  $_echo "Is this the correct drive and do you wish to continue?"
  yesno || return 1

  if [[ -b $1 ]]; then
     ${_dryrun} umount $1 2>/dev/null || true
     ${_dryrun} mkfs -F -t ext4 -L key $1 >/dev/null || return 1
  fi

  [[ ! -d /mnt/usb ]] && mkdir -m 0700 /mnt/usb
  ${_dryrun} mount $1 /mnt/usb 2>/dev/null
  [[ ! -d /mnt/usb/.keys ]] && ${_dryrun} mkdir -m 0700 /mnt/usb/.keys  
  ${_dryrun} dd if=/dev/urandom of=/mnt/usb/.keys/crypt0.key bs=1 count=512 >/dev/null 2>/dev/null || return 1
  ${_dryrun} chmod 0400 /mnt/usb/.keys/crypt0.key
  addLuksKey /mnt/usb/.keys/crypt0.key                                     || return 1

  return 0


}

# Start

# Simple preflight checks
[ $# -eq 0 ] && printOptions && exit 1
[[ "$(whoami)" != "root" ]] && $_echo "Error, $0 needs to be ran as root!, exiting." && exit 1
[[ ! -d ${_backup_loc} ]] && mkdir -m 0700 ${_backup_loc}

# Process options
while getopts "${_options}" OPTION; do
        case $OPTION in
                d)
                       _usb_drive=${OPTARG}
                        ;;
                p)
                       _passphrase=${OPTARG}
                        ;;
		a)
			_apply=1
			_revert=0
			;;
		r)
			_revert=1
			_apply=0
			;;
		t)
			_dryrun="${_echo} 'DRYRUN: Would execute: '"

			;;
		v)
			_verbose=1
			set -x
			;;
                h)
			printOptions
                        exit 0
                        ;;

        esac
done

# Check if we have manadatory options
[[ "${_usb_drive}" == "" ]] && ${_echo} "Error, -d option is mandatory!" && printOptions && exit 1

$_echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"
$_echo "+ Graphcore.ai : Enabling LUKs USB or Passphrase   +"
$_echo "+                decryption of root disk           +"
$_echo "++++++++++++++++++++++++++++++++++++++++++++++++++++"

if ! checkDrive ${_usb_drive}; then
	if (( ${_apply} )); then
    ${_echo} "Error, drive $(${_usb_drive}) is not removable!\nAborting."
    exit 1
  fi
fi

if [[ "${_passphrase}" == "" ]]; then
  ${_echo} "LUKs passphrase is required, please enter below"
  read -s -p "Password: " _passphrase
fi

if ! checkLuksPass ${_passphrase} /dev/disk/by-uuid/$(grep -v '#' /etc/crypttab | awk '{print substr($2,6); exit}'); then
  exit 1
fi

# Looks like we have a USB and a working passphrase, so let get on with it
for file in ${_backup_files}; do
  if ! backupFile $file $_backup_loc; then
    echo "Error backing up file: ${file}!\nAborting!"
    exit 1
  fi
done

# Figure out what we are doing
if (( ${_apply} )); then  
  ${_echo} 
  ${_echo} "Attempting to convert system"

  # First check if we appear to have the option we need in cryptroot, if we have exit.
  for file in ${_backup_files}; do
    if grep -q askpassfallback ${file} > /dev/null; then
      ${_echo} Update already applied!
      ${_echo} Exiting
      exit 0
    fi
  done 

  # Lets create the USB
  if ! createUSBStick ${_usb_drive}; then
    echo "Error, creating USB stick.\nAborting !"
    exit 1
  fi

  # Update crypttab and grub
  if ! createCryptab; then
    echo "Error, updating cryptab! reverting!"
    [[ -f ${_backup_loc}/crypttab ]] && cp -f  ${_backup_loc}/crypttab /etc/crypttab
    exit 1
  fi

  if ! createCryptroot; then
    echo "Error, updating cryptroot! reverting!"
    [[ -f ${_backup_loc}/cryptroot ]] && cp -f  ${_backup_loc}/cryptroot /usr/share/initramfs-tools/scripts/local-top/cryptroot
    exit 1
  fi

  if ! createLegacyGrub /etc/grub.d/999_graphcore; then
    echo "Error adding grub entry, reverting!"
    revertLegacyGrub /etc/grub.d/999_graphcore
    exit 1
  fi

else if (( ${_revert} )); then
        ${_echo} 
        ${_echo} "Attempting to revert system"

        for file in ${_backup_files}; do
          if ! grep -q askpassfallback ${file} > /dev/null; then
            ${_echo} Update not applied!
            ${_echo} Exiting
            exit 0
          fi
        done

	revertCryptab
	revertCryptroot
	revertLegacyGrub /etc/grub.d/999_graphcore
     fi
fi

exit 0

# Fin.
