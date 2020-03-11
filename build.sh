#!/bin/bash

set -e -u

if [ -f config.conf ]; then
    . config.conf
else 
    echo "Fatal error, No config file found."
    exit 1
fi

umask 0022


_usage ()
{
    echo "usage ${0} [options]"
    echo
    echo " General options:"
    echo "    -N <iso_name>      Set an iso filename (prefix)"
    echo "                        Default: ${iso_name}"
    echo "    -V <iso_version>   Set an iso version (in filename)"
    echo "                        Default: ${iso_version}"
    echo "    -L <iso_label>     Set an iso label (disk label)"
    echo "                        Default: ${iso_label}"
    echo "    -P <publisher>     Set a publisher for the disk"
    echo "                        Default: '${iso_publisher}'"
    echo "    -A <application>   Set an application name for the disk"
    echo "                        Default: '${iso_application}'"
    echo "    -D <install_dir>   Set an install_dir (directory inside iso)"
    echo "                        Default: ${install_dir}"
    echo "    -w <work_dir>      Set the working directory"
    echo "                        Default: ${work_dir}"
    echo "    -o <out_dir>       Set the output directory"
    echo "                        Default: ${out_dir}"
    echo "    -v                 Enable verbose output"
    echo "    -h                 This help message"
    exit ${1}
}


# Helper function to run make_*() only one time per architecture.
run_once() {
    if [[ ! -e ${work_dir}/build.${1} ]]; then
        $1 | tee ${work_dir}/build.log
        touch ${work_dir}/build.${1}
    fi
}

# Install tools for build iso etc
make_tools() {
    echo 
    echo ">>> Installing tools for building everything!"
    echo
    apt-get install -y debootstrap squashfs-tools xorriso grub-pc-bin grub-efi-amd64-bin mtools syslinux isolinux 
    echo "Done!"
    echo
}

# Base installation
make_basefs() {
    echo
    echo ">>> Install the base sys now, for building squashfile.system"
    echo
    sleep 3
    if [ -d ${work_dir}/$arch ]; then 
        echo "Looks like base system already installed, skip!"
    else 
        debootstrap --arch=$arch  --variant=minbase  buster ${work_dir}/$arch http://mirrors.aliyun.com/debian/ 
    fi
}

make_packages() {
    echo 
    echo ">>> Install some packages."   
    echo
    chroot ${work_dir}/$arch apt-get update
    for package in $packages; do
        chroot ${work_dir}/$arch apt-get install $package -y
    done
    echo "    Packages installion is done!"
    echo
}


make_custom() {
    echo
    echo ">>> Customizing Live system now."
    echo
    echo "Update hostname: $hostname"
    echo "$hostname" > ${work_dir}/$arch/etc/hostname
    echo "Update password: $password"
    sleep 2
    echo "root:$password" > ${work_dir}/tmp.txt
    chroot ${work_dir}/$arch chpasswd < ${work_dir}/tmp.txt
    rm -f ${work_dir}/tmp.txt
}

get_kernel_intrd(){
    echo ">>>Create iso root file dir "
    echo
    if [ ! -d ${work_dir}/iso/live ]; then
        echo "Create dir: live"
        mkdir -p ${work_dir}/iso/live
    fi

    chroot ${work_dir}/$arch apt-get install linux-image-amd64 live-boot systemd-sysv -y
    if [ ! -f ${work_dir}/iso/live/vmlinuz ]; then
        cp ${work_dir}/$arch/boot/vmlinuz-* ${work_dir}/iso/live/vmlinuz  
    fi
    
    if [ ! -f ${work_dir}/iso/live/initrd.gz ]; then
        echo "Modifying initrd to deal amaxscripts.zip"
        sleep 2 
        if [ ! -d ${work_dir}/tmp/temp ]; then
            echo "create tmp folder"
            mkdir -p ${work_dir}/tmp/temp
        else
            echo "tmp exists, delete!"
	    rm -fr ${work_dir}/tmp
	    mkdir -p ${work_dir}/tmp/temp
        fi

	echo ">>>Copy the initrd.gz now"
        cp ${work_dir}/$arch/boot/initrd.img-* ${work_dir}/tmp/initrd.gz  
	echo ">>>Modify now"
	sleep 2
	zcat ${work_dir}/tmp/initrd.gz | cpio -idmv --directory=work/tmp/temp
	rm -f ${work_dir}/tmp/temp/init
        cp iso/needed/init ${work_dir}/tmp/temp/init
	cd ${work_dir}/tmp/temp/
	find . | cpio --create --format='newc' | gzip > ../initrd.gz
	cd $working_dir
	mv ${work_dir}/tmp/initrd.gz ${work_dir}/iso/live/initrd.gz
		
    fi 
	
}

