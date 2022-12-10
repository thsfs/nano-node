#!/bin/bash

# This script gets the last DB tag for the next release version and checks whether the develop branch contains new
# commits since the last develop build. If so, it sets and exports the variable $build_tag with the correct numbering
# for the next DB build.
# If the option -r is set, then it looks for the latest release branch, that is numbered as '<current major version>-1'.
# The -r option also exports the release branch name as $release_branch.
# Error exit codes:
# 0: success, the build tag was generated!
# 1: branch error or invalid usage of the script.
# 2: no new change found since the last build.

set +o errexit

source_dir="$(pwd)"
git_upstream="origin"
previous_release_gen=false

function print_usage {
    echo "$(basename ${0}) [OPTIONS]"
    echo "OPTIONS:"
    echo "  [-h]                 Print this help info."
    echo "  [-s <source_dir>]    Directory that contains the source-code. Default is \$PWD."
    echo "  [-u <git_upstream>]  Name of the git repository upstream. Default is \"${git_upstream}\"."
    echo "  [-r]                 Generates build tag for the latest release branch."
}

while getopts 'hs:u:r' OPT; do
    case "${OPT}" in
    h)
        print_usage
        exit 0
        ;;
    s)
        source_dir="${OPTARG}"
        if [[ ! -d "$source_dir" ]]; then
            echo "Invalid source directory"
            exit 1
        fi
        ;;
    u)
        git_upstream="${OPTARG}"
        if [[ -z "$git_upstream" ]]; then
            echo "Invalid git upstream"
            exit 1
        fi
        ;;
    r)
        previous_release_gen=true
        ;;
    *)
        print_usage >&2
        exit 1
        ;;
    esac
done

function get_first_item {
    local list="${1}"
    for item in $list; do
        if [[ -n "$item" ]]; then
            echo "$item"
            break
        fi
    done
}

set -o nounset
set -o xtrace

current_version_major=$(grep -P "(set)(.)*(CPACK_PACKAGE_VERSION_MAJOR)" "${source_dir}/CMakeLists.txt" | grep -oP "([0-9]+)")
current_version_minor=$(grep -P "(set)(.)*(CPACK_PACKAGE_VERSION_MINOR)" "${source_dir}/CMakeLists.txt" | grep -oP "([0-9]+)")
current_version_pre_release=$(grep -P "(set)(.)*(CPACK_PACKAGE_VERSION_PRE_RELEASE)" "${source_dir}/CMakeLists.txt" | grep -oP "([0-9]+)")

version_tags=$(git tag | sort -V -r | grep -E "^(V([0-9]+).([0-9]+)(RC[0-9]+)?)$")
last_tag=$(get_first_item "$version_tags")
tag_version_major=$(echo "$last_tag" | grep -oP "\V([0-9]+)\." | grep -oP "[0-9]+")
if [[ ${tag_version_major} -ge ${current_version_major} ]]; then
    echo "This is not the develop branch or your higher tag version is not equivalent to the current major version."
    exit 1
fi

if [[ ${current_version_minor} != "0" ]]; then
    echo "This is not the develop branch or the version-minor number is not properly set."
    exit 1
fi

if [[ ${current_version_pre_release} != "99" ]]; then
    echo "This is not the develop branch or the pre-release version is not properly set."
    exit 1
fi

pushd "$source_dir"

last_tag=""
version_tags=""
previous_release_major=0
previous_release_minor=0
if [[ $previous_release_gen == false ]]; then
    version_tags=$(git tag | sort -V -r | grep -E "^(V(${current_version_major}).(${current_version_minor})(DB[0-9]+))$" || true)
    last_tag=$(get_first_item "$version_tags")
else
    previous_release_major=$(( current_version_major - 1 ))
    version_tags=$(git tag | sort -V -r | grep -E "^(V(${previous_release_major}).([0-9]+)(DB[0-9]+)?)$" || true)
    last_tag=$(get_first_item "$version_tags")
    previous_release_minor=$(echo "$last_tag" | grep -oP "\.([0-9]+)" | grep -oP "[0-9]+")
fi
popd

build_tag=""
if [[ -z "$last_tag" ]]; then
    echo "No tag found"
    export build_number=1
    if [[ $previous_release_gen == false ]]; then
        export build_tag="V${current_version_major}.${current_version_minor}DB${build_number}"
    else
        export build_tag="V${previous_release_major}.${previous_release_minor}DB${build_number}"
    fi
    exit 0
fi

pushd "$source_dir"
develop_head=""
if [[ $previous_release_gen == false ]]; then
    develop_head=$(git rev-parse "${git_upstream}/develop")
else
    export release_branch="releases/v${previous_release_major}"
    develop_head=$(git rev-parse "${git_upstream}/${release_branch}")
fi
tag_head=$(git rev-list "$last_tag" | head -n 1)
popd

if [[ "$develop_head" == "$tag_head" ]]; then
    echo "No new commits for the develop build, the develop (or release) branch head matches the latest DB tag head!"
    exit 2
fi

latest_build_number=$(echo "$last_tag" | grep -oP "(DB[0-9]+)" | grep -oP "[0-9]+")
export build_number=$(( latest_build_number + 1 ))
if [[ $previous_release_gen == false ]]; then
    export build_tag="V${current_version_major}.${current_version_minor}DB${build_number}"
else
    export build_tag="V${previous_release_major}.${previous_release_minor}DB${build_number}"
fi

set +o nounset
set +o xtrace
