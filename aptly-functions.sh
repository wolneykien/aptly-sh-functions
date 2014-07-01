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

# Returns the base part from the given repository (or snapshot) name.
# The name of the repo should be composed of the basename,
# architecture and component parts joined with hyphen.
#
# args: base-arch-component[-suffix]
# outputs: base
#
get_repo_base_name() {
    echo "${1%%-*}"
}

# Returns the architecture part from the given repository (or
# snapshot) name. The name of the repo should be composed of the
# basename, architecture and component parts joined with hyphen.
#
# args: base-arch-component[-suffix]
# outputs: arch
#
get_repo_arch_name() {
    local tmp="${1#*-}"
    echo "${tmp%%-*}"
}

# Returns the component part from the given repository name.
# The name of the repo should be composed of the basename,
# architecture and component parts joined with hyphen.
#
# args: base-arch-component
# outputs: component
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
# outputs: snapshot-name
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
# passing `-s suffix` as the first two arguments.
#
# args: [-s suffix] repo1 repo2 ...
# outputs: snapshot-name
#
aptly_snapshot_multiarch() {
    [ $# -gt 0 ] || return 0

    local suf=
    if [ "${1:-}" = "-s" ]; then
        suf="$2"; shift; shift
    else
        suf="$(date +%Y%m%d)"
    fi

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

# Returns the suffix part of the given snapshot name.
# Warning: actually returns the part of the name after the last
# hyphen.
#
# args: snapshot-name
#
get_snapshot_suffix() {
    echo "${1##*-}"
}

# Returns the repository name for the given snapshot name.
# Warning: actually returns the original name with the part after the
# last hyphen removed.
#
# args: snapshot-name
#
get_snapshot_repo() {
    echo "${1%-*}"
}

# Removes the snapshot with the given name.
#
# args: snapshot-name
#
aptly_snapshot_drop() {
    if aptly_is_published "$1"; then
        echo "Snapshot is published: $1" >&2
        return 1
    fi
    aptly snapshot drop "$1" 2>/dev/null 1>&2
}

# Removes the repo with the given name.
#
# args: repo-name
#
aptly_repo_drop() {
    if aptly_is_published "$1"; then
        echo "Repo is published: $1" >&2
        return 1
    fi
    aptly repo drop "$1" 2>/dev/null 1>&2
}

# Outputs all of the snapshot names known to aptly.
#
# outputs: name-1\n name-2\n...
#
aptly_list_snapshots() {
    aptly snapshot list | sed -n -e 's/^[[:space:]]\+\*[[:space:]]\+\[\([^]]\+\)\].*$/\1/p'
}

# Outputs all of the repository names known to aptly.
#
# outputs: name-1\n name-2\n...
#
aptly_list_repos() {
    aptly repo list | sed -n -e 's/^[[:space:]]\+\*[[:space:]]\+\[\([^]]\+\)\].*$/\1/p'
}

# Outputs all of the publication names known to aptly.
# If a set of snapshot or repository names is passed then lists only
# those names under which the given set is published.
#
# args: [repo-or-snapshot-1 repo-or-snapshot-2...]
# outputs: name-1\n name-2\n...
#
GETPUBNAME='s/^[[:space:]]\+\*[[:space:]]\+\([^[:space:]]\+\).*$/\1/p'
aptly_list_pubs() {
    if [ $# -eq 0 ]; then
        aptly publish list | sed -n -e "$GETPUBNAME"
    else
        local regex='publishes'
        for n in "$@"; do
            regex="$regex.*[[:space:]]*{[^[}]*\\[$n\\][^}]*}"
        done
        aptly publish list | sed -n -e "/$regex/! d" -e "$GETPUBNAME"
    fi
}

# Checks if the given repository, snapshot or set of such
# is published.
#
# args: repo-or-snapshot-1 [repo-or-snapshot-2...]
#
aptly_is_published() {
    [ $(aptly_list_pubs "$@" | wc -l) -gt 0 ]
}

# Removes the multiarch snapshot with the given name along with
# snapshots it is derived from.
#
# args: snapshot-name
#
aptly_multiarch_drop() {

    if ! aptly_snapshot_exists "$1"; then
        echo "Snapshot doesn't exist: $1" >&2
        return 1
    fi

    if aptly_is_published "$1"; then
        echo "Snapshot is published: $1" >&2
        return 1
    fi

    local base="$(get_repo_base_name "$1")"

    if [ -z "$base" ]; then
        echo "Malformed snapshot name, no base: $1" >&2
        return 1
    fi

    local rest="${1#*-}"

    if [ -z "$rest" ]; then
        echo "Malformed snapshot name, only base: $1" >&2
        return 1
    fi

    aptly_snapshot_drop "$1" && \
        aptly_list_snapshots | grep "^$base-[^-]\\+-$rest\$" | \
            while read m; do
                if aptly_snapshot_exists "$m"; then
                    aptly_snapshot_drop "$m" || exit $?
                fi
            done
}

# Publishes the set of multiarch snapshots with the given names.
# The first snapshot suffix is used as the publication prefix and
# its base name is used as the distribution name. The componet parts
# of the given names are used as publication components so each value
# should be uniue within the list.

# Outputs the publication name in the form: 'prefix/distribution'.
#
# args: snapshot-1 [snapshot-2...]
# outputs: prefix/distribution
#
aptly_publish_multiarch() {
    local prefix="$(get_snapshot_suffix "$1")"
    local base="$(get_repo_base_name "$1")"
    
    if [ -z "$prefix" ]; then
        echo "Malformed snapshot name, no suffix: $1" >&2
        return 1
    fi
    if [ -z "$base" ]; then
        echo "Malformed snapshot name, no base: $1" >&2
        return 1
    fi

    if aptly_pub_exists "$prefix/$base"; then
        echo "Publication already exists: $prefix/$base"
        return 1
    fi

    local comps=
    for sn in "$@"; do
        if ! aptly_snapshot_exists "$sn"; then
            echo "Snapshot doesn't exist: $sn" >&2
            return 1
        fi
        sn="${sn%-*}"
        comps="$comps,${sn#*-}"
    done
    comps="${comps#,}"

    aptly publish snapshot \
        --component="$comps" \
        --distribution="$base" \
        "$@" \
        "$prefix" \
        2>/dev/null 1>&2
}

# Outputs the names of the repositories/snapshots that are published
# under the given name.
#
# args: prefix/distribution
# outputs: name-1\n name-2\n...
#
aptly_list_pub_repos() {
    local pub="$(echo "$1" | sed -e 's,/,\\/,g')"

    aptly publish list | sed -n -e "/^[[:space:]]\\+\\*[[:space:]]\\+$pub[[:space:]]\\+/ { s/^[^{]\\+[[:space:]]publishes[[:space:]]\\+//; s/{[^[]\\+\\[//g; s/\\][^}]\\+}//g; s/,[[:space:]]/\\n/g; p; q }"
}

# Checks if the given publication name is known to aptly.
#
# args: prefix/distribution
#
aptly_pub_exists() {
    local pub="$(echo "$1" | sed -e 's,/,\\/,g')"

    aptly publish list | grep -q "^[[:space:]]\\+\\*[[:space:]]\\+$pub[[:space:]]\\+"
}

# Removes the repo/snapshot publication with the given name.
# The name should be of the form prefix/distribution as
# returned by `aptly_publish_multiarch`.
#
# With the -a option passed as the first argument also drops
# all the snapshots that are published under the given name along
# with snapshots they are derived from.
#
# args: [-a] prefix/distribution
#
aptly_pub_drop() {
    local all=
    local repos=

    if [ "${1:-}" = "-a" ]; then
        all=-a; shift
        repos="$(aptly_list_pub_repos "$1")"
    fi

    if ! aptly_pub_exists "$1"; then
        echo "Publication doesn't exist: $1" >&2
        return 1
    fi

    aptly publish drop "${1#*/}" "${1%/*}" 2>/dev/null 1>&2 || return $?

    if [ -n "$all" ]; then
        echo "$repos" | while read sn; do
            if aptly_snapshot_exists "$sn"; then
                aptly_multiarch_drop "$sn" || exit $?
            fi
        done
    fi
}
