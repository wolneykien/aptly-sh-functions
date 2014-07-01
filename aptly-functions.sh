#!/bin/sh
#
# Copyright (C) 2014  Paul Wolneykien <wolneykien@gmail.com>
#
# This file is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
#

# Checks if the specified repository is registered with aptly.
#
# args: repo-name
#
aptly_repo_exists() {
    aptly repo show "$1" 2>/dev/null 1>&2
}

# Gets the base part from the given repository name.
# The name of the repo should be composed of the
# basename, architecture and component parts joined
# with the hyphen.
#
# args: base-arch-component
#
get_repo_base_name() {
    echo "${1%%-*}"
}

# Gets the architecture part from the given repository name.
# The name of the repo should be composed of the
# basename, architecture and component parts joined
# with the hyphen.
#
# args: base-arch-component
#
get_repo_arch_name() {
    local tmp="${1#*-}"
    echo "${tmp%%-*}"
}

# Gets the component part from the given repository name.
# The name of the repo should be composed of the
# basename, architecture and component parts joined
# with the hyphen.
#
# args: base-arch-component
#
get_repo_comp_name() {
    local tmp="${1#*-}"
    echo "${tmp#*-}"
}

# Creates an empty repository with the given name.
# The name of the repo should be composed of the
# basename, architecture and component parts joined
# with the hyphen.
#
# args: base-arch-component
#
aptly_repo_create() {
    local base="$(get_repo_base_name "$1")"
    local arch="$(get_repo_arch_name "$1")"
    local comp="$(get_repo_comp_name "$1")"

    if [ -z "$base" ]; then
        echo "Malformed repository name, no base: $1" >&2
        return 1
    fi
    if [ -z "$arch" ]; then
        echo "Malformed repository name, no arch: $1" >&2
        return 1
    fi
    if [ -z "$comp" ]; then
        echo "Malformed repository name, no comp: $1" >&2
        return 1
    fi

    aptly repo create \
        --architectures="$arch" \
        --comment="The \"$base\" package repository ($arch, $comp)" \
        --component="$comp" \
        --distribution="$base" \
        "$1" \
        2>/dev/null \
        1>&2
}

# Checks if the specified repository snapshot is registered with
# aptly.
#
# args: snapshot-name
#
aptly_snapshot_exists() {
    aptly snapshot show "$1" 2>/dev/null 1>&2
}

# Creates a snapshot of the given repository. The name of the new
# snapshot is the repository name with the current date appended.
# Optionally the suffix can be specified explicitly.
#
# args: repository-name [suffix]
# returns: snapshot-name
#
aptly_snapshot_repo() {
    local sn="$1-${2:-$(date +%Y%m%d)}"

    if ! aptly_repo_exists "$1"; then
        echo "Repository doesn't exist: $1" >&2
        return 1
    fi
    if aptly_snapshot_exists "$sn"; then
        echo "Snapshot already exists: $sn"
        return 1
    fi

    aptly snapshot create "$sn" from repo "$1" 2>/dev/null 1>&2 && \
        echo "$sn"
}

# Creates a united snapshot for the given set of repositories.
# Snapthots each of the given repositories and merges them into
# one. The name of the resulting united snapshot is the name
# of the first repository lacking its 'arch' part and the current date
# appended. Optionally the suffix can be specified explicitly by
# passing `-s suffix` as the last two arguments.
#
# args: repo1 repo2 ... [-s suffix]
# returns: snapshot-name
#
aptly_snapshot_multiarch() {
    [ $# -gt 0 ] || return 0

    local args="$*"
    local suf="${args##* -s }"
    [ "$suf" != "$args" ] || suf="$(date +%Y%m%d)"

    for r in "$@"; do
        if ! aptly_repo_exists "$r"; then
            echo "Repository doesn't exist: $r" >&2
            return 1
        fi
    done

    local sn="$(get_repo_base_name "$1")-$(get_repo_comp_name "$1")-$suf"
    if aptly_snapshot_exists "$sn"; then
        echo "Snapshot already exists: $sn"
        return 1
    fi

    local sns=
    for r in "$@"; do
        if ! aptly_snapshot_exists "$r-$suf"; then
            aptly snapshot create "$r-$suf" from repo "$r" \
                2>/dev/null 1>&2 \
                || return $?
        fi
        sns="$sns $r-$suf"
    done

    aptly snapshot merge "$sn" $sns 2>/dev/null 1>&2 && \
        echo "$sn"
}
