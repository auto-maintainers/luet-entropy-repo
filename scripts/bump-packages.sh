#!/bin/bash

# Author: Daniele Rondina <geaaru@sabayonlinux.org>
# Description: Script for create luet specs for a list of packages
#              available through an entropy repository.

REPOSITORY=${REPOSITORY:-sabayonlinux.org}
TARGET_DIR=${TARGET_DIR:-tree/${REPOSITORY}}
PACKAGES=${PACKAGES:-""}
DOWNLOAD_LATEST_PKGS_CHECKER=${DOWNLOAD_LATEST_PKGS_CHECKER:-0}
DEBUG_BUMP=${DEBUG_BUMP:-0}
PARALLEL_ENABLE=${PARALLEL_ENABLE:-0}
PARALLEL_JOBS=${PARALLEL_JOBS:-40}
BACKGROUND_MODE=${BACKGROUND_MODE:-0}
#ENTROPY_DB=${ENTROPY_DB:-/var/lib/entropy/client/database/amd64/${REPOSITORY}/amd64/5/packages.db}
ENTROPY_DB=${ENTROPY_DB:-/var/lib/entropy/client/database/amd64/equo.db}
PKG_SLOT_SEPARATOR=${PKG_SLOT_SEPARATOR:--}


process_package () {
  local pkg=$1

  # Retrieve package detail
  local name=$(pkgs-checker pkg info $pkg | grep "name:" --color=none | awk '{ print $2 }')
  local cat=$(pkgs-checker pkg info $pkg | grep "category:" --color=none | awk '{ print $2 }')
  local version=$(pkgs-checker pkg info $pkg | grep "version:" --color=none | awk '{ print $2 }')
  local ver_suffix=$(pkgs-checker pkg info $pkg | grep "version_suffix" --color=none | awk '{ print $2 }')
  local ver_build=$(pkgs-checker pkg info $pkg | grep "version_build" --color=none | awk '{ print $2 }')
  local license=$(pkgs-checker entropy info $pkg -d ${ENTROPY_DB} | grep "license:" --color=none | sed -e 's|license: ||g')
  local uses=$(pkgs-checker entropy info $pkg -d ${ENTROPY_DB} | grep "uses" --color=none | sed -e 's|^uses: ||g')

  ver_suffix=${ver_suffix/-}
  ver_suffix=${ver_suffix/_}

  # Skip virtual packages
  if [[ $cat = "virtual" ]] ; then
    echo "Package $pkg is skipped."
    return 0
  fi

  local build_symbol=""
  if [[ -n "${ver_suffix}" || -n "${ver_suffix}" ]] ; then
    build_symbol="+"
  fi

  # Check if package is installed.
  local is_installed=$(qlist -ICvq | grep --color=none $pkg | wc -l)
  if [ "${is_installed}" = "0" ] ; then
    ACCEPT_LICENSE=* equo i $pkg || return 1
  fi

  # Check slot
  # equo seems slow!
  #local slot=$(equo search $pkg | grep Slot | awk '{ print $3 }')
  #local slot=$(equery list  -F 'SLOT $slot' $pkg 2>/dev/null | grep SLOT --color=none 2>/dev/null | awk '{ print $2 }' | sed 's/\x1B\[[0-9;]\+[A-Za-z]//g')
  local slot=$(pkgs-checker entropy info $pkg -d $ENTROPY_DB | grep slot | head -n 1 | awk '{ print $2 }')

  # Ignore sub-slot for now.
  slot=$(echo "${slot}" | sed 's:/.*::g')
  local luet_name="${name}"
  if [ "$slot" != "0" ] ; then
    luet_name="${name}${PKG_SLOT_SEPARATOR}${slot}"
  fi

  local pkgdir="${cat}/${luet_name}/${version}"

  echo "Analyzing package $pkg ..."

  # Check if package is already present
  if [ -d ${pkgdir} ] ; then

    # Check if version is different
    local cur_version="$(cat ${pkgdir}/definition.yaml  | shyaml get-value 'version')"
    if [ "$cur_version" = "${version}${build_symbol}${ver_suffix}${version_build}" ] ; then
      # nothing to do
      echo "Package $pkg is already present. Nothing to do."
      return 0
    fi
  fi

  # This is slow but if there aren package with deps not installed. This ensure to fetch all deps for
  # elaborate right deps info

  echo "Create package $pkg with dir ${pkgdir}..."

  mkdir -p ${pkgdir}

  includes=$(equo q files $pkg -q)

  deps=$(pkgs-checker entropy info -d ${ENTROPY_DB} --onlydeps $pkg)
  # deps=$(equery g $pkg -l -M -U --depth=3 -A | grep " \[" --color=none | awk '{ print $3 }' | sed 's/\x1B\[[0-9;]\+[A-Za-z]//g')
#  deps=$(equery g $pkg  -l --depth=2 2>/dev/null | grep " \[" --color=none | awk '{ print $3 }'  | sed 's/\x1B\[[0-9;]\+[A-Za-z]//g')

  echo "
category: \"${cat}\"
name: \"${luet_name}\"
version: \"${version}${build_symbol}${ver_suffix}${version_build}\"
license: \"${license}\"
" > $pkgdir/definition.yaml

  if [ "$uses" != "" ] ; then
    local uses_counter=0
    for u in ${uses} ; do
      if [ $uses_counter -eq 0 ] ; then
        let uses_counter++ || true
        echo "use_flags:" >> $pkgdir/definition.yaml
      fi

      echo "- \"${u}\"" >> $pkgdir/definition.yaml
    done
  fi

  # we need unpack: tree because also if package is reinstalled container has same files.
  echo "
unpack: true
steps:
- source /etc/profile && ACCEPT_LICENSE=* equo i ${pkg} && equo cleanup
requires:
- category: \"layer\"
  name: \"sabayon-base\"
  version: \"9999\"" > $pkgdir/build.yaml

  local inc_counter=0
  for inc in ${includes} ; do
    if [ $inc_counter -eq 0 ] ; then
      echo "includes:" >> $pkgdir/build.yaml
    fi
    let inc_counter++ || true
    # Check if include contains + char and fix regex
    inc=$(echo "$inc" | sed -e 's|\+|\[+\]|g')
    echo "- ${inc}$" >> $pkgdir/build.yaml
  done

  local dep_name=""
  local dep_cat=""
  local dep_version=""
  local dep_slot=""
  local dep_luet_name=""
  local dep_in_entropy=""
  local dep_entropy_pkgname=""
  local dep_num=0
  for dep in ${deps} ; do


    dep_name=$(pkgs-checker pkg info $dep | grep "name:" --color=none | awk '{ print $2 }' | sed 's/\x1B\[[0-9;]\+[A-Za-z]//g')
    dep_cat=$(pkgs-checker pkg info $dep | grep "category:" --color=none | awk '{ print $2 }' | sed 's/\x1B\[[0-9;]\+[A-Za-z]//g')
    dep_slot=$(pkgs-checker pkg info $dep | grep "slot:" --color=none | awk '{ print $2 }' | sed 's/\x1B\[[0-9;]\+[A-Za-z]//g')
    # Ignore sub-slot for now.
    dep_slot=$(echo "${dep_slot}" | sed 's:/.*::g')
    dep_version=$(pkgs-checker pkg info $dep | grep "version:" --color=none | awk '{ print $2 }' | sed 's/\x1B\[[0-9;]\+[A-Za-z]//g')

    dep_condition=$(pkgs-checker pkg info $dep | grep "condition:" --color=none | awk '{ print $2 }')

    if [ "${dep_cat}/${dep_name}" = "${cat}/${name}" ] ; then
      continue
    fi

    if [ "${dep_cat}" = "virtual" ] ; then
      continue
    fi

    # Workaround for fix python slot issues of pkgs-checker entropy info
    if [[ "${dep_cat}" = "dev-lang" && "${dep_name}" = "python" ]] ; then
      if [[ "${dep_version}" = 2.7* ]] ; then
        dep_slot="2.7"
      else
        dep_slot="3.6"
      fi
    fi

    dep_luet_name="${dep_name}"

    if [ "$DEBUG_BUMP" = "1" ] ; then
      echo "Found dep ${dep}, slot ${dep_slot} and luet name ${dep_luet_name}..."
    fi

    is_installed=$(qlist -ICvq | grep --color=none ${dep_cat}/${dep_name} | wc -l)
    if [ "${is_installed}" = "0" ] ; then
      ACCEPT_LICENSE=* equo i ${dep_cat}/${dep_name} || return 1
    fi

    if [ "${dep_slot}" != "0" ] ; then
      dep_luet_name="${dep_name}${PKG_SLOT_SEPARATOR}${dep_slot}"
    fi

    if [ $dep_num -eq 0 ] ; then
      echo "requires:" >> $pkgdir/definition.yaml
      let dep_num++
    fi

    if [ "${dep_version}" = "" ] ; then
      dep_version="0"
    fi

    if [[ "${dep_condition}" = "=" || "${dep_condition}" = "" ]] ; then
      dep_condition=">="
    fi
    if [[ "${dep_condition}" = "=*" || "${dep_condition}" = "~" ]] ; then
      dep_condition=">="
    fi

    if [ "$DEBUG_BUMP" = "1" ] ; then
      echo "Use entropy dep ${dep}, with version ${dep_version} ..."
    fi
    echo "- category: \"${dep_cat}\"
  name: \"${dep_luet_name}\"
  version: \"${dep_condition}${dep_version}\"" >> $pkgdir/definition.yaml
  done

  echo "1" > ${COUNTERDIR}/${cat}-${name}-${version}

  return 0
}

