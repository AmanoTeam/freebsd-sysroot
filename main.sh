#!/usr/bin/env bash

set -eu

declare -r workdir="${PWD}"
declare -r temporary_directory='/tmp/freebsd-sysroot'

[ -d "${temporary_directory}" ] || mkdir "${temporary_directory}"

cd "${temporary_directory}"

declare -r targets=(
	'riscv/riscv64'
	'amd64'
	'arm64'
	'i386'
	'powerpc/powerpc'
	'powerpc/powerpc64'
	'powerpc/powerpc64_elfv2'
	'sparc64/sparc64'
)

for target in "${targets[@]}"; do
	declare version='12.3-RELEASE'
	
	if [ "${target}" = 'riscv/riscv64' ]; then
		version='14.2-RELEASE'
	elif [ "${target}" = 'powerpc/powerpc64_elfv2' ]; then
		version='13.0-RELEASE'
	fi
	
	declare url="http://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/$(cut -d '_' -f '1' <<< "${target}")/${version}/base.txz"
	declare output="/tmp/freebsd-${target//\//_}-base.tar.xz"
	
	case "${target}" in
		amd64)
			declare triplet='x86_64-unknown-freebsd12.3';;
		arm64)
			declare triplet='aarch64-unknown-freebsd12.3';;
		i386)
			declare triplet='i386-unknown-freebsd12.3';;
		powerpc/powerpc)
			declare triplet='powerpc-unknown-freebsd12.3';;
		powerpc/powerpc64)
			declare triplet='powerpc64-unknown-freebsd12.3';;
		powerpc/powerpc64_elfv2)
			declare triplet='powerpc64-unknown-freebsd13.0';;
		riscv/riscv64)
			declare triplet='riscv64-unknown-freebsd14.2';;
		sparc64/sparc64)
			declare triplet='sparc64-unknown-freebsd12.3';;
	esac
	
	declare sysroot_directory="${workdir}/${triplet}"
	declare tarball_filename="${sysroot_directory}.tar.xz"
	
	[ -d "${sysroot_directory}" ] || mkdir "${sysroot_directory}"
	
	echo "- Generating sysroot for ${triplet}"
	
	if [ -f "${tarball_filename}" ]; then
		echo "+ Already exists. Skip"
		continue
	fi
	
	echo "- Fetching data from ${url}"
	
	curl \
		--url "${url}" \
		--retry '30' \
		--retry-all-errors \
		--retry-delay '0' \
		--retry-max-time '0' \
		--location \
		--silent \
		--output "${output}"
	
	echo "- Unpacking ${output}"
	
	tar --directory="${sysroot_directory}" --strip=2 --extract --file="${output}" './usr/lib' './usr/include' 2>/dev/null
	tar --directory="${sysroot_directory}" --extract --file="${output}"  './lib' 2>/dev/null
	
	
	rm \
		--force \
		--recursive \
		"${sysroot_directory}/lib/clang" \
		"${sysroot_directory}/lib/libxo" \
		"${sysroot_directory}/lib/test.enc" \
		"${sysroot_directory}/lib/nvmecontrol" \
		"${sysroot_directory}/lib/geom" \
		"${sysroot_directory}/lib/aout" \
		"${sysroot_directory}/lib/compat" \
		"${sysroot_directory}/lib/dtrace" \
		"${sysroot_directory}/lib/engines" \
		"${sysroot_directory}/lib/flua" \
		"${sysroot_directory}/lib/i18n" \
		"${sysroot_directory}/lib/include" \
		"${sysroot_directory}/lib/libc++"* \
		"${sysroot_directory}/include/c++"
	
	cd "${sysroot_directory}/lib"
	
	if [ -d './casper' ]; then
		ln --symbolic --force './casper/libcap'* './'
	fi
	
	chmod 777 './libc.so'
	
	if [ "${target}" = 'riscv/riscv64' ] || [ "${target}" = 'powerpc/powerpc64_elfv2' ]; then
		echo 'GROUP ( ./libc.so.7 ./libc_nonshared.a )' > './libc.so'
	else
		echo 'GROUP ( ./libc.so.7 ./libc_nonshared.a ./libssp_nonshared.a )' > './libc.so'
	fi
	
	chmod 444 './libc.so'
	
	find . -type l | xargs ls -l | grep '/lib/' | awk '{print "unlink "$9" && ln -s $(basename "$11") $(basename "$9")"}' | bash 
	
	cd "${temporary_directory}"
	
	rm --force --recursive ./*
	
	echo "- Creating tarball at ${tarball_filename}"
	
	tar --directory="$(dirname "${sysroot_directory}")" --create --file=- "$(basename "${sysroot_directory}")" | xz  --compress -9 > "${tarball_filename}"
	sha256sum "${tarball_filename}" | sed "s|$(dirname "${sysroot_directory}")/||" > "${tarball_filename}.sha256"
	
	rm --force --recursive "${sysroot_directory}"
	unlink "${output}"
done