make_mksquashfs() {
    if [ -f ${work_dir}/iso/live/filesystem.squashfs ]; then
        echo "Deleting the old one: filesystem.squashfs."
	rm -f ${work_dir}/iso/live/filesystem.squashfs
    fi
    echo ">>> Create filesystem.squashfs, please wait"
    echo
    sleep 3
    mksquashfs ${work_dir}/$arch ${work_dir}/iso/live/filesystem.squashfs -e boot
}

make_isolinux() {
    echo "Copy isolinux files"
    sleep 2
    mkdir -p ${work_dir}/iso/boot/isolinux
    cp iso/isolinux/* ${work_dir}/iso/boot/isolinux/

}


make_efi() {
    if [ ! -d  ${work_dir}/iso/EFI/boot ]; then
       echo "Creating boot dir"
       mkdir -p ${work_dir}/iso/EFI/boot
    fi
    echo ">>>Creating EFI booting file now"
    sleep 4    
	grub-mkstandalone --directory="/usr/lib/grub/x86_64-efi" --format=x86_64-efi --output=${work_dir}/iso/EFI/boot/bootx64.efi     --modules="linux normal iso9660 efi_uga efi_gop fat chain disk exfat usb multiboot msdospart part_msdos part_gpt search part_gpt configfile ext2 boot gfxterm_background gfxterm_menu gfxterm echo all_video videoinfo png jpeg" "/boot/grub/grub.cfg=/tmp/grub.cfg"

    (dd if=/dev/zero of=${work_dir}/iso/EFI/efiboot.img bs=1M count=100 && mkfs.vfat ${work_dir}/iso/EFI/efiboot.img && mmd -i ${work_dir}/iso/EFI/efiboot.img efi efi/boot efi/boot/grub &&  mcopy -i ${work_dir}/iso/EFI/efiboot.img ${work_dir}/iso/EFI/boot/bootx64.efi ::efi/boot/ )
echo ">>>copy some files"
   cp iso/EFI/boot/amaxbp.png ${work_dir}/iso/EFI/boot/
   cp iso/EFI/boot/grub_amax.cfg ${work_dir}/iso/EFI/boot/
   cp iso/EFI/boot/unicode.pf2  ${work_dir}/iso/EFI/boot/

}

make_iso() {
  echo ">>> copy some files, almost done."
  sleep 3
  cp iso/live/amaxscripts.zip ${work_dir}/iso/live/
  cp iso/live/memtest ${work_dir}/iso/live/
  cp iso/live/memtest86 ${work_dir}/iso/live/ 
  cp iso/AMAX.file ${work_dir}/iso/
echo ">>>Trying to make am iso, wait"
sleep 3

xorriso -as mkisofs -iso-level 3 -full-iso9660-filenames -volid "$iso_label"     -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin -eltorito-boot boot/isolinux/isolinux.bin  -no-emul-boot -boot-load-size 4 -boot-info-table --eltorito-catalog boot/isolinux/isolinux.cat     -eltorito-alt-boot  -e EFI/efiboot.img         -no-emul-boot -isohybrid-gpt-basdat     -output "${work_dir}/${iso_name}-${iso_version}.iso"     "${work_dir}/iso"


}

if [[ ${EUID} -ne 0 ]]; then
    echo "This script must be run as root."
    _usage 1
fi

while getopts 'N:V:L:P:A:D:w:o:g:vh' arg; do
    case "${arg}" in
        N) iso_name="${OPTARG}" ;;
        V) iso_version="${OPTARG}" ;;
        L) iso_label="${OPTARG}" ;;
        P) iso_publisher="${OPTARG}" ;;
        A) iso_application="${OPTARG}" ;;
        D) install_dir="${OPTARG}" ;;
        w) work_dir="${OPTARG}" ;;
        o) out_dir="${OPTARG}" ;;
        g) gpg_key="${OPTARG}" ;;
        h) _usage 0 ;;
        *)
           echo "Invalid argument '${arg}'"
           _usage 1
           ;;
    esac
done

mkdir -p ${work_dir}
working_dir=`pwd`
echo "***************************************"
echo "Working dir is $working_dir"
echo "***************************************"
sleep 2

run_once make_tools
run_once make_basefs
run_once make_packages
run_once get_kernel_intrd
run_once make_custom
run_once make_mksquashfs
run_once make_isolinux
run_once make_efi
run_once make_iso