process_packages () {

  if [ -z "${PACKAGES}" ] ; then
    # I use installed packages
    PACKAGES=$(equo q list installed ${REPOSITORY} -q -v)
  fi

  COUNTERDIR=$(mktemp -d)

  if [ "$PARALLEL_ENABLE" = "1" ] ; then
    export COUNTERDIR
    export DEBUG_BUMP
    export ENTROPY_DB
    export REPOSITORY
    export PKG_SLOT_SEPARATOR
    export -f process_package
    parallel -j ${PARALLEL_JOBS} --will-cite -k process_package ::: ${PACKAGES}
  else
    for p in ${PACKAGES} ; do
      if [ $BACKGROUND_MODE = "1" ] ; then
        process_package $p &
      else
        process_package $p
      fi
    done

    wait
  fi

  local N_PKGS=$(ls -l ${COUNTERDIR} | wc -l)

  echo "Added ${N_PKGS} packages!"

  rm -rf ${COUNTERDIR}

  return 0
}

main () {

  if [ ! -e $TARGET_DIR ] ; then
    mkdir -p ${TARGET_DIR}
  fi

  if [ ${DOWNLOAD_LATEST_PKGS_CHECKER} = "1" ] ; then
    # Download latest version of pkgs-checker
    wget https://dispatcher.sabayon.org/sbi/namespace/pkgs-checker-cross-bin/pkgs-checker-latest-linux-amd64 -O /usr/bin/pkgs-checker
    chmod a+x /usr/bin/pkgs-checker
  fi

  pushd ${TARGET_DIR}
    process_packages || return 1
  popd

  return 0
}

main
exit $?
