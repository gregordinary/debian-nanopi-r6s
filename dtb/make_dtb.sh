#!/bin/sh

# Copyright (C) 2023, John Clark <inindev@gmail.com>

set -e

# script exit codes:
#   1: missing utility
#   5: invalid file hash

main() {
    local linux='https://git.kernel.org/torvalds/t/linux-6.11-rc5.tar.gz'
    local lxsha='48a12488747ee494c312fb59cf8f070a7b1c0da1eaa563b558835e2003394999'

    local lf="$(basename "$linux")"
    local lv="$(echo "$lf" | sed -nE 's/linux-(.*)\.tar\..z/\1/p')"

    if is_param 'clean' "$@"; then
        rm -f *.dtb *-top.dts
        find . -maxdepth 1 -type l -delete
        rm -rf "linux-$lv"
        echo -e '\nclean complete\n'
        exit 0
    fi

    check_installed 'device-tree-compiler' 'gcc' 'wget' 'xz-utils'

    if ! [ -e "$lf" ]; then
        if [ -e "../kernel/$lf" ]; then
            echo -e "using local copy of linux $lv"
            cp -v "../kernel/$lf" .
        elif [ -e "../kernel/kernel-$lv/$lf" ]; then
            echo -e "using local copy of linux $lv"
            cp -v "../kernel/kernel-$lv/$lf" .
        else
            print_hdr "downloading linux $lv"
            wget "$linux"
        fi
    fi

    if [ "_$lxsha" != "_$(sha256sum "$lf" | cut -c1-64)" ]; then
        echo -e "invalid hash for linux source file: $lf"
        exit 5
    fi

    local rkpath="linux-$lv/arch/arm64/boot/dts/rockchip"
    if ! [ -d "linux-$lv" ]; then
        tar xavf "$lf" "linux-$lv/include/dt-bindings" "linux-$lv/include/uapi" "linux-$lv/drivers/clk/rockchip" "$rkpath"

        local patch patches="$(find patches -maxdepth 1 -name '*.patch' 2>/dev/null | sort)"
        for patch in $patches; do
            patch -p1 -d "linux-$lv" -i "../$patch"
        done
    fi

    if is_param 'links' "$@"; then
        local rkf rkfl='rk3588s-nanopi-r6s.dts rk3588s.dtsi rk3588-pinctrl.dtsi rockchip-pinconf.dtsi'
        for rkf in $rkfl; do
            ln -sfv "$rkpath/$rkf"
        done
        echo -e '\nlinks created\n'
        exit 0
    fi

    # build
    local dt dts='rk3588s-nanopi-r6s'
    local fldtc='-Wno-interrupt_provider -Wno-unique_unit_address -Wno-unit_address_vs_reg -Wno-avoid_unnecessary_addr_size -Wno-alias_paths -Wno-graph_child_address -Wno-simple_bus_reg'
    for dt in $dts; do
        gcc -I "linux-$lv/include" -E -nostdinc -undef -D__DTS__ -x assembler-with-cpp -o "${dt}-top.dts" "$rkpath/${dt}.dts"
        dtc -I dts -O dtb -b 0 ${fldtc} -o "${dt}.dtb" "${dt}-top.dts"
        is_param 'cp' "$@" && cp_to_debian "${dt}.dtb"
        echo -e "\n${cya}device tree ready: ${dt}.dtb${rst}\n"
    done
}

cp_to_debian() {
    local target="$1"
    local deb_dist=$(cat "../debian/make_debian_img.sh" | sed -n 's/\s*local deb_dist=.\([[:alpha:]]\+\)./\1/p')
    [ -z "$deb_dist" ] && return
    local cdir="../debian/cache.$deb_dist"
    echo -e '\ncopying to debian cache...'
    sudo mkdir -p "$cdir"
    sudo cp -v "$target" "$cdir"
}

is_param() {
    local item match
    for item in "$@"; do
        if [ -z "$match" ]; then
            match="$item"
        elif [ "$match" = "$item" ]; then
            return 0
        fi
    done
    return 1
}

# check if debian package is installed
check_installed() {
    local item todo
    for item in "$@"; do
        dpkg -l "$item" 2>/dev/null | grep -q "ii  $item" || todo="$todo $item"
    done

    if [ ! -z "$todo" ]; then
        echo -e "this script requires the following packages:${bld}${yel}$todo${rst}"
        echo -e "   run: ${bld}${grn}sudo apt update && sudo apt -y install$todo${rst}\n"
        exit 1
    fi
}

print_hdr() {
    local msg="$1"
    echo -e "\n${h1}$msg...${rst}"
}

rst='\033[m'
bld='\033[1m'
red='\033[31m'
grn='\033[32m'
yel='\033[33m'
blu='\033[34m'
mag='\033[35m'
cya='\033[36m'
h1="${blu}==>${rst} ${bld}"

cd "$(dirname "$(realpath "$0")")"
main "$@"
